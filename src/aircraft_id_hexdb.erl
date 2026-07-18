%%%-------------------------------------------------------------------
%%% @doc Optional HexDB fallback for fields still missing after ADSBDB.
%%%
%%% This module is a deliberate stub: `fill/3' currently returns the
%%% candidate unchanged. The URL builders are implemented so the request
%%% shape is documented and testable. Wire the network path during the
%%% provider implementation task (see plans/implementation.md).
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_hexdb).

-export([aircraft_url/1, route_url/1, fill/3]).

-spec aircraft_url(binary()) -> binary().
aircraft_url(Icao) ->
    <<"https://hexdb.io/api/v1/aircraft/", Icao/binary>>.

-spec route_url(binary()) -> binary().
route_url(Callsign) ->
    <<"https://hexdb.io/api/v1/route/icao/", Callsign/binary>>.

%% Fill missing candidate fields from HexDB. Stub: returns candidate as-is.
-spec fill(aircraft_id_opensky:ctx(), aircraft_id_geo:candidate(),
           aircraft_id_config:config()) -> aircraft_id_geo:candidate().
fill(_Ctx, Candidate, _Config) ->
    %% TODO: query HexDB only for fields still null after ADSBDB.
    Candidate.
