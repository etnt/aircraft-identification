%%%-------------------------------------------------------------------
%%% @doc Default HTTP transport adapter over OTP `inets'/`httpc' with
%%% CA-verified TLS.
%%%
%%% This adapter authenticates the remote server using the system CA
%%% store (`public_key:cacerts_get/0'). It is the default `http_client'
%%% for standard OTP hosts.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_httpc).

-behaviour(aircraft_id_http_client).

-export([get/3]).

-define(DEFAULT_TIMEOUT_MS, 12000).
-define(DEFAULT_CONNECT_TIMEOUT_MS, 8000).
-define(DEFAULT_MAX_BODY, 262144).

-spec get(aircraft_id_http_client:url(),
          [aircraft_id_http_client:header()],
          aircraft_id_http_client:opts()) ->
    {ok, non_neg_integer(), [aircraft_id_http_client:header()], binary()}
    | {error, term()}.
get(Url, Headers, Opts) ->
    ok = ensure_started(),
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT_MS),
    ConnectTimeout = maps:get(connect_timeout, Opts, ?DEFAULT_CONNECT_TIMEOUT_MS),
    MaxBody = maps:get(max_body, Opts, ?DEFAULT_MAX_BODY),
    Request = {to_list(Url), to_httpc_headers(Headers)},
    HttpOpts = [
        {timeout, Timeout},
        {connect_timeout, ConnectTimeout},
        {ssl, ssl_opts()}
    ],
    ReqOpts = [{body_format, binary}],
    case httpc:request(get, Request, HttpOpts, ReqOpts) of
        {ok, {{_Version, Status, _Reason}, RespHeaders, Body}} ->
            case byte_size(Body) > MaxBody of
                true -> {error, body_too_large};
                false -> {ok, Status, normalize_headers(RespHeaders), Body}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Internal
%%====================================================================

-spec ensure_started() -> ok.
ensure_started() ->
    _ = application:ensure_all_started(inets),
    _ = application:ensure_all_started(ssl),
    ok.

-spec ssl_opts() -> [ssl:tls_client_option()].
ssl_opts() ->
    [
        {verify, verify_peer},
        {cacerts, public_key:cacerts_get()},
        {depth, 99},
        {customize_hostname_check,
            [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}
    ].

-spec to_list(binary() | string()) -> string().
to_list(Url) when is_binary(Url) -> binary_to_list(Url);
to_list(Url) when is_list(Url) -> Url.

-spec to_httpc_headers([aircraft_id_http_client:header()]) -> [{string(), string()}].
to_httpc_headers(Headers) ->
    [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Headers].

-spec normalize_headers([{string(), string()}]) -> [aircraft_id_http_client:header()].
normalize_headers(Headers) ->
    [{list_to_binary(string:lowercase(K)), list_to_binary(V)} || {K, V} <- Headers].
