%%%-------------------------------------------------------------------
%%% @doc Optional supervised owner process for `aircraft_id'.
%%%
%%% Serializes manual identification requests and rejects concurrent
%%% attempts with a `busy' result. The actual work is delegated to
%%% {@link aircraft_id:identify/1} in a monitored worker so a provider
%%% crash cannot take down this server. It starts no timers and performs
%%% no provider queries from `init/1'.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_server).

-behaviour(gen_server).

-export([start_link/1, identify/0, identify/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(CALL_TIMEOUT_MS, 30000).

-record(state, {
    config :: map(),
    busy = false :: boolean(),
    worker :: undefined | {pid(), reference(), gen_server:from()}
}).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @equiv identify(30000)
-spec identify() -> aircraft_id:result().
identify() ->
    identify(?CALL_TIMEOUT_MS).

-spec identify(timeout()) -> aircraft_id:result().
identify(Timeout) ->
    gen_server:call(?MODULE, identify, Timeout).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(Config) ->
    {ok, #state{config = Config}}.

handle_call(identify, _From, #state{busy = true} = State) ->
    {reply, busy_result(), State};
handle_call(identify, From, #state{busy = false, config = Config} = State) ->
    {Pid, Ref} = spawn_monitor(fun() ->
        gen_server:reply(From, aircraft_id:identify(Config))
    end),
    {noreply, State#state{busy = true, worker = {Pid, Ref, From}}};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, Reason},
            #state{worker = {Pid, Ref, From}} = State) ->
    %% If the worker crashed before replying, surface a stable error.
    case Reason of
        normal -> ok;
        _ -> gen_server:reply(From, error_result())
    end,
    {noreply, State#state{busy = false, worker = undefined}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

-spec busy_result() -> aircraft_id:result().
busy_result() ->
    #{status => error, code => busy,
      message => <<"An identification is already in progress">>}.

-spec error_result() -> aircraft_id:result().
error_result() ->
    #{status => error, code => internal_error,
      message => <<"The identification worker terminated unexpectedly">>}.
