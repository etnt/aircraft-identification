%%%-------------------------------------------------------------------
%%% @doc Configuration validation and defaults for `aircraft_id'.
%%%
%%% Configuration is a plain map supplied by the caller. Only the
%%% observer `latitude' and `longitude' are required; every other key has
%%% a default. {@link validate/1} returns a fully-populated, normalized
%%% config map or `{error, Reason}'.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_config).

-export([validate/1, defaults/0]).

-type config() :: #{
    latitude := float(),
    longitude := float(),
    elevation_m := float(),
    search_radius_km := float(),
    max_position_age_s := non_neg_integer(),
    min_elevation_deg := float(),
    ambiguity_margin_deg := float(),
    enrichment := adsbdb | none,
    hexdb_fallback := boolean(),
    http_client := module(),
    json_codec := module()
}.

-export_type([config/0]).

%% Defaults applied on top of the caller-supplied map.
-spec defaults() -> map().
defaults() ->
    #{
        elevation_m => 0.0,
        search_radius_km => 20.0,
        max_position_age_s => 20,
        min_elevation_deg => 45.0,
        ambiguity_margin_deg => 8.0,
        enrichment => adsbdb,
        hexdb_fallback => true,
        http_client => aircraft_id_httpc,
        json_codec => aircraft_id_json_otp
    }.

-spec validate(map()) -> {ok, config()} | {error, term()}.
validate(Input) when is_map(Input) ->
    try
        Merged = maps:merge(defaults(), Input),
        Lat = req_num(Merged, latitude, -90.0, 90.0),
        Lon = req_num(Merged, longitude, -180.0, 180.0),
        Elev = num(Merged, elevation_m),
        Radius = clamp(num(Merged, search_radius_km), 0.1, 50.0),
        MaxAge = non_neg_int(Merged, max_position_age_s),
        MinElev = num_in(Merged, min_elevation_deg, 0.0, 90.0),
        Margin = num_in(Merged, ambiguity_margin_deg, 0.0, 90.0),
        Enrichment = enrichment(maps:get(enrichment, Merged)),
        Hexdb = boolean(Merged, hexdb_fallback),
        HttpClient = module(Merged, http_client),
        JsonCodec = module(Merged, json_codec),
        {ok, Merged#{
            latitude => Lat,
            longitude => Lon,
            elevation_m => Elev,
            search_radius_km => Radius,
            max_position_age_s => MaxAge,
            min_elevation_deg => MinElev,
            ambiguity_margin_deg => Margin,
            enrichment => Enrichment,
            hexdb_fallback => Hexdb,
            http_client => HttpClient,
            json_codec => JsonCodec
        }}
    catch
        throw:{invalid, Reason} -> {error, Reason}
    end;
validate(_) ->
    {error, {invalid, not_a_map}}.

%%====================================================================
%% Internal validators
%%====================================================================

-spec req_num(map(), atom(), number(), number()) -> float().
req_num(Map, Key, Min, Max) ->
    case maps:find(Key, Map) of
        {ok, V} when is_number(V) -> range(Key, float(V), Min, Max);
        {ok, _} -> throw({invalid, {not_a_number, Key}});
        error -> throw({invalid, {missing, Key}})
    end.

-spec num(map(), atom()) -> float().
num(Map, Key) ->
    case maps:get(Key, Map) of
        V when is_number(V) -> float(V);
        _ -> throw({invalid, {not_a_number, Key}})
    end.

-spec num_in(map(), atom(), number(), number()) -> float().
num_in(Map, Key, Min, Max) ->
    range(Key, num(Map, Key), Min, Max).

-spec non_neg_int(map(), atom()) -> non_neg_integer().
non_neg_int(Map, Key) ->
    case maps:get(Key, Map) of
        V when is_integer(V), V >= 0 -> V;
        _ -> throw({invalid, {not_a_non_neg_integer, Key}})
    end.

-spec boolean(map(), atom()) -> boolean().
boolean(Map, Key) ->
    case maps:get(Key, Map) of
        V when is_boolean(V) -> V;
        _ -> throw({invalid, {not_a_boolean, Key}})
    end.

-spec module(map(), atom()) -> module().
module(Map, Key) ->
    case maps:get(Key, Map) of
        V when is_atom(V) -> V;
        _ -> throw({invalid, {not_a_module, Key}})
    end.

-spec enrichment(term()) -> adsbdb | none.
enrichment(adsbdb) -> adsbdb;
enrichment(none) -> none;
enrichment(_) -> throw({invalid, {bad_enrichment, valid_values, [adsbdb, none]}}).

-spec range(atom(), float(), number(), number()) -> float().
range(Key, V, Min, Max) ->
    case V >= Min andalso V =< Max of
        true -> V;
        false -> throw({invalid, {out_of_range, Key, Min, Max}})
    end.

-spec clamp(float(), number(), number()) -> float().
clamp(V, Min, Max) -> float(min(max(V, Min), Max)).
