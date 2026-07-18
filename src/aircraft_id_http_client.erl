%%%-------------------------------------------------------------------
%%% @doc HTTP transport behaviour used by `aircraft_id'.
%%%
%%% The library never talks to a concrete HTTP client directly. Instead a
%%% host application supplies a module implementing this behaviour through
%%% the `http_client' configuration key. The default adapter is
%%% {@link aircraft_id_httpc}; constrained targets (AtomVM) supply an
%%% `ahttp_client'-based adapter instead.
%%%
%%% Implementations MUST:
%%% <ul>
%%%   <li>Send `Connection: close', `Accept: application/json' and
%%%       `Accept-Encoding: identity'.</li>
%%%   <li>Enforce connect/read/total timeouts from `Opts'.</li>
%%%   <li>Cap the response body at `max_body' bytes.</li>
%%%   <li>Always close sockets.</li>
%%%   <li>Never log authorization headers or secrets.</li>
%%% </ul>
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_http_client).

-type url() :: binary() | string().
-type header() :: {binary(), binary()}.
-type opts() :: #{
    timeout => non_neg_integer(),
    connect_timeout => non_neg_integer(),
    max_body => pos_integer(),
    _ => _
}.

-export_type([url/0, header/0, opts/0]).

%% Perform a single GET request and return the full response.
-callback get(Url :: url(), Headers :: [header()], Opts :: opts()) ->
    {ok, Status :: non_neg_integer(), RespHeaders :: [header()], Body :: binary()}
    | {error, Reason :: term()}.
