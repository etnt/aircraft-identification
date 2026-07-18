# aircraft_id

An embeddable Erlang library that answers a single question:

> **"Which aircraft is most likely the one flying over me right now?"**

Given a fixed observer location, `aircraft_id` performs **one** query to the
[OpenSky Network](https://opensky-network.org/), ranks nearby aircraft by how
high they sit in your sky, optionally enriches the best match with registration
and route data, and returns a normalized result map.

It is a **library**, not a service: it starts no timers and no processes, holds
no state, and does no polling. You call a function, it returns a map. An optional
`gen_server` wrapper is provided for hosts that want request serialization, but
it is off by default.

- **OTP 27+** (the default JSON adapter uses the OTP `json` module)
- **Pluggable HTTP transport and JSON codec** via behaviours, so the same core
  runs on standard OTP and on constrained targets such as
  [AtomVM](https://www.atomvm.net/) (ESP32) by swapping adapters
- **No external dependencies** in the default build
- Licensed under **MPL-2.0**

---

## Quick start

```sh
rebar3 compile
rebar3 shell
```

```erlang
%% Only latitude and longitude are required; everything else has a default.
Config = #{latitude => 59.3279, longitude => 18.0551, search_radius_km => 30.0,
           enrichment => adsbdb,min_elevation_deg => 18.0}.
aircraft_id:identify(Config).
```

Example result when something is overhead:

```erlang
#{status => ok,
  candidate =>
      #{origin =>
            #{name => <<"Helsinki Vantaa Airport">>,
              icao => <<"EFHK">>,
              iata => <<"HEL">>},
        distance_km => 28.61,
        bearing_deg => 99.9,
        elevation_deg => 23.5,
        icao24 => <<"461f57">>,
        callsign => <<"FIN7WG">>,
        enrichment_status => ok,
        registration => <<"OH-LWP">>,
        manufacturer => <<"Airbus">>,
        model => <<"A350 941">>,
        registered_owner_operator => <<"Finnair">>,
        photo_url =>
            <<"https://airport-data.com/images/aircraft/001/667/001667920.jpg">>,
        airline => <<"Finnair">>,
        destination =>
            #{name => <<"London Heathrow Airport">>,
              icao => <<"EGLL">>,
              iata => <<"LHR">>},
        altitude_m => 12443.46,
        altitude_source => geometric,
        track_deg => 246.83,
        speed_mps => 240.61,
        position_age_s => 9},
  confidence => medium,
  alternatives => [],
  observed_at => 1784383422}
```

Example result when the sky is clear (above your elevation threshold):

```erlang
#{status => ok,
  confidence => none,
  observed_at => 1784381467,
  candidate => null,
  alternatives => [],
  message => <<"No recent aircraft found above the elevation threshold">>}
```

> TIPS: to get your Latitude and Longitude: right-click on your Google Map.

---

## The core idea: elevation angle

The library ranks aircraft by **elevation angle** — how far above your local
horizon a plane appears, measured from where you stand:

- **0°** = on the horizon (eye level, straight out)
- **90°** = directly overhead (the zenith)

For each aircraft it takes the horizontal ground distance and the aircraft's
height above you and computes:

```
elevation = atan2(height_above_observer, horizontal_distance)
```

So elevation depends on **both** altitude and horizontal distance. A plane at
10 km altitude directly overhead is at ~90°; the same plane 10 km away
horizontally is at ~45°; 30 km away it drops to ~18°.

This is exactly the notion of "overhead": `min_elevation_deg` keeps only aircraft
that are sufficiently high in your sky and rejects distant traffic that is
technically nearby but low on the horizon.

Two knobs work together:

- **`search_radius_km`** bounds the *horizontal* map footprint queried from
  OpenSky.
- **`min_elevation_deg`** then filters that set by the *vertical* angle.

> **Tip:** the default `min_elevation_deg` is `45.0`, a deliberately tight cone.
> If you get `confidence => none` a lot, lower it (e.g. `10.0`) to widen the
> sky you consider "overhead". Because elevation uses height *relative to you*,
> set `elevation_m` if you are at significant altitude.

---

## Configuration

Configuration is a plain map you pass to `identify/1`. Only `latitude` and
`longitude` are required; all other keys fall back to defaults.

| Key                    | Type | Default | Meaning |
|------------------------|------|---------|---------|
| `latitude`             | float `-90.0..90.0` | *(required)* | Observer latitude |
| `longitude`            | float `-180.0..180.0` | *(required)* | Observer longitude |
| `elevation_m`          | float | `0.0` | Observer height above sea level (m) |
| `search_radius_km`     | float `0.1..50.0` | `20.0` | Horizontal query radius (clamped) |
| `max_position_age_s`.  | non-neg integer | `20` | Reject positions older than this |
| `min_elevation_deg`    | float `0.0..90.0` | `45.0` | Minimum angle above the horizon |
| `ambiguity_margin_deg` | float `0.0..90.0` | `8.0` | Elevation gap below which the top two are "ambiguous" |
| `enrichment`           | `adsbdb \| none` | `adsbdb` | Enrich the primary candidate |
| `hexdb_fallback`       | boolean | `true` | Fill remaining gaps via HexDB (currently a stub) |
| `http_client`          | module | `aircraft_id_httpc` | HTTP transport adapter |
| `json_codec`           | module | `aircraft_id_json_otp` | JSON codec adapter |

`aircraft_id_config:validate/1` returns `{ok, Config}` with all keys populated,
or `{error, Reason}` (e.g. `{missing, latitude}`, `{out_of_range, latitude, -90.0, 90.0}`).

---

## Result shape

`identify/1,2` always returns a map with a `status` key.

### `status => ok`

| Field          | Meaning |
|----------------|---------|
| `confidence`.  | `high` \| `medium` \| `ambiguous` \| `none` |
| `observed_at`  | Unix timestamp (seconds) of the query |
| `candidate`.   | The best match map, or `null` if nothing qualified |
| `alternatives` | Up to 3 runner-up candidates (same shape, no enrichment) |
| `message`      | Present only when `candidate => null` |

**Confidence** summarizes how sure the pick is:

- `high` — clearly overhead, fresh position, and a comfortable lead over the next
  aircraft
- `medium` — qualifies but with weaker margins
- `ambiguous` — two aircraft are within `ambiguity_margin_deg` of each other; the
  lead is not decisive
- `none` — nothing passed the filters (`candidate => null`)

**Candidate fields** include `icao24`, `callsign`, `registration`,
`manufacturer`, `model`, `airline`, `registered_owner_operator`, `origin`,
`destination`, `altitude_m`, `altitude_source` (`geometric | barometric`),
`distance_km`, `bearing_deg`, `elevation_deg`, `track_deg`, `speed_mps`,
`position_age_s`, and `photo_url`. Fields OpenSky does not provide start as
`null` and are populated by enrichment when available.

### `status => error`

```erlang
#{status => error, code => Code, message => Message}.
```

| `code` | Meaning |
|--------|---------|
| `not_configured` | Config failed validation (`message` has the detail) |
| `network_unavailable` | Could not reach the service |
| `dns_failed` | Host could not be resolved |
| `tls_failed` | TLS handshake failed |
| `opensky_timeout` | Service did not respond in time |
| `opensky_rate_limited` | HTTP 429 from OpenSky |
| `opensky_unauthorized` | HTTP 401/403 from OpenSky |
| `opensky_bad_response` | Malformed or 5xx response |

---

## Trying a real call

```erlang
%% Isolate OpenSky (no enrichment), widen the cone to see traffic.
Config = #{latitude => 59.3279, longitude => 18.0551,
           search_radius_km => 30.0, enrichment => none,
           min_elevation_deg => 5.0}.
aircraft_id:identify(Config).
```

To confirm OpenSky is returning traffic regardless of geometry:

```erlang
Ctx = #{http => aircraft_id_httpc, json => aircraft_id_json_otp,
        config => (aircraft_id_config:defaults())#{
            latitude => 59.3279, longitude => 18.0551,
            search_radius_km => 30.0}}.
{ok, States} = aircraft_id_opensky:fetch_states(Ctx),
length(States).
```

> **OpenSky access:** the default `aircraft_id_httpc` adapter sends **no
> authentication**. OpenSky increasingly requires an OAuth2 token for
> `/api/states/all`; anonymous requests may be rate limited (`opensky_rate_limited`)
> or rejected (`opensky_unauthorized`). Authenticated transport is not yet
> implemented — see [plans/implementation.md](plans/implementation.md).

---

## Pluggable transport and codec

The core never calls `httpc` or `json` directly. Instead it calls two
behaviours, so you can run the same logic on different runtimes:

- **`aircraft_id_http_client`** — one callback, `get/3`, returning
  `{ok, Status, Headers, Body} | {error, Reason}`. Default:
  `aircraft_id_httpc` (inets/ssl with CA-verified TLS).
- **`aircraft_id_json`** — `decode/1` and `encode/1`. Default:
  `aircraft_id_json_otp` (OTP `json` module).

Select alternatives per call via config:

```erlang
aircraft_id:identify(Config#{http_client => my_atomvm_http,
                             json_codec  => my_tiny_json}).
```

This is how the library targets constrained devices (e.g. AtomVM on ESP32):
provide adapters over the device's HTTP stack and JSON codec; the geometry,
ranking, and orchestration are unchanged.

> **AtomVM/TLS caveat:** on some constrained targets certificate verification is
> limited (`verify_none`); treat results accordingly. See the design plan for
> the target-feasibility notes.

---

## Optional server

For hosts that want one in-flight request at a time, `aircraft_id_server` is a
`gen_server` that serializes calls (concurrent callers get a `busy` result). It
is **not** started by default. Enable it via application env:

```erlang
%% sys.config
[{aircraft_id, [{start_server, true}, {config, #{latitude => 59.3279, 
                                                 longitude => 18.0551}}]}].
```

```erlang
aircraft_id_server:identify().        %% uses the configured location
aircraft_id_server:identify(Config).  %% override per call
```

Otherwise the pure `aircraft_id:identify/1` API is all you need.

---

## Data sources

- **OpenSky Network** — live state vectors (`/api/states/all`), one bounded
  query per call.
- **ADSBDB** — enrichment (registration, owner, route) for the primary candidate
  only. *The response mapping is currently best-effort and must be verified
  against the live API.*
- **HexDB** — optional fallback for still-missing fields (currently a stub).

---

## Development

```sh
rebar3 compile      # build
rebar3 eunit        # run the offline test suite (uses a fake transport)
rebar3 xref         # undefined/deprecated call checks
rebar3 dialyzer     # type checks
rebar3 shell        # interactive
```

Tests run fully offline using `aircraft_id_fake_http`, an in-memory transport
that returns canned responses — no network required.

## Documentation

- [plans/aircraft_identification.md](plans/aircraft_identification.md) — design:
  goals, architecture, geometry, ranking, confidence, error taxonomy.
- [plans/implementation.md](plans/implementation.md) — build plan, module status,
  milestones, and open decisions.

## Companion mobile app

A Flutter app, **Sky Overhead**, provides a phone-friendly front end over the
same OpenSky/ADSBDB data and identification logic. See
[mobile/README.md](mobile/README.md) for setup, running on a device, and
configuration.

## License

[MPL-2.0](LICENSE).
