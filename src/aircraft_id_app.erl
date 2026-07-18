%%%-------------------------------------------------------------------
%%% @doc Optional application callback.
%%%
%%% Starting the `aircraft_id' application starts {@link aircraft_id_sup},
%%% which supervises {@link aircraft_id_server} only when the
%%% `start_server' environment key is `true'. The pure functional API in
%%% {@link aircraft_id} does not require the application to be started.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    aircraft_id_sup:start_link().

stop(_State) ->
    ok.
