# Aircraft Identification Plan

## Overview

`aircraft_id` is a reusable Erlang/OTP library that identifies the aircraft most
likely to be flying over a caller-supplied observer location. On demand, it
queries the OpenSky REST API once, ranks nearby aircraft by apparent elevation,
and enriches the best candidate with aircraft and route metadata from ADSBDB.
HexDB can be used as an optional fallback.

The library is transport- and codec-agnostic: the HTTP client and JSON decoder
are injected by the host application through small behaviours, so the same core
logic runs on standard OTP (using `inets`/`ssl` and the OTP `json` module) and on
constrained targets such as AtomVM on the ESP32-S3 (using `ahttp_client` and
`tiny_json`). The library ships no web server, dashboard, or persistent storage;
those remain the responsibility of the consuming project.

There is no periodic polling, background tracking, or flight-history storage.
Every identification is a best-effort result derived from public ADS-B data and
must not imply knowledge of passengers or crew.

## Goals

- Expose a small Erlang API (`aircraft_id:identify/1,2`) that other projects can
  call as a dependency, with no compile-time coupling to any host application.
- Perform identification only when the host explicitly calls the API; never on a
  timer or at application start.
- Find the aircraft with the highest apparent elevation above the observer.
- Return the ICAO24 address, callsign, position age, altitude, distance, bearing,
  track, speed, and estimated elevation angle.
- Enrich the result with registration, manufacturer, model, owner/operator,
  airline, origin, destination, and photograph when available.
- Report, with stable error codes, why no reliable candidate could be identified.
- Keep the HTTP transport and JSON codec pluggable so the library runs on
  standard OTP and on AtomVM without core code changes.
- Isolate network and provider failures so they surface as normalized return
  values rather than crashing the caller.

## Non-goals

- Continuous polling, alerts, or automatic aircraft tracking.
- Historical flight lookup or storage.
- Identification of passengers, crew, or the current occupant of a private
  aircraft.
- Guaranteed identification of military, privacy-filtered, non-ADS-B, or
  out-of-coverage aircraft.
- Shipping a web server, HTTP router, dashboard, or UI as part of the core
  library (reference integrations may be provided as optional examples).
- A general-purpose HTTP client beyond the narrow contract this library requires.
- Bundling or mandating a specific JSON decoder or HTTP client implementation.

## Consumer Experience (Reference Integration)

The library returns plain Erlang maps; presentation is entirely up to the host.
The following describes a typical dashboard integration a consumer might build on
top of `aircraft_id:identify/1`. It is illustrative only and is not part of the
library.

A consumer dashboard might add an **Identify aircraft overhead** card that stays
idle until the user presses **Identify**. During a request the consumer would:

1. Disable the button and show `Checking nearby airspace...`.
2. Call its own endpoint, which invokes `aircraft_id:identify/1` once.
3. Render the best candidate, alternatives if the result is ambiguous, or a
   clear no-result/error state from the returned map.
4. Re-enable the button. It must not schedule another request.

Example rendering of a successful result:

```text
SAS SK1421 - high confidence
Airbus A320neo, SE-ROJ
Stockholm (ARN) -> Copenhagen (CPH)
10,600 m altitude, 2.1 km southwest, 78 degrees elevation
Position updated 6 seconds ago
```

Consumers must label registry owner data as **Registered owner/operator**, since
it is not proof of who operates the current flight. The library preserves this
distinction in its field names (`registered_owner_operator`).

## Architecture

```text
Host application (any project)
    |
    | aircraft_id:identify(Config)   (optionally via aircraft_id_server)
    v
aircraft_id (public API / orchestration)
    |
    +-- aircraft_id_geo (pure candidate filtering/ranking)
    |
    +-- aircraft_id_opensky / _adsbdb / _hexdb (pure request build + parse)
    |
    +-- aircraft_id_http_client (behaviour)  --> host-supplied adapter
    |         - aircraft_id_httpc  (OTP inets/ssl, default)
    |         - AtomVM ahttp_client adapter (constrained target)
    |
    +-- aircraft_id_json (behaviour)          --> host-supplied codec
              - OTP json (default)   - tiny_json (AtomVM)   - jsx/jsone/...
```

The core is a set of mostly pure functions. `aircraft_id:identify/1` performs
exactly one OpenSky state query, selects a candidate, and enriches only that
candidate. It takes no timers and starts no processes on its own.

For hosts that want request serialization, a boot-scoped enrichment cache, or a
supervised owner process, the library also provides an optional
`aircraft_id_server` `gen_server` and matching child spec (see Supervision). The
plain functional API remains usable without starting any process.

## Target Feasibility

On standard OTP, outbound HTTPS with CA-chain verification is available through
`inets`/`ssl`, and OTP 27+ provides the `json` module. No special feasibility
gate is required for that target beyond the normal library dependency checks.

### Constrained targets (AtomVM / ESP32-S3)

When the host targets AtomVM, validate outbound HTTPS on the exact firmware
build before relying on the library:

1. Ensure AtomVM's `ssl` and `ahttp_client` modules are packed into the
   application `.avm`. If the host uses `{packbeam, [prune]}`, these modules are
   stripped unless statically reachable, so the host's chosen
   `aircraft_id_http_client` adapter must reference them directly. Verify with
   `packbeam list` (or temporarily disable `prune`) that both are present
   before hardware testing.
2. Call `ssl:start/0` once before the first HTTPS connection.
3. Perform a hardware smoke request to:
   - `https://opensky-network.org/api/states/all` with a tiny bounding box.
   - `https://api.adsbdb.com/v0/online`.
4. Verify DNS, SNI, TLS handshake, chunked response handling, response-size
   behavior, connection cleanup, and timeout behavior.
5. Send `Accept-Encoding: identity` so the device does not need gzip support.
6. Confirm the host's JSON codec can parse a representative OpenSky response
   within available heap. On AtomVM this is typically `tiny_json`
   (`tiny_json:decode/1` returns `{ok, Term}`). OpenSky returns deeply nested
   arrays of mixed null/number/string values, so explicitly verify the codec
   handles arrays of arrays and JSON `null` on the target build before relying
   on it.

**TLS verification caveat.** The current AtomVM `ssl` client exposes
`verify_none` but not normal CA-chain verification, so direct HTTPS on that
target encrypts traffic without authenticating the remote server. The library
defaults to verified TLS on OTP and must document this AtomVM limitation
prominently. If authenticated TLS is required on AtomVM, run a small trusted
HTTPS-to-HTTP proxy on the local network and restrict its access to the device;
do not silently fall back to public plain HTTP.

Do not ship on a constrained target until these smoke requests work on hardware
without starving the host application.

## Configuration

Configuration is supplied by the caller as a plain map, either passed directly to
`aircraft_id:identify/2` or read from the host's `application:get_env(aircraft_id,
...)`. The library ships no configuration template and hardcodes no coordinates;
the observer location always comes from the host.

```erlang
Config = #{
    latitude => 59.3293,
    longitude => 18.0686,
    elevation_m => 25.0,
    search_radius_km => 20.0,
    max_position_age_s => 20,
    min_elevation_deg => 45.0,
    ambiguity_margin_deg => 8.0,
    enrichment => adsbdb,
    hexdb_fallback => true,

    %% Injected adapters (see Module Responsibilities).
    http_client => aircraft_id_httpc,
    json_codec  => aircraft_id_json_otp
}.
```

`aircraft_id_config` validates the map and applies defaults so callers only need
to supply the observer location:

- Latitude: `-90.0..90.0`.
- Longitude: `-180.0..180.0`.
- Search radius: default 20 km; cap at 50 km to bound response size.
- Maximum position age: default 20 seconds.
- Minimum elevation: default 45 degrees.
- `http_client` / `json_codec`: default to the OTP adapters; a host targeting
  AtomVM overrides them with the `ahttp_client` / `tiny_json` adapters.

The observer coordinates and thresholds are host-controlled. A consumer that
exposes identification over the network must decide for itself whether to accept
caller-supplied coordinates; the library neither requires nor forbids it.

The MVP uses anonymous OpenSky access, so no OpenSky credential is stored.
Authenticated OAuth2 client-credentials support can be added later if anonymous
quotas or resolution become insufficient. If a host supplies credentials, the
library must never return them from any result map or log them; storage of
secrets is the host's responsibility.

## Provider Requests

### OpenSky state query

Use one bounded request:

```text
GET https://opensky-network.org/api/states/all
    ?lamin=<south>&lomin=<west>&lamax=<north>&lomax=<east>&extended=1
```

Compute the bounding box from the configured radius:

```text
latitude_delta  = radius_km / 111.32
longitude_delta = radius_km / (111.32 * cos(latitude))
```

Clamp bounds at the poles and split the query only if a future installation
crosses the antimeridian. For the current use case, keep the box below 25 square
degrees so an OpenSky request costs one state credit.

Relevant OpenSky state-vector indexes:

| Index | Field | Use |
|------:|-------|-----|
| 0 | `icao24` | Stable lookup key for enrichment |
| 1 | `callsign` | Flight/aircraft callsign; trim spaces |
| 3 | `time_position` | Staleness check |
| 4 | `last_contact` | Diagnostic freshness |
| 5 | `longitude` | Candidate position |
| 6 | `latitude` | Candidate position |
| 7 | `baro_altitude` | Fallback altitude, metres |
| 8 | `on_ground` | Reject ground vehicles/aircraft |
| 9 | `velocity` | Display, metres/second |
| 10 | `true_track` | Display, degrees |
| 11 | `vertical_rate` | Display, metres/second |
| 13 | `geo_altitude` | Preferred geometric altitude, metres |
| 16 | `position_source` | Diagnostic source |
| 17 | `category` | Aircraft category when `extended=1` |

Reject rows with missing ICAO24, latitude, longitude, altitude, or position
time. Prefer geometric altitude and fall back to barometric altitude while
marking which source was used.

### ADSBDB enrichment

For the selected ICAO24 and a non-empty callsign, use the combined endpoint:

```text
GET https://api.adsbdb.com/v0/aircraft/<ICAO24>?callsign=<CALLSIGN>
```

Without a callsign, query only the aircraft endpoint. Expected metadata includes
registration, type, manufacturer, registered owner/operator, airline, route,
and optional photo URLs.

Treat enrichment as optional. A valid OpenSky candidate remains a successful
result if ADSBDB returns `404`, malformed data, a timeout, or incomplete route
information.

### HexDB fallback

If enabled, use HexDB only for fields still missing after ADSBDB:

```text
GET https://hexdb.io/api/v1/aircraft/<ICAO24>
GET https://hexdb.io/api/v1/route/icao/<CALLSIGN>
```

Do not call both providers unconditionally. This limits latency, external
requests, and heap use.

## Candidate Geometry and Ranking

For each valid state vector:

1. Compute horizontal great-circle distance with the haversine formula.
2. Compute initial bearing from the observer to the aircraft.
3. Determine height above observer:

   ```text
   relative_height_m = aircraft_altitude_m - observer_elevation_m
   ```

4. Reject candidates with non-positive relative height, excessive distance,
   stale positions, or `on_ground = true`.
5. Estimate elevation angle:

   ```text
   elevation_deg = atan2(relative_height_m, horizontal_distance_m) * 180 / pi
   ```

6. Sort by elevation descending, then position freshness descending, then
   horizontal distance ascending.

The highest-elevation candidate is the primary result. Return up to three
ranked candidates when useful. Confidence is derived from observable data, not
provider branding:

| Confidence | Suggested rule |
|------------|----------------|
| `high` | Elevation >= 60 degrees, position age <= 10 s, and lead >= 8 degrees |
| `medium` | Elevation >= 45 degrees and position age <= 20 s |
| `ambiguous` | Top candidates are within the configured ambiguity margin |
| `none` | No candidate meets minimum elevation and freshness requirements |

If `math:atan2/2` is unavailable on the target AtomVM build, compare candidates
using the ratio `relative_height_m / horizontal_distance_m` and use a pure
approximation only for the displayed angle. Target Feasibility must verify the
required math functions on constrained targets.

## Library Return Values

`aircraft_id:identify/1,2` returns a normalized Erlang map. The map is designed
to serialize directly to the JSON shapes below, so a consumer exposing an HTTP
endpoint can encode the result with its own JSON codec without reshaping.

Successful identification (`status => ok`, a ranked `candidate`):

```json
{
  "status": "ok",
  "confidence": "high",
  "observed_at": 1784203200,
  "candidate": {
    "icao24": "4ac9e1",
    "callsign": "SAS1421",
    "registration": "SE-ROJ",
    "manufacturer": "Airbus",
    "model": "A320neo",
    "airline": "Scandinavian Airlines",
    "registered_owner_operator": "SAS",
    "origin": {"icao": "ESSA", "iata": "ARN", "name": "Stockholm Arlanda"},
    "destination": {"icao": "EKCH", "iata": "CPH", "name": "Copenhagen"},
    "altitude_m": 10600,
    "altitude_source": "geometric",
    "distance_km": 2.1,
    "bearing_deg": 224.0,
    "elevation_deg": 78.0,
    "track_deg": 210.0,
    "speed_mps": 230.0,
    "position_age_s": 6,
    "photo_url": null
  },
  "alternatives": []
}
```

Expected no-result response (still a successful call):

```json
{
  "status": "ok",
  "confidence": "none",
  "candidate": null,
  "alternatives": [],
  "message": "No recent aircraft found above the elevation threshold"
}
```

Provider and transport failures should use a stable error code:

```json
{
  "status": "error",
  "code": "opensky_timeout",
  "message": "The aircraft service did not respond in time"
}
```

Suggested error codes include `not_configured`, `network_unavailable`,
`dns_failed`, `tls_failed`, `opensky_timeout`, `opensky_rate_limited`,
`opensky_bad_response`, and `busy`.

### Optional HTTP endpoint (consumer side)

A consumer that wants to trigger identification over HTTP can map a single route
to the library, for example:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/aircraft/identify` | Call `aircraft_id:identify/1` once and encode the result |

The request body is empty; the host supplies the observer location and thresholds
from its own configuration. This route, its web framework, and its error mapping
are the consumer's responsibility, not the library's.

## Module Responsibilities

### `aircraft_id`

The public API and orchestration facade:

- Expose `identify/1` (config map) and `identify/2` (config map + per-call
  options such as timeouts).
- Validate configuration via `aircraft_id_config`.
- Execute exactly one OpenSky query per call, select a candidate with
  `aircraft_id_geo`, and enrich only the primary candidate.
- Return the normalized result map; convert provider/transport errors into the
  stable error map rather than raising.

### `aircraft_id_http_client` (behaviour)

The narrow HTTP transport contract the library depends on. It abstracts the
actual client so the library is not bound to any one implementation:

- `get(Url, Headers, Opts) -> {ok, Status, Headers, Body} | {error, Reason}`.
- Callbacks must send `Connection: close`, `Accept: application/json`, and
  `Accept-Encoding: identity`, collect content-length or chunked bodies under a
  strict byte limit, enforce connect/read/total timeouts, always close sockets,
  and never log authorization headers or secrets.

Provided adapters:

- `aircraft_id_httpc` - default, over OTP `inets`/`ssl` with CA verification.
- An AtomVM adapter over `ahttp_client` with SNI (verify_none, per the TLS
  caveat). This adapter keeps a direct reference to `ssl`/`ahttp_client` so
  `packbeam` prune retains them.

Initial response-body caps: 256 KiB for the bounded OpenSky response and 32 KiB
for enrichment responses. Tune during hardware testing on constrained targets.

### `aircraft_id_json` (behaviour)

A minimal `decode/1` / `encode/1` abstraction so the JSON codec is pluggable:

- `aircraft_id_json_otp` - default, over the OTP `json` module.
- `aircraft_id_json_tiny` - over `tiny_json` for AtomVM.
- Hosts may supply their own adapter (jsx, jsone, thoas, ...).

### `aircraft_id_geo`

Pure functions for:

- Bounding-box construction.
- OpenSky state-vector normalization.
- Haversine distance and bearing.
- Elevation calculation.
- Filtering, sorting, ambiguity detection, and confidence assignment.

Keeping this module pure makes nearly all feature logic testable under desktop
Erlang without network access.

### `aircraft_id_opensky` / `aircraft_id_adsbdb` / `aircraft_id_hexdb`

Per-provider request construction and response normalization. These build URLs
and parse decoded JSON into the library's internal shapes; they perform no I/O
themselves and delegate transport to the injected `aircraft_id_http_client`.

### `aircraft_id_server` (optional `gen_server`)

An optional supervised owner process for hosts that want it:

- Serialize manual requests and reject concurrent attempts with `busy`.
- Optionally cache ICAO24 enrichment records for the current boot.
- Delegate the actual work to `aircraft_id:identify/1`.
- Use an explicit call timeout of approximately 30 seconds; do not rely on the
  five-second `gen_server:call/2` default. Apply shorter per-provider deadlines
  so the total remains bounded.
- Must not start timers or query providers from `init/1`.

Hosts that prefer to manage their own concurrency can skip this process and call
`aircraft_id:identify/1` directly.

### Logging

The library emits concise, ASCII-only diagnostics through a pluggable log
callback (defaulting to `logger`), and returns errors as values. Keep all log
and `io_lib:format` strings pure ASCII: constrained back ends such as AtomVM's
`iolist_to_binary/1` reject codepoints > 255, so a stray em-dash, smart quote, or
degree sign can silently drop a log line. Use `-` and `deg` in messages, never
non-ASCII symbols.

## Supervision and Application Integration

The core library is usable without any running process: a host can simply call
`aircraft_id:identify/1`. Hosts that want the optional `aircraft_id_server`
(serialization + boot cache) can integrate it in one of two ways:

- Add the `aircraft_id_server` child spec to the host's own supervision tree, so
  a worker restart clears only in-flight work and the optional metadata cache and
  never affects the host's other services.
- Or start `aircraft_id` as its own OTP application (with `aircraft_id_app` /
  `aircraft_id_sup`) that supervises the worker.

On constrained targets, ensure application packaging includes every runtime
module needed by the chosen HTTP and JSON adapters. Because `{packbeam, [prune]}`
may be enabled by the host, those modules are packed only if reachable from a
called function; the selected `aircraft_id_http_client` adapter must keep at
least one direct reference to `ssl`/`ahttp_client`. Update application
declarations only as required by the target's packaging model, verified during
Target Feasibility.

## Timeouts and Resource Limits

Suggested starting limits:

| Operation | Limit |
|-----------|-------|
| Whole identification request | 30 s |
| OpenSky connect + response | 12 s |
| ADSBDB enrichment | 8 s |
| Optional HexDB fallback | 6 s |
| OpenSky response body | 256 KiB |
| Enrichment response body | 32 KiB |
| Returned alternatives | 3 |
| Concurrent identifications | 1 |

If enrichment reaches its deadline, return the OpenSky identification without
enrichment rather than failing the whole action.

## Error Handling

- **No network:** Return `network_unavailable`; the failure is a return value and
  never crashes the caller.
- **OpenSky `401`/`403`:** Return an authentication/configuration error.
- **OpenSky `429`:** Return `opensky_rate_limited`; do not automatically retry.
- **OpenSky `5xx` or timeout:** Return a provider error; do not query enrichment.
- **Malformed/oversized JSON:** Abort parsing and return `opensky_bad_response`.
- **No qualifying aircraft:** Return `status=ok`, `confidence=none`.
- **Missing callsign:** Identify by ICAO24/registration when possible; omit route.
- **Enrichment failure:** Return the positional candidate with an
  `enrichment_status` field and partial metadata.
- **Concurrent request (when using `aircraft_id_server`):** Return `busy`; do not
  start a second provider request.
- **Worker crash:** When supervised, the host's supervisor restarts only
  `aircraft_id_server`; the plain functional API has no process to crash.

## Testing Strategy

### Desktop EUnit tests

Add fixture-driven tests for:

- Bounding boxes at ordinary latitudes, near poles, and near the antimeridian.
- OpenSky vectors with null/missing fields and trailing callsign spaces.
- Geometric-altitude preference and barometric fallback.
- Distance, bearing, and elevation calculations with known coordinates.
- Freshness, ground-state, radius, and elevation filtering.
- Candidate ranking and ambiguity thresholds.
- Confidence classification.
- OpenSky and ADSBDB JSON normalization.
- Stable provider-error mapping.
- Partial enrichment behavior.

Network tests must use a fake transport or fixture bodies; ordinary unit tests
must not depend on live external APIs.

### HTTP client tests

Use a local test server under desktop Erlang to cover:

- Content-Length and chunked bodies.
- Fragmented headers/body.
- Non-2xx status codes.
- Body-size limits.
- Connection close and timeout behavior.

### Constrained-target validation (optional)

Only required when a host ships the library on AtomVM/ESP32-S3:

1. Run the Target Feasibility provider smoke tests.
2. Record free heap before, during, and after identification.
3. Repeat identification several times and verify sockets and heap are released.
4. Exercise the host's other services during a slow provider response to confirm
   the library does not block them.
5. Verify a second concurrent identification returns `busy` (when using
   `aircraft_id_server`) without destabilizing the host.
6. Compare one result with the OpenSky map or another flight tracker at the same
   timestamp.
7. Verify no automatic request occurs after boot or while a consumer UI remains
   open.

## Documentation Updates

After implementation:

- Document the public API (`aircraft_id:identify/1,2`), the config map, and the
  result/error maps in the library README with a copy-pasteable usage example.
- Document how to select and supply `http_client` / `json_codec` adapters for
  both OTP and AtomVM, and how to plug in a custom adapter.
- Provide an optional reference integration example (e.g. a single web route)
  rather than shipping a server in the core.
- Document anonymous OpenSky credit use and current provider rate limits.
- Document the AtomVM TLS verification limitation and any local proxy setup.
- State that aircraft registry and route data may be stale or incomplete.
- Publish the library (e.g. on Hex or as a git dependency) with version and OTP
  compatibility notes.

## Implementation Order

1. Define the `aircraft_id_http_client` and `aircraft_id_json` behaviours and the
   default OTP adapters (`aircraft_id_httpc`, `aircraft_id_json_otp`).
2. Implement `aircraft_id_config` validation and defaults.
3. Implement pure geometry, state normalization, ranking, and confidence logic in
   `aircraft_id_geo`.
4. Implement OpenSky request construction and response parsing.
5. Implement ADSBDB enrichment and optional HexDB fallback.
6. Implement the `aircraft_id` orchestration facade and result/error maps.
7. Add the optional `aircraft_id_server`, supervisor, and child spec.
8. Provide the AtomVM `ahttp_client` / `tiny_json` adapters and complete Target
   Feasibility on hardware.
9. Add an optional reference HTTP-endpoint example (no polling).
10. Run desktop tests; run constrained-target resource/concurrency validation
    where applicable.
11. Write the library README and publish.

## Acceptance Criteria

- The library builds as a standalone dependency with no coupling to any host
  application, and exposes `aircraft_id:identify/1,2`.
- The HTTP client and JSON codec are pluggable; the same core runs unchanged on
  OTP (default adapters) and on AtomVM (ahttp_client/tiny_json adapters).
- No external aircraft request is made at library start or on a timer.
- One API call causes at most one OpenSky state query.
- Only the selected aircraft is enriched, except for an explicitly enabled
  fallback after a failed primary lookup.
- A qualifying nearby aircraft produces a ranked, confidence-labelled result.
- No qualifying aircraft produces a successful no-result response.
- Missing enrichment does not discard a valid OpenSky candidate.
- Requests finish or time out within 30 seconds.
- Concurrent requests through `aircraft_id_server` do not create duplicate
  provider traffic.
- Provider, DNS, TLS, JSON, and rate-limit failures surface as normalized error
  values and never crash the caller.
- Unit tests run without internet access using a fake transport adapter.
- On constrained targets, hardware testing confirms bounded heap use and no
  socket leak.

## Future Extensions

- OpenSky OAuth2 client-credentials authentication with token caching.
- A trusted local proxy that performs certificate verification and provider
  aggregation.
- User-selectable alternatives when multiple aircraft have similar elevation.
- Optional short-lived last-result caching exposed through the library API.
- Local ADS-B receiver integration for lower latency and better coverage.
- Additional shipped adapters (e.g. `gun`/`hackney` transports, `jsx`/`jsone`
  codecs) alongside the OTP and AtomVM defaults.
- A reference consumer integration (web route + dashboard card) published as an
  example project.
