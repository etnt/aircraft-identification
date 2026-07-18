%%%-------------------------------------------------------------------
%%% @doc JSON codec behaviour used by `aircraft_id'.
%%%
%%% The JSON decoder/encoder is injected through the `json_codec'
%%% configuration key so the library is not bound to any single
%%% implementation. The default adapter is {@link aircraft_id_json_otp}
%%% (the OTP `json' module); AtomVM hosts supply a `tiny_json' adapter.
%%%
%%% `decode/1' MUST accept a UTF-8 binary and return the decoded term
%%% using the OTP `json' representation: objects as maps with binary
%%% keys, arrays as lists, strings as binaries, and JSON `null'/`true'/
%%% `false' as the atoms `null'/`true'/`false'.
%%% @end
%%%-------------------------------------------------------------------
-module(aircraft_id_json).

-callback decode(Binary :: binary()) -> {ok, term()} | {error, Reason :: term()}.

-callback encode(Term :: term()) -> {ok, iodata()} | {error, Reason :: term()}.
