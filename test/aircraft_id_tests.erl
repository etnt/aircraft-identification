-module(aircraft_id_tests).

-include_lib("eunit/include/eunit.hrl").

invalid_config_returns_not_configured_test() ->
    Result = aircraft_id:identify(#{longitude => 18.0}),
    ?assertEqual(error, maps:get(status, Result)),
    ?assertEqual(not_configured, maps:get(code, Result)).

identify_end_to_end_with_fake_transport_test() ->
    Now = erlang:system_time(second),
    OpenSkyBody = json:encode(#{
        <<"time">> => Now,
        <<"states">> => [overhead_vector(Now)]
    }),
    AdsbdbBody = json:encode(#{
        <<"response">> => #{
            <<"aircraft">> => #{
                <<"registration">> => <<"SE-ROJ">>,
                <<"type">> => <<"A320neo">>,
                <<"manufacturer">> => <<"Airbus">>,
                <<"registered_owner">> => <<"SAS">>
            }
        }
    }),
    aircraft_id_fake_http:set([
        {"opensky-network.org", {200, iolist_to_binary(OpenSkyBody)}},
        {"api.adsbdb.com", {200, iolist_to_binary(AdsbdbBody)}}
    ]),
    try
        Result = aircraft_id:identify(#{
            latitude => 59.3293,
            longitude => 18.0686,
            elevation_m => 25.0,
            hexdb_fallback => false,
            http_client => aircraft_id_fake_http,
            json_codec => aircraft_id_json_otp
        }),
        ?assertEqual(ok, maps:get(status, Result)),
        Candidate = maps:get(candidate, Result),
        ?assertEqual(<<"4ac9e1">>, maps:get(icao24, Candidate)),
        ?assertEqual(<<"SAS1421">>, maps:get(callsign, Candidate)),
        ?assertEqual(<<"SE-ROJ">>, maps:get(registration, Candidate)),
        ?assertEqual(<<"SAS">>, maps:get(registered_owner_operator, Candidate)),
        ?assertEqual(ok, maps:get(enrichment_status, Candidate))
    after
        aircraft_id_fake_http:clear()
    end.

identify_no_result_when_states_empty_test() ->
    Body = json:encode(#{<<"time">> => 0, <<"states">> => []}),
    aircraft_id_fake_http:set([{"opensky-network.org", {200, iolist_to_binary(Body)}}]),
    try
        Result = aircraft_id:identify(#{
            latitude => 59.3293, longitude => 18.0686,
            http_client => aircraft_id_fake_http, json_codec => aircraft_id_json_otp
        }),
        ?assertEqual(ok, maps:get(status, Result)),
        ?assertEqual(none, maps:get(confidence, Result)),
        ?assertEqual(null, maps:get(candidate, Result))
    after
        aircraft_id_fake_http:clear()
    end.

overhead_vector(Now) ->
    [
        <<"4ac9e1">>, <<"SAS1421 ">>, <<"Sweden">>, Now, Now,
        18.0700, 59.3300, 10550.0, false, 230.0, 210.0, 0.0, null,
        10600.0, null, false, 0, 1
    ].
