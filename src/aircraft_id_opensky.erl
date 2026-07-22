%%%-------------------------------------------------------------------
%%% @doc OpenSky provider: request construction and response parsing.
%%%
%%% `build_url/1' and `parse_states/1' are pure and unit-testable.
%%% `fetch_states/1' performs the single bounded state query through the
%%% injected HTTP client and JSON codec and maps provider/transport
%%% failures to stable error codes.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_opensky).

-export([build_url/1, parse_states/1, fetch_states/1]).

-type ctx() :: #{
    http := module(),
    json := module(),
    config := aircraft_id_config:config()
}.

-export_type([ctx/0]).

-define(OPENSKY_MAX_BODY, 262144).
-define(OPENSKY_TIMEOUT_MS, 12000).

%% Build the bounded /states/all URL from the observer config.
-spec build_url(aircraft_id_config:config()) -> binary().
build_url(Config) ->
    #{latitude := Lat, longitude := Lon, search_radius_km := Radius} = Config,
    #{south := S, west := W, north := N, east := E} =
        aircraft_id_geo:bounding_box(Lat, Lon, Radius),
    Query = io_lib:format(
        "lamin=~s&lomin=~s&lamax=~s&lomax=~s&extended=1",
        [f(S), f(W), f(N), f(E)]
    ),
    iolist_to_binary([<<"https://opensky-network.org/api/states/all?">>, Query]).

%% Extract the list of raw state vectors from a decoded OpenSky response.
-spec parse_states(term()) -> [list()].
parse_states(#{<<"states">> := States}) when is_list(States) -> States;
parse_states(_) -> [].

%% Perform exactly one OpenSky state query.
-spec fetch_states(ctx()) -> {ok, [list()]} | {error, atom()}.
fetch_states(#{http := Http, json := Json, config := Config}) ->
    Url = build_url(Config),
    Opts = #{timeout => ?OPENSKY_TIMEOUT_MS, max_body => ?OPENSKY_MAX_BODY},
    case Http:get(Url, headers(), Opts) of
        {ok, 200, _Headers, Body} ->
            case Json:decode(Body) of
                {ok, Term} -> {ok, parse_states(Term)};
                {error, _} -> {error, opensky_bad_response}
            end;
        {ok, Status, _H, _B} when Status =:= 401; Status =:= 403 ->
            {error, opensky_unauthorized};
        {ok, 429, _H, _B} ->
            {error, opensky_rate_limited};
        {ok, 503, _H, _B} ->
            {error, opensky_unavailable};
        {ok, Status, _H, _B} when Status >= 500 ->
            {error, opensky_bad_response};
        {ok, _Status, _H, _B} ->
            {error, opensky_bad_response};
        {error, Reason} ->
            {error, classify_transport(Reason)}
    end.

%%====================================================================
%% Internal
%%====================================================================

-spec headers() -> [aircraft_id_http_client:header()].
headers() ->
    [
        {<<"accept">>, <<"application/json">>},
        {<<"accept-encoding">>, <<"identity">>},
        {<<"connection">>, <<"close">>}
    ].

-spec classify_transport(term()) -> atom().
classify_transport(timeout) -> opensky_timeout;
classify_transport({failed_connect, _}) -> network_unavailable;
classify_transport(nxdomain) -> dns_failed;
classify_transport({tls_alert, _}) -> tls_failed;
classify_transport(_) -> network_unavailable.

-spec f(float()) -> string().
f(V) -> lists:flatten(io_lib:format("~.6f", [V])).
