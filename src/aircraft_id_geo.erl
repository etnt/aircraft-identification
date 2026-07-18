%%%-------------------------------------------------------------------
%%% @doc Pure geometry, normalization, ranking and confidence logic.
%%%
%%% Everything in this module is side-effect free so the bulk of the
%%% feature can be tested under desktop Erlang without any network
%%% access. It converts OpenSky state vectors into candidate maps,
%%% computes distance/bearing/elevation relative to an observer, filters
%%% and ranks candidates, and assigns a confidence label.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_geo).

-export([
    bounding_box/3,
    distance_km/4,
    bearing_deg/4,
    elevation_deg/2,
    parse_state/1,
    select/4
]).

-define(EARTH_KM, 6371.0088).
-define(KM_PER_DEG_LAT, 111.32).

-type observer() :: #{lat := number(), lon := number(), elev := number()}.
-type candidate() :: map().
-type selection() :: #{
    confidence := high | medium | ambiguous | none,
    candidate := candidate() | null,
    alternatives := [candidate()]
}.

-export_type([observer/0, candidate/0, selection/0]).

%%====================================================================
%% Bounding box
%%====================================================================

%% Build the OpenSky bounding box for a search radius (km) around a point.
%% Longitude is not clamped; antimeridian handling is out of scope for MVP.
-spec bounding_box(number(), number(), number()) ->
    #{south := float(), west := float(), north := float(), east := float()}.
bounding_box(Lat, Lon, RadiusKm) ->
    LatDelta = RadiusKm / ?KM_PER_DEG_LAT,
    LonDelta = RadiusKm / (?KM_PER_DEG_LAT * math:cos(deg2rad(Lat))),
    #{
        south => clamp(Lat - LatDelta, -90.0, 90.0),
        north => clamp(Lat + LatDelta, -90.0, 90.0),
        west => float(Lon - LonDelta),
        east => float(Lon + LonDelta)
    }.

%%====================================================================
%% Great-circle helpers
%%====================================================================

%% Horizontal great-circle distance in kilometres (haversine).
-spec distance_km(number(), number(), number(), number()) -> float().
distance_km(Lat1, Lon1, Lat2, Lon2) ->
    P1 = deg2rad(Lat1),
    P2 = deg2rad(Lat2),
    DP = deg2rad(Lat2 - Lat1),
    DL = deg2rad(Lon2 - Lon1),
    A = math:sin(DP / 2) * math:sin(DP / 2)
        + math:cos(P1) * math:cos(P2) * math:sin(DL / 2) * math:sin(DL / 2),
    C = 2 * math:atan2(math:sqrt(A), math:sqrt(1 - A)),
    ?EARTH_KM * C.

%% Initial bearing from the observer to the target, degrees 0..360.
-spec bearing_deg(number(), number(), number(), number()) -> float().
bearing_deg(Lat1, Lon1, Lat2, Lon2) ->
    P1 = deg2rad(Lat1),
    P2 = deg2rad(Lat2),
    DL = deg2rad(Lon2 - Lon1),
    Y = math:sin(DL) * math:cos(P2),
    X = math:cos(P1) * math:sin(P2) - math:sin(P1) * math:cos(P2) * math:cos(DL),
    norm360(rad2deg(math:atan2(Y, X))).

%% Elevation angle in degrees from horizontal distance and relative height (m).
-spec elevation_deg(number(), number()) -> float().
elevation_deg(_RelHeightM, +0.0) -> 90.0;
elevation_deg(RelHeightM, HorizM) ->
    rad2deg(math:atan2(RelHeightM, HorizM)).

%%====================================================================
%% OpenSky state-vector normalization
%%====================================================================

%% Normalize one raw OpenSky state vector (a decoded JSON array) into a
%% map with atom keys and `undefined' for missing/null fields.
-spec parse_state(list()) -> map().
parse_state(Vec) when is_list(Vec) ->
    #{
        icao24 => bin(at(Vec, 0)),
        callsign => trim(bin(at(Vec, 1))),
        time_position => num_or_undef(at(Vec, 3)),
        last_contact => num_or_undef(at(Vec, 4)),
        longitude => num_or_undef(at(Vec, 5)),
        latitude => num_or_undef(at(Vec, 6)),
        baro_altitude => num_or_undef(at(Vec, 7)),
        on_ground => bool_or_undef(at(Vec, 8)),
        velocity => num_or_undef(at(Vec, 9)),
        true_track => num_or_undef(at(Vec, 10)),
        vertical_rate => num_or_undef(at(Vec, 11)),
        geo_altitude => num_or_undef(at(Vec, 13)),
        position_source => num_or_undef(at(Vec, 16)),
        category => num_or_undef(at(Vec, 17))
    }.

%%====================================================================
%% Selection: filter, rank, classify
%%====================================================================

%% Turn a list of raw OpenSky state vectors into a ranked selection.
-spec select([list()], observer(), integer(), aircraft_id_config:config()) -> selection().
select(RawStates, Observer, Now, Config) ->
    Candidates =
        [C
         || Raw <- RawStates,
            (State = parse_state(Raw)) =/= skip,
            (C = build(State, Observer, Now)) =/= skip,
            passes(C, Config)],
    classify(sort(Candidates), Config).

-spec build(map(), observer(), integer()) -> candidate() | skip.
build(State, Observer, Now) ->
    Icao = maps:get(icao24, State),
    Lat = maps:get(latitude, State),
    Lon = maps:get(longitude, State),
    Tpos = maps:get(time_position, State),
    OnGround = maps:get(on_ground, State),
    {Alt, Source} = altitude(State),
    case is_valid(Icao, Lat, Lon, Tpos, OnGround, Alt) of
        false ->
            skip;
        true ->
            #{lat := OLat, lon := OLon, elev := OElev} = Observer,
            Rel = Alt - OElev,
            Dist = distance_km(OLat, OLon, Lat, Lon),
            HorizM = Dist * 1000.0,
            Brg = bearing_deg(OLat, OLon, Lat, Lon),
            Elev = elevation_deg(Rel, HorizM),
            #{
                icao24 => Icao,
                callsign => nullify(maps:get(callsign, State)),
                registration => null,
                manufacturer => null,
                model => null,
                airline => null,
                registered_owner_operator => null,
                origin => null,
                destination => null,
                altitude_m => Alt,
                altitude_source => Source,
                distance_km => round2(Dist),
                bearing_deg => round1(Brg),
                elevation_deg => round1(Elev),
                track_deg => nullify(maps:get(true_track, State)),
                speed_mps => nullify(maps:get(velocity, State)),
                position_age_s => Now - Tpos,
                photo_url => null
            }
    end.

-spec passes(candidate(), aircraft_id_config:config()) -> boolean().
passes(C, Config) ->
    Elev = maps:get(elevation_deg, C),
    Age = maps:get(position_age_s, C),
    Dist = maps:get(distance_km, C),
    Elev > 0.0
        andalso Elev >= maps:get(min_elevation_deg, Config)
        andalso Age >= 0
        andalso Age =< maps:get(max_position_age_s, Config)
        andalso Dist =< maps:get(search_radius_km, Config).

-spec sort([candidate()]) -> [candidate()].
sort(Candidates) ->
    lists:sort(fun compare/2, Candidates).

%% Elevation desc, then freshness (age asc), then distance asc.
-spec compare(candidate(), candidate()) -> boolean().
compare(A, B) ->
    EA = maps:get(elevation_deg, A),
    EB = maps:get(elevation_deg, B),
    if
        EA =/= EB -> EA > EB;
        true ->
            AgeA = maps:get(position_age_s, A),
            AgeB = maps:get(position_age_s, B),
            if
                AgeA =/= AgeB -> AgeA < AgeB;
                true -> maps:get(distance_km, A) =< maps:get(distance_km, B)
            end
    end.

-spec classify([candidate()], aircraft_id_config:config()) -> selection().
classify([], _Config) ->
    #{confidence => none, candidate => null, alternatives => []};
classify([Primary | Rest], Config) ->
    #{
        confidence => confidence(Primary, Rest, Config),
        candidate => Primary,
        alternatives => lists:sublist(Rest, 3)
    }.

-spec confidence(candidate(), [candidate()], aircraft_id_config:config()) ->
    high | medium | ambiguous.
confidence(Primary, Rest, Config) ->
    Elev = maps:get(elevation_deg, Primary),
    Age = maps:get(position_age_s, Primary),
    Margin = maps:get(ambiguity_margin_deg, Config),
    Lead = lead(Primary, Rest),
    if
        Rest =/= [] andalso Lead =< Margin -> ambiguous;
        Elev >= 60.0 andalso Age =< 10 andalso Lead >= 8.0 -> high;
        true -> medium
    end.

-spec lead(candidate(), [candidate()]) -> float().
lead(_Primary, []) -> infinity;
lead(Primary, [Second | _]) ->
    maps:get(elevation_deg, Primary) - maps:get(elevation_deg, Second).

%%====================================================================
%% Field helpers
%%====================================================================

-spec altitude(map()) -> {number(), geometric | barometric} | {undefined, none}.
altitude(State) ->
    case maps:get(geo_altitude, State) of
        G when is_number(G) ->
            {G, geometric};
        _ ->
            case maps:get(baro_altitude, State) of
                B when is_number(B) -> {B, barometric};
                _ -> {undefined, none}
            end
    end.

-spec is_valid(term(), term(), term(), term(), term(), term()) -> boolean().
is_valid(Icao, Lat, Lon, Tpos, OnGround, Alt) ->
    is_binary(Icao)
        andalso is_number(Lat)
        andalso is_number(Lon)
        andalso is_number(Tpos)
        andalso is_number(Alt)
        andalso OnGround =/= true.

-spec at(list(), non_neg_integer()) -> term().
at(List, Index) ->
    case Index < length(List) of
        true -> lists:nth(Index + 1, List);
        false -> undefined
    end.

-spec num_or_undef(term()) -> number() | undefined.
num_or_undef(V) when is_number(V) -> V;
num_or_undef(_) -> undefined.

-spec bin(term()) -> binary() | undefined.
bin(V) when is_binary(V) -> V;
bin(_) -> undefined.

-spec bool_or_undef(term()) -> boolean() | undefined.
bool_or_undef(V) when is_boolean(V) -> V;
bool_or_undef(_) -> undefined.

-spec trim(binary() | undefined) -> binary() | undefined.
trim(undefined) -> undefined;
trim(Bin) ->
    case string:trim(Bin) of
        <<>> -> undefined;
        Trimmed -> Trimmed
    end.

-spec nullify(term()) -> term().
nullify(undefined) -> null;
nullify(V) -> V.

-spec deg2rad(number()) -> float().
deg2rad(D) -> D * math:pi() / 180.0.

-spec rad2deg(number()) -> float().
rad2deg(R) -> R * 180.0 / math:pi().

-spec norm360(number()) -> float().
norm360(D) ->
    R = D - 360.0 * float(trunc(D / 360.0)),
    case R < 0.0 of
        true -> R + 360.0;
        false -> R
    end.

-spec clamp(number(), number(), number()) -> float().
clamp(V, Min, Max) -> float(min(max(V, Min), Max)).

-spec round1(number()) -> float().
round1(V) -> erlang:round(V * 10) / 10.

-spec round2(number()) -> float().
round2(V) -> erlang:round(V * 100) / 100.
