-module(aircraft_id_geo_tests).

-include_lib("eunit/include/eunit.hrl").

%% One degree of latitude is ~111 km along a meridian.
distance_one_degree_lat_test() ->
    D = aircraft_id_geo:distance_km(0.0, 0.0, 1.0, 0.0),
    ?assert(abs(D - 111.19) < 0.5).

bearing_due_north_test() ->
    B = aircraft_id_geo:bearing_deg(0.0, 0.0, 1.0, 0.0),
    ?assert(abs(B - 0.0) < 0.01).

bearing_due_east_test() ->
    B = aircraft_id_geo:bearing_deg(0.0, 0.0, 0.0, 1.0),
    ?assert(abs(B - 90.0) < 0.01).

elevation_forty_five_degrees_test() ->
    ?assert(abs(aircraft_id_geo:elevation_deg(1000.0, 1000.0) - 45.0) < 0.001).

elevation_straight_up_test() ->
    ?assertEqual(90.0, aircraft_id_geo:elevation_deg(1000.0, 0.0)).

bounding_box_brackets_point_test() ->
    #{south := S, north := N, west := W, east := E} =
        aircraft_id_geo:bounding_box(59.3293, 18.0686, 20.0),
    ?assert(S < 59.3293 andalso 59.3293 < N),
    ?assert(W < 18.0686 andalso 18.0686 < E).

parse_state_handles_nulls_and_trims_callsign_test() ->
    Vec = vec(<<"4ac9e1">>, <<"SAS1421 ">>, 59.33, 18.07, 10600.0, 1000000),
    State = aircraft_id_geo:parse_state(Vec),
    ?assertEqual(<<"4ac9e1">>, maps:get(icao24, State)),
    ?assertEqual(<<"SAS1421">>, maps:get(callsign, State)),
    ?assertEqual(10600.0, maps:get(geo_altitude, State)).

select_ranks_highest_elevation_first_test() ->
    Now = 1000000,
    Observer = #{lat => 59.3293, lon => 18.0686, elev => 25.0},
    {ok, Config} = aircraft_id_config:validate(
        #{latitude => 59.3293, longitude => 18.0686, elevation_m => 25.0}),
    Overhead = vec(<<"aaaaaa">>, <<"OVR1">>, 59.3300, 18.0700, 11000.0, Now),
    Lower = vec(<<"bbbbbb">>, <<"LOW1">>, 59.3700, 18.1300, 8000.0, Now),
    Sel = aircraft_id_geo:select([Lower, Overhead], Observer, Now, Config),
    Candidate = maps:get(candidate, Sel),
    ?assertEqual(<<"aaaaaa">>, maps:get(icao24, Candidate)),
    ?assertEqual(1, length(maps:get(alternatives, Sel))),
    ?assertEqual(high, maps:get(confidence, Sel)).

select_none_when_all_below_threshold_test() ->
    Now = 1000000,
    Observer = #{lat => 59.3293, lon => 18.0686, elev => 25.0},
    {ok, Config} = aircraft_id_config:validate(
        #{latitude => 59.3293, longitude => 18.0686, elevation_m => 25.0}),
    %% Far away and low: elevation below the 45-degree minimum.
    Distant = vec(<<"cccccc">>, <<"FAR1">>, 59.45, 18.30, 3000.0, Now),
    Sel = aircraft_id_geo:select([Distant], Observer, Now, Config),
    ?assertEqual(none, maps:get(confidence, Sel)),
    ?assertEqual(null, maps:get(candidate, Sel)).

select_rejects_on_ground_test() ->
    Now = 1000000,
    Observer = #{lat => 59.3293, lon => 18.0686, elev => 25.0},
    {ok, Config} = aircraft_id_config:validate(
        #{latitude => 59.3293, longitude => 18.0686, elevation_m => 25.0}),
    Grounded = set_on_ground(vec(<<"dddddd">>, <<"GND1">>, 59.33, 18.07, 11000.0, Now)),
    Sel = aircraft_id_geo:select([Grounded], Observer, Now, Config),
    ?assertEqual(none, maps:get(confidence, Sel)).

%%====================================================================
%% Helpers
%%====================================================================

%% Build an 18-element OpenSky state vector with geometric altitude set.
vec(Icao, Callsign, Lat, Lon, GeoAlt, Tpos) ->
    [
        Icao,          %% 0 icao24
        Callsign,      %% 1 callsign
        <<"XX">>,      %% 2 origin_country
        Tpos,          %% 3 time_position
        Tpos,          %% 4 last_contact
        Lon,           %% 5 longitude
        Lat,           %% 6 latitude
        GeoAlt - 50.0, %% 7 baro_altitude
        false,         %% 8 on_ground
        200.0,         %% 9 velocity
        180.0,         %% 10 true_track
        0.0,           %% 11 vertical_rate
        null,          %% 12 sensors
        GeoAlt,        %% 13 geo_altitude
        null,          %% 14 squawk
        false,         %% 15 spi
        0,             %% 16 position_source
        1              %% 17 category
    ].

set_on_ground(Vec) ->
    lists:sublist(Vec, 8) ++ [true] ++ lists:nthtail(9, Vec).
