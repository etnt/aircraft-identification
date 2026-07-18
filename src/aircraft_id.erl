%%%-------------------------------------------------------------------
%%% @doc Public API for the aircraft identification library.
%%%
%%% Call {@link identify/1} with a config map (see
%%% {@link aircraft_id_config}). The call performs exactly one OpenSky
%%% state query, ranks nearby aircraft, and enriches only the primary
%%% candidate. It starts no timers and no processes; hosts that want
%%% request serialization can use {@link aircraft_id_server} instead.
%%%
%%% The return value is a normalized map designed to serialize directly
%%% to the JSON shapes documented in plans/aircraft_identification.md.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id).

-export([identify/1, identify/2]).

-type result() :: map().

-export_type([result/0]).

%% @equiv identify(Config, #{})
-spec identify(map()) -> result().
identify(Config) ->
    identify(Config, #{}).

-spec identify(map(), map()) -> result().
identify(Config0, _Opts) ->
    case aircraft_id_config:validate(Config0) of
        {ok, Config} -> run(Config);
        {error, Reason} -> error_result(not_configured, detail(Reason))
    end.

%%====================================================================
%% Internal
%%====================================================================

-spec run(aircraft_id_config:config()) -> result().
run(Config) ->
    Ctx = #{
        http => maps:get(http_client, Config),
        json => maps:get(json_codec, Config),
        config => Config
    },
    case aircraft_id_opensky:fetch_states(Ctx) of
        {ok, RawStates} ->
            Now = erlang:system_time(second),
            Observer = observer(Config),
            Selection = aircraft_id_geo:select(RawStates, Observer, Now, Config),
            finalize(Ctx, Selection, Now, Config);
        {error, Code} ->
            error_result(Code, message_for(Code))
    end.

-spec finalize(aircraft_id_opensky:ctx(), aircraft_id_geo:selection(),
               integer(), aircraft_id_config:config()) -> result().
finalize(_Ctx, #{candidate := null}, Now, _Config) ->
    #{
        status => ok,
        confidence => none,
        observed_at => Now,
        candidate => null,
        alternatives => [],
        message => <<"No recent aircraft found above the elevation threshold">>
    };
finalize(Ctx, #{confidence := Confidence, candidate := Candidate, alternatives := Alts},
         Now, Config) ->
    Enriched = enrich(Ctx, Candidate, Config),
    #{
        status => ok,
        confidence => Confidence,
        observed_at => Now,
        candidate => Enriched,
        alternatives => Alts
    }.

-spec enrich(aircraft_id_opensky:ctx(), aircraft_id_geo:candidate(),
             aircraft_id_config:config()) -> aircraft_id_geo:candidate().
enrich(Ctx, Candidate, Config) ->
    Base =
        case maps:get(enrichment, Config) of
            none -> Candidate;
            adsbdb -> aircraft_id_adsbdb:enrich(Ctx, Candidate, Config)
        end,
    case maps:get(hexdb_fallback, Config) of
        true -> aircraft_id_hexdb:fill(Ctx, Base, Config);
        false -> Base
    end.

-spec observer(aircraft_id_config:config()) -> aircraft_id_geo:observer().
observer(Config) ->
    #{
        lat => maps:get(latitude, Config),
        lon => maps:get(longitude, Config),
        elev => maps:get(elevation_m, Config)
    }.

-spec error_result(atom(), binary()) -> result().
error_result(Code, Message) ->
    #{status => error, code => Code, message => Message}.

-spec message_for(atom()) -> binary().
message_for(network_unavailable) -> <<"The network is unavailable">>;
message_for(dns_failed) -> <<"Could not resolve the aircraft service host">>;
message_for(tls_failed) -> <<"TLS handshake with the aircraft service failed">>;
message_for(opensky_timeout) -> <<"The aircraft service did not respond in time">>;
message_for(opensky_rate_limited) -> <<"The aircraft service is rate limiting requests">>;
message_for(opensky_unauthorized) -> <<"The aircraft service rejected the request">>;
message_for(opensky_bad_response) -> <<"The aircraft service returned an invalid response">>;
message_for(_) -> <<"The aircraft service request failed">>.

-spec detail(term()) -> binary().
detail(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
