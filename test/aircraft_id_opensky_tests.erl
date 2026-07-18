-module(aircraft_id_opensky_tests).

-include_lib("eunit/include/eunit.hrl").

build_url_contains_bounding_box_test() ->
    {ok, Config} = aircraft_id_config:validate(
        #{latitude => 59.3293, longitude => 18.0686}),
    Url = binary_to_list(aircraft_id_opensky:build_url(Config)),
    ?assert(string:find(Url, "opensky-network.org/api/states/all") =/= nomatch),
    ?assert(string:find(Url, "lamin=") =/= nomatch),
    ?assert(string:find(Url, "extended=1") =/= nomatch).

parse_states_extracts_list_test() ->
    Term = #{<<"time">> => 1, <<"states">> => [[<<"abc">>], [<<"def">>]]},
    ?assertEqual([[<<"abc">>], [<<"def">>]], aircraft_id_opensky:parse_states(Term)).

parse_states_handles_null_states_test() ->
    ?assertEqual([], aircraft_id_opensky:parse_states(#{<<"states">> => null})).

fetch_states_maps_rate_limit_test() ->
    aircraft_id_fake_http:set([{"opensky-network.org", {429, <<>>}}]),
    try
        Ctx = ctx(),
        ?assertEqual({error, opensky_rate_limited},
                     aircraft_id_opensky:fetch_states(Ctx))
    after
        aircraft_id_fake_http:clear()
    end.

fetch_states_maps_timeout_test() ->
    aircraft_id_fake_http:set([{"opensky-network.org", {error, timeout}}]),
    try
        ?assertEqual({error, opensky_timeout},
                     aircraft_id_opensky:fetch_states(ctx()))
    after
        aircraft_id_fake_http:clear()
    end.

ctx() ->
    {ok, Config} = aircraft_id_config:validate(
        #{latitude => 59.3293, longitude => 18.0686,
          http_client => aircraft_id_fake_http, json_codec => aircraft_id_json_otp}),
    #{http => aircraft_id_fake_http, json => aircraft_id_json_otp, config => Config}.
