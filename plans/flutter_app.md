# Flutter Companion App Plan

## Overview

`skyoverhead` (working name) is a small cross-platform **Flutter** app that answers
the same question as the `aircraft_id` Erlang library — *"which aircraft is
overhead right now?"* — but as a self-contained mobile app. The user taps a
button; the app reads the device location, queries the public **OpenSky** and
**ADSBDB** APIs directly, ranks nearby aircraft by apparent elevation, and shows
the best match on a card.

The app is **independent of the Erlang library**. It does not call the Erlang
code and needs no backend of our own for the MVP. Instead it re-implements the
same small, well-understood pipeline in Dart. The domain logic is simple
geometry and ranking, so this duplication is cheap and keeps the app deployable
to phone stores without hosting anything.

This plan covers only the app. The Erlang library remains the reference
implementation and the source of truth for the algorithm (see
[aircraft_identification.md](aircraft_identification.md)).

## Goals

- One-tap identification: a single primary button triggers exactly one OpenSky
  query, ranking, and a single enrichment lookup for the best candidate.
- Use the **device GPS** as the observer location (with manual override).
- Mirror the Erlang pipeline: bounding box → freshness/elevation filtering →
  elevation-first ranking → confidence → ADSBDB enrichment.
- Present a clear result card (callsign, registration, type, operator, route,
  distance, bearing, elevation, altitude, a photo when available) and the same
  stable error/`no-result` states the library produces.
- No background tracking, no polling, no flight-history storage — every result is
  an on-demand, best-effort snapshot from public ADS-B data.

## Non-goals

- No live map/radar view or continuous refresh in the MVP (possible later).
- No push notifications, accounts, or analytics.
- No re-use of Erlang code at runtime (no FFI, no embedded BEAM).
- No storage of personal data; the app holds only the current, transient result.

## Architecture decision

Two viable shapes were considered:

1. **Direct-to-API (chosen for MVP).** The app calls OpenSky and ADSBDB directly
   over HTTPS and does the geometry/ranking on-device. Zero infrastructure,
   fully offline-deployable to stores.
2. **Backend proxy.** A thin HTTP service (potentially wrapping the Erlang
   `aircraft_id` library via `aircraft_id_server`) that the app calls once per
   tap. Centralizes credentials, rate limiting, and the algorithm.

We start with **(1)** for speed and independence, but design the networking
layer behind an interface (`AircraftService`) so switching to **(2)** later is a
one-class change. See "Credentials & security" for why (2) becomes attractive if
authenticated OpenSky access is required.

## Credentials & security (important)

- **OpenSky now favors OAuth2** for `/api/states/all`; anonymous requests are
  heavily rate-limited or rejected. If we need authenticated access, note that
  **secrets embedded in a mobile app are not secret** — they can be extracted
  from the binary. Options, least-risk first:
  - Use anonymous/rate-limited access for the MVP and surface `rate_limited`
    clearly to the user.
  - Move OpenSky auth behind a **backend proxy** (architecture option 2) that
    holds the client credentials server-side. This is the recommended path if
    authenticated OpenSky access is a hard requirement.
  - Only as a last resort, ship per-user credentials entered in-app and stored
    with `flutter_secure_storage` (Keychain/Keystore).
- **ADSBDB** currently needs no key for the endpoints we use.
- All calls are HTTPS with default certificate validation. Do **not** disable TLS
  verification. Set explicit connect/read timeouts and cap response body sizes,
  mirroring the Erlang adapters.
- Request only "when in use" location permission; never track in the background.

## Project layout (separate directory)

The app lives in its own top-level directory, isolated from the Erlang project:

```
mobile/                          # Flutter app root (separate from src/, test/)
  pubspec.yaml
  analysis_options.yaml
  lib/
    main.dart                    # app entry, theme, home screen wiring
    src/
      config/
        identify_config.dart     # observer + thresholds (mirrors aircraft_id_config)
      domain/
        geo.dart                 # bounding box, haversine, bearing, elevation
        ranking.dart             # filter + elevation-first sort + confidence
        models.dart              # Candidate, Selection, IdentifyResult, enums
      data/
        aircraft_service.dart    # AircraftService interface + IdentifyOutcome
        opensky_client.dart      # one /states/all query + state-vector parsing
        adsbdb_client.dart       # enrichment lookup + response mapping
        http.dart                # shared client, timeouts, body cap, error mapping
      location/
        location_provider.dart   # GPS via geolocator, permission flow, manual entry
      ui/
        home_screen.dart         # button + result/loading/error states
        result_card.dart         # candidate presentation
        widgets/                 # small reusable widgets
    state/
      identify_controller.dart   # idle/loading/result/error state machine
  test/
    geo_test.dart                # unit tests (parity with aircraft_id_geo_tests)
    ranking_test.dart            # ranking + confidence
    adsbdb_client_test.dart      # response mapping against recorded JSON
    identify_controller_test.dart# controller with a fake AircraftService
  integration_test/
    identify_flow_test.dart      # button tap → result card (mocked HTTP)
  android/ ios/ ...              # platform folders (flutter create output)
```

## Dart module mapping (to the Erlang library)

| Erlang module | Dart equivalent | Notes |
|---------------|-----------------|-------|
| `aircraft_id_config` | `config/identify_config.dart` | Same keys/defaults: radius 20 km, `minElevationDeg` 45, `maxPositionAgeS` 20, `ambiguityMarginDeg` 8 |
| `aircraft_id_geo` | `domain/geo.dart` + `domain/ranking.dart` | Haversine (R=6371.0088 km), bearing, `atan2` elevation, filter/sort/confidence |
| `aircraft_id_opensky` | `data/opensky_client.dart` | Build bounded URL, parse `states` array, map status/transport → errors |
| `aircraft_id_adsbdb` | `data/adsbdb_client.dart` | `/v0/aircraft/<icao>?callsign=<cs>`; mapping verified 2026-07-18 |
| `aircraft_id` (facade) | `data/aircraft_service.dart` | `identify(config)` orchestration returning an `IdentifyResult` |
| `aircraft_id_http_client` | `data/http.dart` | Injectable client so tests use a fake/mock |

The ranking rules to port verbatim: keep aircraft with `elevation > 0` and
`>= minElevationDeg`, position age `0..maxPositionAgeS`, distance `<= radius`,
reject `onGround`; sort by elevation desc, then age asc, then distance asc;
confidence = `ambiguous` when the runner-up is within `ambiguityMarginDeg`,
`high` when `elevation >= 60 && age <= 10 && lead >= 8.0`, else `medium`, and
`none` when no candidate qualifies. Cap alternatives at 3.

## Result model

`IdentifyResult` mirrors the library's return map:

- `status`: `ok` | `error`
- `confidence`: `high` | `medium` | `ambiguous` | `none`
- `observedAt`: timestamp
- `candidate`: nullable `Candidate` (icao24, callsign, registration, manufacturer,
  model, airline, registeredOwnerOperator, origin/destination airports,
  altitudeM, altitudeSource, distanceKm, bearingDeg, elevationDeg, trackDeg,
  speedMps, positionAgeS, photoUrl)
- `alternatives`: up to 3 `Candidate`s (no enrichment)
- `message`: present for the no-result and error cases

Error codes reuse the library's taxonomy (`network_unavailable`, `dns_failed`,
`tls_failed`, `opensky_timeout`, `opensky_rate_limited`, `opensky_unauthorized`,
`opensky_bad_response`, `not_configured`) mapped to friendly user copy.

## UI / UX

- **Home screen:** app title, current observer location chip (GPS or manual),
  a large **"What's overhead?"** button, and a result area.
- **States:** `idle` (prompt), `loading` (spinner + "Scanning the sky…"),
  `result` (result card or a "clear skies" empty state for `confidence == none`),
  `error` (friendly message + retry).
- **Result card:** callsign + operator headline, aircraft type & registration,
  route (origin → destination) when known, a compact metrics row
  (elevation°, bearing, distance, altitude), optional aircraft photo, and a
  confidence badge. A subtle note when `enrichmentStatus == unavailable`.
- **Tip:** default `minElevationDeg` of 45° is strict; offer a "widen search"
  toggle (e.g. 10°) in a settings sheet, matching the library guidance.

## Packages (proposed)

- `http` — REST calls (or `dio` if we want interceptors/timeout niceties).
- `geolocator` — device location + permission handling.
- `permission_handler` — explicit permission UX (if needed beyond geolocator).
- State management: `flutter_riverpod` (or `provider`) for the identify controller.
- `flutter_secure_storage` — only if we ever store user-entered credentials.
- Dev: `mocktail`/`http_mock_adapter` for network fakes, `flutter_lints`.

Keep the dependency set minimal; all are pure-Dart/Flutter with no native code
beyond geolocator.

## Milestones

- **M0 — Scaffold.** *(done)* `flutter create mobile`, lints, folder structure,
  `flutter test` wiring, dependencies (`http`, `geolocator`, `flutter_riverpod`,
  `mocktail`).
- **M1 — Domain core (pure Dart).** *(done)* `geo.dart` + `ranking.dart` +
  `models.dart` + `identify_config.dart` with unit tests mirroring
  `aircraft_id_geo_tests` (distance ≈111.19 km/deg lat, bearings, elevation
  45°/90°, bounding box, ranking, confidence). No network.
- **M2 — Networking.** *(done)* `opensky_client`, `adsbdb_client`, shared `http`
  transport with timeouts + body caps + error mapping, plus `errors.dart`; tests
  against recorded JSON fixtures (including the verified `DLH804` / `D-AIZE`
  response).
- **M3 — Orchestration + controller.** *(done)* `AircraftService.identify` and the
  idle/loading/success/failure state machine, tested with a fake service.
- **M4 — UI.** *(done)* Home screen, result card, empty/error states, location chip.
- **M5 — Location & permissions.** *(done)* GPS via geolocator, iOS/Android permission
  strings, manual-entry fallback.
- **M6 — Integration + polish.** *(done)* `integration_test` for tap→card with
  mocked HTTP (`integration_test/app_test.dart`), light/dark Material 3 theming,
  and an optional-auth OpenSky hook. Remaining polish (app icon, store metadata)
  is cosmetic and tracked as follow-up.

## Testing strategy

- **Unit:** geometry and ranking are pure functions → high-value, fast tests that
  can be checked for parity against the Erlang EUnit expectations.
- **Data mapping:** decode recorded OpenSky/ADSBDB JSON fixtures and assert the
  resulting `Candidate`/`IdentifyResult`, so schema drift is caught.
- **Controller/widget:** drive the controller with a fake `AircraftService`;
  widget-test the three visible states.
- **Integration:** one end-to-end tap→result flow with a mocked HTTP client (no
  live network in CI).

## Platform configuration

- **iOS:** `NSLocationWhenInUseUsageDescription` in `Info.plist`; ATS keeps HTTPS.
- **Android:** `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`; `INTERNET`
  permission; target a modern SDK.
- Provide a graceful path when location is denied (manual coordinate entry).

## Open questions

- **OpenSky auth:** *(decided)* ship **anonymous** (rate-limited) for the MVP.
  `OpenSkyClient` accepts an optional `tokenProvider` so a `Bearer` token can be
  attached without code changes; the full OAuth2 client-credentials token
  exchange (and/or the backend proxy in architecture option 2) is a documented
  follow-up if the anonymous quota proves too tight.
- **Photo usage rights:** confirm ADSBDB photo URLs are OK to display in-app.
- **Offline/last-result:** cache the last result for display when offline? (Nice
  to have, out of MVP scope.)
- **State management choice:** *(decided)* Riverpod.

## Definition of done (MVP)

- Tapping the button on a real device returns a correct result card for a plane
  overhead, a clear "clear skies" state when nothing qualifies, and friendly
  error copy for network/rate-limit failures.
- Geometry/ranking unit tests pass and agree with the Erlang reference behavior.
- ADSBDB/OpenSky mapping tests pass against recorded fixtures.
- Runs on both iOS and Android from a single `mobile/` codebase.
