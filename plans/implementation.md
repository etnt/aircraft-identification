# Implementation Plan

This is the actionable, checklist-style plan for building the `aircraft_id`
library. It complements the design in
[aircraft_identification.md](aircraft_identification.md): the design doc explains
*what* and *why*; this doc tracks *how* and *in what order*, with concrete
signatures, tasks, and per-module tests.

Status legend: `[ ]` todo, `[~]` scaffolded (stub/partial), `[x]` done.

## Resolved decisions

- **License:** MPL-2.0 (matches repository `LICENSE`).
- **Minimum OTP:** 27.0 (the default JSON adapter uses the OTP `json` module).
  Enforced via `minimum_otp_vsn` in `rebar.config`.
- **Build tool:** rebar3. Library application name and module prefix: `aircraft_id`.
- **Shipped adapters (v0.1):** OTP only — `aircraft_id_httpc` (inets/ssl, CA
  verified) and `aircraft_id_json_otp` (OTP `json`). AtomVM `ahttp_client` /
  `tiny_json` adapters and additional codecs (`jsx`/`jsone`) are follow-ups.
- **Process model:** the core is pure-call (`aircraft_id:identify/1`); the
  `gen_server` (`aircraft_id_server`) and OTP application are optional and off by
  default (`start_server => false`).
- **Deps:** none in v0.1 (only OTP applications).

## Open decisions (must close before release)

- **HexDB fallback:** shape and field-merge policy (`aircraft_id_hexdb` is a stub).
- **Transport error taxonomy:** confirm the exact `httpc` error terms to map to
  `dns_failed` / `tls_failed` / `network_unavailable` / `opensky_timeout`.
- **OTP `json` error/`null` behaviour:** confirm decode of arrays-of-arrays with
  JSON `null` and encode of the `null` atom on the pinned OTP version.

## Module status

| Module | Role | Status |
|--------|------|--------|
| `aircraft_id` | Public API + orchestration | `[~]` flow wired |
| `aircraft_id_config` | Config validation/defaults | `[x]` |
| `aircraft_id_geo` | Pure geometry, ranking, confidence | `[x]` |
| `aircraft_id_http_client` | HTTP transport behaviour | `[x]` |
| `aircraft_id_httpc` | Default OTP transport adapter | `[~]` needs hardware/network soak |
| `aircraft_id_json` | JSON codec behaviour | `[x]` |
| `aircraft_id_json_otp` | Default OTP `json` adapter | `[x]` |
| `aircraft_id_opensky` | OpenSky request/parse/fetch | `[~]` parse minimal |
| `aircraft_id_adsbdb` | ADSBDB enrichment | `[x]` schema verified against live API |
| `aircraft_id_hexdb` | Optional HexDB fallback | `[~]` stub |
| `aircraft_id_server` | Optional serialized owner | `[~]` skeleton |
| `aircraft_id_app` / `_sup` | Optional application/supervisor | `[~]` skeleton |

## Milestones

### M0 — Scaffolding (done)

- [x] `rebar.config`, `src/aircraft_id.app.src`, `.gitignore`.
- [x] Compilable module stubs with `-spec` / `-callback` and doc comments.
- [x] EUnit suites + `aircraft_id_fake_http` test transport.

### M1 — Pure core (config + geometry)

- [x] `aircraft_id_config:validate/1` with defaults, ranges, radius clamp.
- [x] `aircraft_id_geo` bounding box, haversine, bearing, elevation.
- [x] State-vector normalization, filtering, ranking, confidence.
- [ ] Extend fixtures: pole/antimeridian bounding boxes; barometric fallback;
      ambiguity-margin boundary; freshness boundary at exactly `max_position_age_s`.

### M2 — Transport + codec contracts

- [x] `aircraft_id_http_client` and `aircraft_id_json` behaviours.
- [x] `aircraft_id_json_otp` decode/encode with try/catch.
- [~] `aircraft_id_httpc`: verified TLS, body cap, timeouts.
- [ ] HTTP client tests against a local desktop server: Content-Length + chunked
      bodies, fragmented headers, non-2xx, body-size limit, connection close,
      timeout. (Fake transport covers logic; a real socket test covers the adapter.)

### M3 — Providers + orchestration

- [~] `aircraft_id_opensky:build_url/1`, `parse_states/1`, `fetch_states/1`.
- [x] `aircraft_id_adsbdb:build_url/2`, `enrich/3`, `parse/1`.
- [~] `aircraft_id:identify/1,2` end-to-end via injected transport.
- [x] Verify ADSBDB schema and `parse/1` field mapping + photo URL (confirmed
      2026-07-18 against `3c6745`/`DLH804` → `D-AIZE`, full FRA→ARN route).
- [ ] Confirm transport error classification with real `httpc` error terms.

### M4 — Optional process + integration

- [~] `aircraft_id_server` (busy handling via monitored worker), `_app`, `_sup`.
- [ ] Server tests: `busy` on concurrent call; result passthrough; worker-crash
      returns a stable error and clears busy; explicit 30s call timeout.

### M5 — HexDB fallback

- [ ] Implement `aircraft_id_hexdb:fill/3` to query only for still-missing fields
      when `hexdb_fallback => true`; add fixture tests.

### M6 — AtomVM target + docs + release

- [ ] AtomVM `ahttp_client` transport adapter (keeps direct `ssl`/`ahttp_client`
      references for packbeam prune) and `tiny_json` codec adapter.
- [ ] Complete the Target Feasibility hardware smoke tests.
- [ ] README with API usage, adapter selection, limitations, and a reference
      HTTP-endpoint example (no polling).
- [ ] `rebar3 dialyzer` + `rebar3 xref` clean; publish (Hex or git dep).

## Key signatures (contract)

```erlang
%% Public API
aircraft_id:identify(Config :: map()) -> result_map().
aircraft_id:identify(Config :: map(), Opts :: map()) -> result_map().

%% Config
aircraft_id_config:validate(map()) -> {ok, config()} | {error, term()}.

%% Behaviours
-callback get(Url, Headers, Opts) ->
    {ok, Status, RespHeaders, Body} | {error, term()}.   %% aircraft_id_http_client
-callback decode(binary()) -> {ok, term()} | {error, term()}.  %% aircraft_id_json
-callback encode(term())  -> {ok, iodata()} | {error, term()}. %% aircraft_id_json

%% Pure core
aircraft_id_geo:bounding_box(Lat, Lon, RadiusKm) -> #{south,west,north,east}.
aircraft_id_geo:select([RawVector], Observer, Now, Config) -> selection().

%% Providers
aircraft_id_opensky:fetch_states(ctx()) -> {ok, [RawVector]} | {error, atom()}.
aircraft_id_adsbdb:enrich(ctx(), Candidate, Config) -> Candidate.
```

## Commands

```sh
rebar3 compile        # build
rebar3 eunit          # run desktop tests (no network required)
rebar3 xref           # undefined/deprecated call checks
rebar3 dialyzer       # type checks (set up PLT on first run)
rebar3 shell          # interactive; aircraft_id:identify/1 with real transport
```

## Definition of done (v0.1)

- `rebar3 eunit` passes offline using `aircraft_id_fake_http`.
- `aircraft_id:identify/1` returns the documented result/error maps for: a
  qualifying aircraft, no qualifying aircraft, and each provider/transport error.
- OTP adapters verified against the live OpenSky + ADSBDB APIs at least once.
- ADSBDB `parse/1` mapping confirmed; HexDB fallback either implemented or the
  `hexdb_fallback` default set to `false` and documented as unimplemented.
- README documents API, adapter injection, and the AtomVM TLS caveat.
