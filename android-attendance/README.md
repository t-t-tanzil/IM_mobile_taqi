# Attendance — Geo-Fenced Attendance (Native Android)

A native Android app (Kotlin + Jetpack Compose) that lets a user save an office location
once from GPS, then tracks their live distance from it and only allows marking attendance
while they're within a 50-meter radius. Built with Clean Architecture + MVVM, Kotlin Flow
as the sole state-management mechanism, Hilt for DI, and Jetpack DataStore for persistence.

## Features

- Save the office location once, from the device's current GPS fix.
- Continuous live distance readout from the office, recomputed reactively on every
  location update — not polled or recalculated on a timer.
- Circular distance gauge, a static map preview with the configured lat/lon and a pin, and
  a clear in-range / out-of-range status section.
- Mark Attendance action, enabled only inside the 50m radius.
- Distinct, recoverable UI states for: permission denied, permission permanently denied,
  location services disabled, and transient GPS unavailability.
- Double-back-press-to-exit on the single-screen app.
- Forced dark theme, matching the assignment's reference design.

## Architecture

Three layers, dependency direction enforced one-way: `presentation → domain → data`.

```
presentation/attendance/   AttendanceScreen (Compose) + AttendanceViewModel + UI-state types
domain/                    model / repository interface / use cases — zero Android imports
data/                      DataStore persistence + FusedLocationProviderClient adapter
data/di/                   Hilt module wiring the above together
```

`AttendanceViewModel` combines two Flows — the saved office location
(`GetOfficeLocationUseCase`) and a retry-driven current-location stream
(`GetCurrentLocationUseCase`) — into one `LocationSnapshot`, exposed as a single
`StateFlow<AttendanceUiState>` the Compose screen collects with
`collectAsStateWithLifecycle()`. There is no second source of truth: distance and
eligibility are recomputed every time either input Flow emits, never set imperatively.

```
DataStore.data ──► GetOfficeLocationUseCase() ─────┐
                                                     ├─ combine ─► CalculateDistanceUseCase
FusedLocationProviderClient (callbackFlow) ─►       │             ValidateAttendanceLocationUseCase
  GetCurrentLocationUseCase() ────────────────────┘                       │
        ▲                                                                 ▼
   retryLocationUpdates() (flatMapLatest trigger)          StateFlow<AttendanceUiState>
                                                                           │
                                                     AttendanceScreen (collectAsStateWithLifecycle)
```

The domain layer (`CalculateDistanceUseCase`, `ValidateAttendanceLocationUseCase`,
`GetOfficeLocationUseCase`, `SaveOfficeLocationUseCase`, `GetCurrentLocationUseCase`) is
plain Kotlin with no `android.*` imports — testable on the JVM with no emulator or
Robolectric. `AttendanceRepositoryImpl` is the only bridge between domain interfaces and
the two data sources (`OfficeLocationDataStore`, `FusedLocationDataSource`).

## Key Implementation Details

- **Distance** — `CalculateDistanceUseCase` implements the Haversine formula
  (`EARTH_RADIUS_METERS = 6_371_000.0`), returning meters as a `Float`.
- **50m radius** — `ValidateAttendanceLocationUseCase.ALLOWED_RADIUS_METERS = 50f`; the
  check is `distanceMeters <= ALLOWED_RADIUS_METERS`, so the boundary is **inclusive**
  (exactly 50.0m is eligible, 50.01m is not). Swept by a dedicated boundary test.
- **Distance gauge** — a "how far out of range" indicator, not a "how close" one: its
  progress *increases* with distance, reaching a full ring at `DISTANCE_GAUGE_MAX_METERS`
  (200m) and beyond (`distanceGaugeProgress()`, a pure function unit-tested on its own).
  The ring and center text turn red past the radius; the disc behind the ring also fills
  with a light-red background when out of range, so range is never conveyed by ring color
  alone (it's paired with the "AWAY" label, the status text below, and an icon).
- **Office map preview** — a static, illustrative placeholder (`Canvas` grid + a pin icon
  centered on it, with the saved latitude/longitude shown to 4 decimal places in a chip),
  **not a live map**. No Google Maps dependency or API key is wired up. The exact steps to
  swap it for a real `GoogleMap` composable (add `play-services-maps`/`maps-compose`, a
  manifest API-key meta-data entry, and a `MAPS_API_KEY` in `local.properties`) are written
  out as a doc comment directly above `OfficeMapPreview` in `AttendanceScreen.kt`.
- **Attendance action card** — a dashed-border container (custom
  `Modifier.dashedBorder()`) with a lock icon and the "Mark Attendance" button, colored
  green (`0xFF4CAF50`) only when enabled; the card border/background/icon stay neutral in
  both states — only the button itself changes color.
- **Availability window text** — the "AVAILABLE 09:00 AM - 10:30 AM" line under the button
  is a **static string**, matching the reference design's visual copy. It is not backed by
  a real clock, schedule, or config value, and does not gate the button — only the 50m
  radius does.
- **Double-back-press-to-exit** — a `BackHandler` shows a "Press back again to exit" Toast
  on the first press; a second press within 2 seconds (`DOUBLE_BACK_PRESS_INTERVAL_MS`)
  finishes the Activity.
- **Splash screen** — a Compose `SplashScreen` (badge with the launcher icon's location-pin
  glyph, title, subtitle, `CircularProgressIndicator`) shown for a fixed 2 seconds on
  launch, then `Crossfade`s into `AttendanceScreen`. Purely presentational.

## Location & Attendance Flow

```
GPS fix (FusedLocationProviderClient)
        │
        ▼
GetCurrentLocationUseCase  ──► CalculateDistanceUseCase (Haversine, meters)
        │                              │
        ▼                              ▼
  combine() with saved         ValidateAttendanceLocationUseCase
  office location                (distance <= 50f ?)
        │                              │
        └──────────────┬──────────────┘
                        ▼
              AttendanceUiState (distanceMeters, isWithinAttendanceRadius)
                        │
                        ▼
     DistanceGauge + RangeStatusSection + AttendanceActionCard(enabled = isWithinAttendanceRadius)
```

- **Within 50m** (inclusive): the gauge and status text render in the normal/primary
  color, the status section shows "You are `X`m away from the office" with "Within
  attendance range", and the Mark Attendance button is enabled.
- **Beyond 50m**: the gauge ring/disc/text switch to the red out-of-range palette, the
  status section shows "OUT OF RANGE" and "Move within 50m of the office to mark
  attendance." (the `50` is read from `ALLOWED_RADIUS_METERS`, not re-typed), and the
  button stays disabled.
- Marking attendance sets `attendanceMarked = true` and shows a success banner with the
  time it happened — this is in-memory `ViewModel` state (see **Persistence** below), not
  written to disk.

## Permission Handling

Two independent state machines, kept separate on purpose:

```
LocationPermissionStatus (Compose, request-flow status)      LocationAvailability (domain-adjacent, presentation)
├── Granted                                                  ├── Unknown
├── Denied              — system dialog can still be shown   ├── Available
└── PermanentlyDenied    — must open Settings                └── Unavailable
                                                                   ├── PermissionMissing
                                                                   ├── LocationServicesDisabled
                                                                   └── TemporarilyUnavailable(message)
```

`resolveAttendanceScreenMode()` (`AttendanceScreenState.kt`) is a pure function — no
Compose or Android in the loop — that picks one of four screens from those two signals:
request-permission card, "open app settings" card (permanently denied), "open location
settings" card (services disabled), or the real attendance content.

- **Recovery on resume** — `AttendanceScreen` observes `ON_RESUME` and calls
  `permissionState.refresh()` + `viewModel.retryLocationUpdates()`. This single hook covers
  both "granted permission and returned" and "enabled location services and returned"
  without opening a second GPS subscription (`retryLocationUpdates()` just re-triggers the
  existing `flatMapLatest`-managed one).
- **Permission revoked mid-session** — `refresh()` is symmetric: it upgrades
  `Denied → Granted` and also downgrades `Granted → Denied` when the OS no longer reports
  the permission as granted. `resolveAttendanceScreenMode()` also routes correctly on a
  `PermissionMissing` location-flow error even before `refresh()` has run.
- **Transient GPS unavailability** — Play Services can report `isLocationAvailable = false`
  immediately after a fresh registration, before a real fix has arrived. An 8-second grace
  period (found and fixed via live emulator testing, not by inspection) prevents this from
  flashing the screen into a false "unavailable" state; it's cancelled early by a real fix
  or an "available again" callback.
- **Location services disabled** is detected independently of permission status
  (`LocationManagerCompat.isLocationEnabled`) and routed to its own reason card.

## Persistence

Only the office location is persisted, via Jetpack **DataStore Preferences**
(`OfficeLocationDataStore`): two `Double` keys (`office_latitude`, `office_longitude`),
written together in a single `edit {}` transaction so there's never a partial write. A
location is considered "configured" only when both keys are present; an `IOException` on
read recovers to an empty preference set instead of crashing.

**Attendance-marked state is not persisted.** `attendanceMarked` and the marked-at
timestamp live only in `AttendanceViewModel`'s in-memory `StateFlow` — they reset on
process death, app restart, or navigating away and back to a fresh `ViewModel` instance.
There is no attendance-history log or database in this project.

## Testing

**40 JVM unit tests, 0 failures** (`./gradlew testDebugUnitTest`), no emulator or
Robolectric required:

| File | Tests | Focus |
|---|---:|---|
| `AttendanceViewModelTest` | 12 | reactive updates, eligibility sweep, permission/services/temporary-failure mapping, retry-recovery, save/mark success & failure |
| `AttendanceScreenStateTest` | 8 | screen-mode decision table, incl. the permission-revoked-mid-session branch |
| `ValidateAttendanceLocationUseCaseTest` | 6 | 50m boundary, inclusive edge |
| `DistanceGaugeProgressTest` | 5 | gauge progress mapping (0m, 120m, max, beyond-max, boundary) |
| `OfficeLocationDataStoreMappingTest` | 4 | preference-key mapping, missing-value handling |
| `CalculateDistanceUseCaseTest` | 4 | Haversine correctness |
| `GetCurrentLocationUseCaseTest` | 1 | pass-through forwarding |

**Emulator verification** (not unit-testable — requires the real
`FusedLocationProviderClient`/`Activity` framework): permission grant/deny/permanently-deny
flow, the transient-GPS-unavailability grace period (this is what actually surfaced that
bug), mock-GPS-driven within/outside-range transitions, and a permission-revoked-while-
backgrounded scenario. That last one confirmed the app recovers correctly, with the honest
caveat that Android kills the process on any runtime-permission revocation — so that
specific live test mainly proved the cold-start path; the `refresh()` downgrade branch
itself is verified deterministically by `AttendanceScreenStateTest` instead.

**Physical-device verification**: the visual redesign — map preview, distance gauge,
in-range/out-of-range colors, the dashed attendance card, and double-back-press-to-exit —
was verified live on a real Android device (Pixel 7), not just the emulator. Two issues
were caught this way and fixed as a direct result: the out-of-range red state initially
rendering as a pale M3 error tone rather than a clear red on real hardware (fixed with
explicit `0xFFEF6969`/`0xFFFAF5F6` colors), and the Mark Attendance button's enabled-state
green not matching the intended design on first pass.

**Release build verification**: `./gradlew assembleDebug` and `./gradlew :app:assembleRelease`
both succeed locally (release falls back to debug signing without a local keystore — see
**Release APK** below).

## Screenshots

| | |
|---|---|
| ![Location permission request](screenshots/permission_request.png) Requesting location permission | ![No office location set](screenshots/office_setup.png) No office location configured yet |
| ![Outside the radius](screenshots/outside_range.png) Outside the 50m radius — status text and disabled button | ![Within the radius](screenshots/within_range.png) Within the 50m radius — status text and enabled button |
| ![Attendance marked](screenshots/attendance_marked.png) Attendance marked, with the time it happened | ![Recovered after a revoked permission](screenshots/permission_revoked_midsession.png) Correctly back on the permission-request screen after the permission was revoked while backgrounded |

*Captured live on an emulator, using `adb emu geo fix` for the mock GPS positions — not
staged. These predate the visual redesign (dark theme, circular distance gauge, map
preview, dashed attendance card), so the colors and layout above no longer match the
current build exactly — but the states, flows, and copy they demonstrate are still
accurate. No screenshots of the redesigned UI exist in this repository yet. Also not
captured: the "Permission Required" (denied-not-permanently) and "Location Services
Disabled" reason cards, and the permanently-denied → Settings hand-off.*

## Project Structure

```
com.geofence.attendance/
├── domain/                 model, repository interface, use cases (pure Kotlin)
├── data/                   DataStore + FusedLocationProviderClient + Hilt DI module
├── presentation/attendance/ AttendanceScreen (Compose), AttendanceViewModel, UI-state types
├── presentation/splash/    SplashScreen (Compose)
├── ui/theme/               Material 3 theme
├── MainActivity.kt
└── App.kt                  @HiltAndroidApp
```

See `ARCHITECTURE.md` for a deeper walkthrough of the reactive pipeline and design
trade-offs.

## How to Run

**Requirements:** Android Studio or a configured Android SDK + JDK 17, `minSdk 26`
device/emulator (Android 8.0+).

```bash
git clone https://github.com/t-t-tanzil/IM_mobile_taqi.git
cd IM_mobile_taqi/android-attendance
./gradlew installDebug   # or open the folder in Android Studio and hit Run
```

```bash
./gradlew testDebugUnitTest   # 40 unit tests
```

## Release APK

```bash
./gradlew :app:assembleRelease
```

The output APK lands at `android-attendance/app/build/outputs/apk/release/app-release.apk`.
This repository does not host a pre-built APK or download link — build it locally with the
command above.

Release signing is optional and local-only: `app/build.gradle.kts` looks for a
`keystore.properties` file at the project root. If present, `release` signs with it;
otherwise it falls back to the debug signing config so the project stays buildable on a
fresh clone. Neither the keystore nor `keystore.properties` is committed (see
`.gitignore`). To produce a locally-signed release build, create your own keystore and add
`keystore.properties` next to `settings.gradle.kts`:

```properties
storeFile=keystore/release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

## Known Limitations & Trade-offs

- **No real map.** The office location preview is a static illustration (grid + pin + the
  coordinates), not Google Maps — there's no Maps API key in this project. The swap-in
  path is documented in code (`AttendanceScreen.kt`, above `OfficeMapPreview`).
- **The availability window text is static**, not a real schedule — it doesn't gate the
  Mark Attendance action.
- **Attendance-marked state is not persisted** — it's in-memory `ViewModel` state, reset on
  process death or restart. There is no attendance history/log.
- **`setOfficeLocation()` runs a brief second GPS subscription** alongside the continuous
  one; both clean up correctly, but it means a few seconds of redundant polling per tap —
  judged not worth sharing the flow for what it would save.
- **`retryLocationUpdates()` fires on every `ON_RESUME`**, even when nothing changed (e.g.
  pulling down the notification shade) — a brief, invisible re-subscription each time.
- **Screenshots predate the visual redesign** (see the Screenshots section above) — the
  states and copy they show are accurate, the colors/layout are not current.
- Core GPS/permission business logic (grace period, permission-revoke recovery) was
  verified on an emulator; the visual redesign and double-back-press-to-exit were verified
  on a real Pixel 7 (see **Testing**) — but no screenshots from that device pass were saved
  to this repository.

## Generative AI Usage

Generative AI was used as a development assistant throughout — architecture, use cases,
the Compose UI, tests, and this documentation — with all output reviewed, adapted, and
verified, including live emulator testing (which is what actually surfaced the transient-
GPS grace-period bug; a static-analysis-only pass would not have caught it). Representative
direction given during the engagement included: implementing Clean Architecture + MVVM
with Hilt/DataStore before any GPS code existed; wrapping `FusedLocationProviderClient`
behind a `Flow`-based interface with distinct domain exceptions instead of leaking Play
Services types; combining office/current location into one `StateFlow` with no second
source of truth for distance/eligibility; writing a boundary sweep for the 50m radius
rather than one happy-path number; debugging the transient-GPS issue against a real running
emulator instead of guessing; a final read-only audit pass that caught the permission-
revoke recovery gap; and, most recently, implementing the reference-design visual redesign
(map preview, distance gauge, dashed attendance card, colors), the splash screen and
double-back-press-to-exit, and this documentation pass itself.
