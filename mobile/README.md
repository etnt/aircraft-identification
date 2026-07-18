# Sky Overhead

Tap a button to identify the aircraft flying overhead, using public
[OpenSky Network](https://opensky-network.org/) and
[ADSBDB](https://www.adsbdb.com/) data.

Sky Overhead reads your current location, queries live ADS-B traffic near you,
ranks the candidates by how close they are to being directly overhead, and shows
the best match enriched with route and registration details.

## How it works

1. Resolve the observer's position via device GPS (`geolocator`).
2. Query OpenSky for aircraft states within a bounding box around you.
3. Rank candidates by elevation angle, keeping those above a minimum elevation
   (default 18°) so only aircraft that are genuinely overhead are considered.
4. Enrich the top match with callsign/route/registration data from ADSBDB.
5. Present the result — or a friendly "Clear skies" message when nothing
   qualifies.

### Observer location

On startup the app seeds the observer position with a **hard-coded default of
central Stockholm** (`59.3293, 18.0686`, defined as `kDefaultConfig` in
`lib/src/state/config_provider.dart`). This is just a placeholder shown in the
location chip before any location is set — it is not derived from your device,
IP, or locale. Replace it at runtime by tapping **Use my location** (device GPS)
or **Enter location** (manual coordinates).

## Project structure

```
lib/src/
  config/   App configuration (min elevation, search radius, endpoints).
  data/     HTTP transport + OpenSky/ADSBDB clients, aircraft & location services.
  domain/   Pure models, geospatial math (geo.dart), and ranking logic.
  state/    Riverpod controllers (identify, location) and providers.
  ui/       Screens and widgets (home screen, result card, location bar).
```

## Tech stack

- **Flutter** (Material 3) — Dart SDK `^3.12.0`
- **flutter_riverpod** — state management
- **http** — REST calls to OpenSky and ADSBDB
- **geolocator** — device location with permission handling
- **mocktail** + **integration_test** — unit and end-to-end tests

## Getting started

Fetch dependencies:

```bash
flutter pub get
```

Run on a connected device or emulator:

```bash
flutter run                # auto-selects a device
flutter run -d <deviceId>  # target a specific device (see: flutter devices)
```

## Running on a physical Android phone

1. **Enable Developer options** on the phone: Settings → About phone → tap
   **Build number** seven times.
2. **Enable USB debugging**: Settings → System → Developer options → **USB
   debugging** on.
3. **Connect the phone to the computer** with a **data-capable** USB cable
   (charge-only cables will not work). Plug directly into the machine rather than
   through a hub or dock.
4. **Set the USB mode** on the phone to **File transfer / MTP** via the USB
   notification — some phones default to charge-only, which blocks the data
   connection.
5. **Authorize the computer**: unlock the phone and accept the *Allow USB
   debugging?* prompt (tick *Always allow from this computer* to skip it next
   time).
6. **Verify the device is detected**:

   ```bash
   # platform-tools ships with the Android SDK, e.g.
   #   macOS:  $HOME/Library/Android/sdk/platform-tools
   adb devices -l     # should list your phone with state "device"
   flutter devices    # should show the phone
   ```

   If it shows `unauthorized`, re-accept the on-phone prompt. If it does not
   appear at all, the connection is physical — try another cable/port and
   re-check the USB mode.
7. **Build, install, and launch** on the phone:

   ```bash
   flutter run -d <deviceId>   # deviceId from `flutter devices`, e.g. 56041FDCH00CDN
   ```

   Flutter builds the debug APK, installs it, and starts a live debug session
   (hot reload with `r`, hot restart with `R`). The app also stays installed in
   the app drawer after you quit the session.

On first launch the app will ask for **location permission** — allow it so the
observer position can be resolved.

## Testing

```bash
flutter analyze lib test integration_test
flutter test                   # unit and widget tests
flutter test integration_test  # end-to-end integration test
```

## Permissions

The app requests **location** access at first launch to determine the observer
position, and requires **internet** access for the OpenSky and ADSBDB APIs.
Both are declared in the Android and iOS platform manifests.

## Data sources

- Aircraft states: [OpenSky Network REST API](https://openskynetwork.github.io/opensky-api/rest.html)
- Aircraft/route metadata: [ADSBDB API](https://www.adsbdb.com/)
