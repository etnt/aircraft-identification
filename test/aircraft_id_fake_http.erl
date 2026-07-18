%%%-------------------------------------------------------------------
%%% @doc Test-only fake HTTP transport.
%%%
%%% Implements the {@link aircraft_id_http_client} behaviour by matching a
%%% request URL against a list of registered `{UrlSubstring, {Status,
%%% Body}}' stubs, so provider and facade logic can be exercised without
%%% any network access.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_fake_http).

-behaviour(aircraft_id_http_client).

-export([get/3, set/1, clear/0]).

-define(KEY, {?MODULE, responses}).

-spec set([{string(), {non_neg_integer(), binary()} | {error, term()}}]) -> ok.
set(Responses) ->
    persistent_term:put(?KEY, Responses).

-spec clear() -> ok.
clear() ->
    _ = (catch persistent_term:erase(?KEY)),
    ok.

get(Url, _Headers, _Opts) ->
    UrlStr = to_list(Url),
    case match(UrlStr, persistent_term:get(?KEY, [])) of
        {ok, {error, Reason}} -> {error, Reason};
        {ok, {Status, Body}} -> {ok, Status, [], Body};
        error -> {error, {no_stub, UrlStr}}
    end.

match(_Url, []) ->
    error;
match(Url, [{Sub, Response} | Rest]) ->
    case string:find(Url, Sub) of
        nomatch -> match(Url, Rest);
        _ -> {ok, Response}
    end.

to_list(Url) when is_binary(Url) -> binary_to_list(Url);
to_list(Url) when is_list(Url) -> Url.
