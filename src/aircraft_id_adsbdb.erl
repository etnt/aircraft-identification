%%%-------------------------------------------------------------------
%%% @doc ADSBDB enrichment for the selected candidate.
%%%
%%% Enrichment is best effort: any failure (404, timeout, malformed body)
%%% returns the positional candidate unchanged with an `enrichment_status'
%%% field, never discarding a valid OpenSky result.
%%%
%%% The response field names below were verified against the live ADSBDB
%%% API on 2026-07-18 (icao24 `3c6745' / callsign `DLH804' returned
%%% registration `D-AIZE', an Airbus A320, and the full FRA->ARN route).
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_adsbdb).

-export([build_url/2, enrich/3, parse/1]).

-define(ADSBDB_MAX_BODY, 32768).
-define(ADSBDB_TIMEOUT_MS, 8000).

%% Combined aircraft (+ optional callsign route) endpoint URL.
-spec build_url(binary(), binary() | null | undefined) -> binary().
build_url(Icao, Callsign) when is_binary(Callsign) ->
    <<"https://api.adsbdb.com/v0/aircraft/", Icao/binary,
      "?callsign=", Callsign/binary>>;
build_url(Icao, _) ->
    <<"https://api.adsbdb.com/v0/aircraft/", Icao/binary>>.

%% Enrich the primary candidate. Returns the candidate either way.
-spec enrich(aircraft_id_opensky:ctx(), aircraft_id_geo:candidate(),
             aircraft_id_config:config()) -> aircraft_id_geo:candidate().
enrich(#{http := Http, json := Json}, Candidate, _Config) ->
    Icao = maps:get(icao24, Candidate),
    Callsign = maps:get(callsign, Candidate),
    Url = build_url(Icao, Callsign),
    Opts = #{timeout => ?ADSBDB_TIMEOUT_MS, max_body => ?ADSBDB_MAX_BODY},
    case Http:get(Url, headers(), Opts) of
        {ok, 200, _H, Body} ->
            case Json:decode(Body) of
                {ok, Term} ->
                    Fields = parse(Term),
                    maps:merge(Candidate, Fields#{enrichment_status => ok});
                {error, _} ->
                    Candidate#{enrichment_status => unavailable}
            end;
        _ ->
            Candidate#{enrichment_status => unavailable}
    end.

%% Map a decoded ADSBDB response into candidate override fields.
-spec parse(term()) -> map().
parse(#{<<"response">> := Response}) when is_map(Response) ->
    Aircraft = get_map(Response, <<"aircraft">>),
    Route = get_map(Response, <<"flightroute">>),
    put_all(#{}, [
        {registration, get_bin(Aircraft, <<"registration">>)},
        {manufacturer, get_bin(Aircraft, <<"manufacturer">>)},
        {model, get_bin(Aircraft, <<"type">>)},
        {registered_owner_operator, get_bin(Aircraft, <<"registered_owner">>)},
        {photo_url, get_bin(Aircraft, <<"url_photo">>)},
        {airline, get_in_bin(Route, [<<"airline">>, <<"name">>])},
        {origin, airport(get_map(Route, <<"origin">>))},
        {destination, airport(get_map(Route, <<"destination">>))}
    ]);
parse(_) ->
    #{}.

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

-spec airport(map()) -> map() | undefined.
airport(Map) when map_size(Map) =:= 0 -> undefined;
airport(Map) ->
    Fields = put_all(#{}, [
        {icao, get_bin(Map, <<"icao_code">>)},
        {iata, get_bin(Map, <<"iata_code">>)},
        {name, get_bin(Map, <<"name">>)}
    ]),
    case map_size(Fields) of
        0 -> undefined;
        _ -> Fields
    end.

%% Add only the {Key, Value} pairs whose value is a usable term.
-spec put_all(map(), [{atom(), term()}]) -> map().
put_all(Acc, []) -> Acc;
put_all(Acc, [{_Key, undefined} | Rest]) -> put_all(Acc, Rest);
put_all(Acc, [{Key, Value} | Rest]) -> put_all(Acc#{Key => Value}, Rest).

-spec get_map(map(), binary()) -> map().
get_map(Map, Key) ->
    case maps:get(Key, Map, undefined) of
        V when is_map(V) -> V;
        _ -> #{}
    end.

-spec get_bin(map(), binary()) -> binary() | undefined.
get_bin(Map, Key) ->
    case maps:get(Key, Map, undefined) of
        V when is_binary(V), V =/= <<>> -> V;
        _ -> undefined
    end.

-spec get_in_bin(map(), [binary()]) -> binary() | undefined.
get_in_bin(Map, [Key]) ->
    get_bin(Map, Key);
get_in_bin(Map, [Key | Rest]) ->
    get_in_bin(get_map(Map, Key), Rest).
