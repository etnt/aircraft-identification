-module(aircraft_id_config_tests).

-include_lib("eunit/include/eunit.hrl").

valid_minimal_config_applies_defaults_test() ->
    {ok, Config} = aircraft_id_config:validate(#{latitude => 59.3293, longitude => 18.0686}),
    ?assertEqual(59.3293, maps:get(latitude, Config)),
    ?assertEqual(20.0, maps:get(search_radius_km, Config)),
    ?assertEqual(45.0, maps:get(min_elevation_deg, Config)),
    ?assertEqual(adsbdb, maps:get(enrichment, Config)),
    ?assertEqual(aircraft_id_httpc, maps:get(http_client, Config)),
    ?assertEqual(aircraft_id_json_otp, maps:get(json_codec, Config)).

missing_latitude_is_error_test() ->
    ?assertEqual({error, {missing, latitude}},
                 aircraft_id_config:validate(#{longitude => 18.0686})).

latitude_out_of_range_is_error_test() ->
    ?assertMatch({error, {out_of_range, latitude, _, _}},
                 aircraft_id_config:validate(#{latitude => 120.0, longitude => 18.0})).

radius_is_clamped_to_50_test() ->
    {ok, Config} = aircraft_id_config:validate(
        #{latitude => 0.0, longitude => 0.0, search_radius_km => 500.0}),
    ?assertEqual(50.0, maps:get(search_radius_km, Config)).

bad_enrichment_is_error_test() ->
    ?assertMatch({error, {bad_enrichment, _, _}},
                 aircraft_id_config:validate(
                     #{latitude => 0.0, longitude => 0.0, enrichment => magic})).

non_map_is_error_test() ->
    ?assertEqual({error, {invalid, not_a_map}}, aircraft_id_config:validate(not_a_map)).
