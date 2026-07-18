%%%-------------------------------------------------------------------
%%% @doc Optional supervisor.
%%%
%%% Supervises {@link aircraft_id_server} only when the `start_server'
%%% environment key is `true'; otherwise it starts with no children so a
%%% host that only wants the pure API pays nothing. The worker config is
%%% read from the `config' environment key.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    {ok, {SupFlags, children()}}.

-spec children() -> [supervisor:child_spec()].
children() ->
    case application:get_env(aircraft_id, start_server, false) of
        true ->
            Config = application:get_env(aircraft_id, config, #{}),
            [#{
                id => aircraft_id_server,
                start => {aircraft_id_server, start_link, [Config]},
                restart => permanent,
                shutdown => 5000,
                type => worker,
                modules => [aircraft_id_server]
            }];
        false ->
            []
    end.
