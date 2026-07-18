%%%-------------------------------------------------------------------
%%% @doc Default JSON codec adapter over the OTP `json' module (OTP 27+).
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_json_otp).

-behaviour(aircraft_id_json).

-export([decode/1, encode/1]).

-spec decode(binary()) -> {ok, term()} | {error, term()}.
decode(Binary) when is_binary(Binary) ->
    try
        {ok, json:decode(Binary)}
    catch
        _:Reason -> {error, {invalid_json, Reason}}
    end.

-spec encode(term()) -> {ok, iodata()} | {error, term()}.
encode(Term) ->
    try
        {ok, json:encode(Term)}
    catch
        _:Reason -> {error, {invalid_term, Reason}}
    end.
