# Android Attendance — Architecture Overview

Task 1 of the Senior App Developer technical assessment: a native Android geo-fenced
attendance app. This document explains how the project is put together, why it's put
together that way, and what trade-offs were made along the way.

## Assignment requirements (recap)

- Jetpack Compose `AttendanceScreen`
- User can set an office location from current GPS
- User can mark attendance only within a 50-meter radius of the saved office location
- Real-time distance indicator
- Built with Kotlin Flow
- Local persistence (no networking, no backend)
- Graceful handling of permission and hardware/location failures
- Clean Architecture + MVVM

No maps, no authentication, no networking, no WorkManager, no Room (DataStore only) —
all deliberately out of scope per the assignment.

## Tech stack

| Concern | Choice |
|---|---|
| UI | Jetpack Compose, Material 3 |
| DI | Hilt |
| Async | Kotlin Coroutines + Flow |
| Location | Google Play Services `FusedLocationProviderClient` |
| Persistence | Jetpack DataStore (Preferences) |
| Build | Gradle Kotlin DSL, version catalog (`libs.versions.toml`) |
| Tests | JUnit4 + `kotlinx-coroutines-test` (pure JVM unit tests, no instrumentation) |

Kotlin 2.0.21, AGP 8.8.0, Compose BOM 2024.09.03, Hilt 2.52, minSdk 26 / target 34.

## Package structure

```
com.geofence.attendance/
├── domain/                          # pure Kotlin — no Android imports
│   ├── model/
│   │   ├── OfficeLocation.kt        # latitude, longitude
│   │   ├── LocationData.kt          # latitude, longitude, accuracy, timestamp
│   │   └── LocationExceptions.kt    # PermissionMissing / ServicesDisabled / Unavailable
│   ├── repository/
│   │   └── AttendanceRepository.kt  # interface — the only contract data/ must satisfy
│   └── usecase/
│       ├── GetOfficeLocationUseCase.kt
│       ├── SaveOfficeLocationUseCase.kt
│       ├── GetCurrentLocationUseCase.kt
│       ├── CalculateDistanceUseCase.kt        # Haversine formula
│       └── ValidateAttendanceLocationUseCase.kt  # the 50m rule
│
├── data/                            # Android-specific implementations
│   ├── local/
│   │   └── OfficeLocationDataStore.kt   # DataStore Preferences read/write
│   ├── location/
│   │   ├── LocationDataSource.kt        # interface
│   │   └── FusedLocationDataSource.kt   # callbackFlow around FusedLocationProviderClient
│   ├── repository/
│   │   └── AttendanceRepositoryImpl.kt  # wires local + location sources together
│   └── di/
│       └── DataModule.kt                # Hilt @Binds / @Provides
│
├── presentation/attendance/
│   ├── AttendanceUiState.kt         # immutable UI state + LocationAvailability sealed type
│   ├── AttendanceViewModel.kt       # the reactive pipeline (see below)
│   ├── AttendanceScreen.kt          # Compose UI
│   ├── AttendanceScreenState.kt     # pure, testable screen-mode resolver
│   └── LocationPermissionState.kt   # Compose permission state holder (Granted/Denied/PermanentlyDenied)
│
├── ui/theme/Theme.kt                # Material 3 theme
├── MainActivity.kt
└── App.kt                           # @HiltAndroidApp
```

**Dependency direction is enforced one-way: `presentation → domain → data`.**
The domain layer never imports `android.location.Location`, `FusedLocationProviderClient`,
`Context`, or DataStore/Preferences types — it only knows about its own models and the
`AttendanceRepository` interface. `data/` is the only layer allowed to import Android
location/persistence APIs, and it adapts them into the domain's vocabulary.

## Why Clean Architecture here specifically

The assignment's own hint (persist office location → observe current location → compute
distance → validate radius) is naturally a pipeline with three independently-testable,
independently-swappable stages. Splitting it into domain/data/presentation means:

- The 50m business rule (`ValidateAttendanceLocationUseCase`) and the distance math
  (`CalculateDistanceUseCase`) can be unit-tested with plain numbers — no emulator, no
  mocked `Context`, no Robolectric.
- `FusedLocationDataSource` could be swapped for a different location provider without
  touching the ViewModel or the business rule.
- `AttendanceViewModel` never has to know *how* a location was obtained or *how* it's
  persisted — it only calls use cases.

## The reactive pipeline (the core of the app)

```
DataStore.data ──────────────► GetOfficeLocationUseCase() ──┐
                                                              │
FusedLocationProviderClient                                  ├─ combine ─► buildSnapshot()
  (callbackFlow) ─► GetCurrentLocationUseCase() ─.map/.catch─┘        │
        ▲                                                              ▼
        │                                              CalculateDistanceUseCase
   retryLocationUpdates()                              ValidateAttendanceLocationUseCase
   (flatMapLatest trigger)                                             │
                                                                        ▼
                                                          LocationSnapshot → stateIn
                                                                        │
                                                          _uiState.update { copy(...) }
                                                                        │
                                                                        ▼
                                                          StateFlow<AttendanceUiState>
                                                                        │
                                                          AttendanceScreen (collectAsStateWithLifecycle)
```

Key design decisions inside `AttendanceViewModel`:

- **Two kinds of state, one exposed `StateFlow`.** Office/current location, distance, and
  eligibility are *purely derived* — they come from `combine()`-ing two flows and never get
  set imperatively. Action-triggered flags (`isSavingOfficeLocation`, `attendanceMarked`,
  `errorMessage`) are set directly via `.update{}` from `setOfficeLocation()`/
  `markAttendance()`. Both are merged into the same `MutableStateFlow<AttendanceUiState>` —
  the reactive part is collected in `init{}` and only touches its own fields via `copy()`,
  so it never clobbers the action-driven fields and vice versa.
- **Errors are data, not exceptions crossing layers.** The current-location flow is wrapped
  in `.map { Result.success(it) }.catch { emit(Result.failure(it)) }` so a permission/GPS
  failure becomes a value flowing through `combine()` instead of crashing it.
- **Retry via `flatMapLatest`.** A `MutableSharedFlow<Unit>` retry signal feeds
  `locationRetrySignal.flatMapLatest { getCurrentLocationUseCase()... }`. Calling
  `retryLocationUpdates()` re-emits into that signal, which cancels the dead inner flow and
  opens a fresh subscription — this is what lets the app recover after the user grants
  permission or re-enables location services, without ever running two GPS subscriptions
  at once or recreating the ViewModel.
- **`setOfficeLocation()` does one-shot fetch, not continuous.** It calls
  `getCurrentLocationUseCase().first()` — a separate, short-lived subscription that cancels
  itself the moment it gets a value. Only on success is `SaveOfficeLocationUseCase` called;
  a failed fetch never touches persistence. A re-entrancy guard
  (`if (_uiState.value.isSavingOfficeLocation) return`) prevents a fast double-tap from
  firing two concurrent saves.

## Location layer: `FusedLocationDataSource`

```kotlin
override fun observeLocationUpdates(): Flow<LocationData> = callbackFlow {
    if (!hasLocationPermission()) { close(LocationPermissionMissingException()); return@callbackFlow }
    if (!isLocationServicesEnabled()) { close(LocationServicesDisabledException()); return@callbackFlow }
    // ... register LocationCallback, trySend() on each result ...
    awaitClose { fusedLocationClient.removeLocationUpdates(callback) }
}
```

- `callbackFlow` + `awaitClose` is what makes cancellation-safety possible: whenever the
  collecting coroutine is cancelled (screen closed, ViewModel cleared, retry superseding
  this subscription), `awaitClose` runs deterministically and unregisters the callback with
  Play Services. Without it, the callback would keep running (and draining battery)
  indefinitely.
- Permission-missing and location-services-disabled are checked and reported as **distinct**
  exception types before ever registering a callback — the ViewModel maps each to its own
  `LocationAvailability.Unavailable` case so the UI can react correctly to each.
- **Grace period on transient unavailability** (added after live device testing): Play
  Services reports `onLocationAvailability(false)` almost immediately on a fresh
  registration, before it has actually warmed up — even when a real fix is seconds away.
  Treating that as instantly fatal made `retryLocationUpdates()` effectively unable to ever
  recover, since every retry died within milliseconds. The fix waits 8 seconds (cancelled
  early by any location or a `true` availability signal) before actually closing the flow.
  This bug was **not** caught by unit tests — it only showed up when driving the real
  `FusedLocationProviderClient` on a running emulator, which is why the manual device pass
  mattered.

## Persistence: `OfficeLocationDataStore`

- Two `Double` preference keys (`office_latitude`, `office_longitude`), written together in
  a single `edit{}` transaction — never a partial write.
- Read maps to `OfficeLocation?`: both keys present → object, either missing → `null`.
- `IOException` (corrupted/unreadable file) is caught and recovered to `emptyPreferences()`;
  any other exception is rethrown, never silently swallowed.
- DataStore types (`Preferences`, `preferencesDataStore`) never leave this file — the rest
  of the app only sees `OfficeLocation?`.

## The 50m rule

```kotlin
// CalculateDistanceUseCase — Haversine, accounts for Earth's curvature
val a = sin(Δlat/2)² + cos(lat1)·cos(lat2)·sin(Δlon/2)²
val centralAngle = 2 * atan2(√a, √(1-a))
distance = EARTH_RADIUS_METERS * centralAngle

// ValidateAttendanceLocationUseCase
distanceMeters <= ALLOWED_RADIUS_METERS   // 50f, inclusive — 50.0 eligible, 50.01 not
```

The radius is a single named constant (`ValidateAttendanceLocationUseCase.ALLOWED_RADIUS_METERS`),
referenced (not re-implemented) anywhere it needs to be displayed. Compose never
recomputes this comparison — it only reads `uiState.isWithinAttendanceRadius`.

## Permission & failure states

`LocationAvailability` (presentation) is a sealed hierarchy, not a pile of booleans:

```
LocationAvailability
├── Unknown                                    (no location yet — loading)
├── Available
└── Unavailable
    ├── PermissionMissing
    ├── LocationServicesDisabled
    └── TemporarilyUnavailable(message)
```

Separately, `LocationPermissionStatus` (also presentation, Compose-only) models the
*request-flow* status, which only an `Activity` can determine
(`shouldShowRequestPermissionRationale`):

```
LocationPermissionStatus
├── Granted
├── Denied              — system dialog can still be shown
└── PermanentlyDenied    — user must go to Settings
```

`AttendanceScreenState.kt` has a single pure function, `resolveAttendanceScreenMode()`,
that decides which top-level screen to show from these two signals — kept out of the
Composable specifically so it's unit-testable without Compose/Android in the loop.

**Recovering after Settings/permission changes:** `AttendanceScreen` registers a
`LifecycleEventObserver` for `ON_RESUME` that calls `permissionState.refresh()` and
`viewModel.retryLocationUpdates()`. Requesting a runtime permission always pauses the host
Activity while the system dialog shows and resumes it after — so this single hook covers
both "granted permission" and "returned from location settings" without creating a second
GPS subscription (it just re-triggers the existing `flatMapLatest`-managed one).

`refresh()` is symmetric, not one-directional: it upgrades `Denied → Granted` (the original
behavior) and also downgrades `Granted → Denied` when the OS no longer reports the permission
as granted — added after a self-audit found that a permission revoked via Settings while the
app was backgrounded left the UI on a stale `Granted` status with no path back to the request
screen. `resolveAttendanceScreenMode()` also gained a branch for
`LocationAvailability.Unavailable.PermissionMissing` so the screen routes correctly even
before `refresh()` runs. Live-tested on an emulator with an honest caveat: revoking a runtime
permission kills the app's process (confirmed via PID check) regardless of the revocation
path, so that particular live test mostly proved the cold-start path works — the new
downgrade branch is verified deterministically by unit tests instead
(`AttendanceScreenStateTest`), since forcing the narrower "process survives" scenario isn't
achievable through `adb`.

## Compose layer

- `collectAsStateWithLifecycle()` for state collection (lifecycle-aware, stops collecting
  when the screen isn't visible).
- No composable touches `AttendanceRepository`, `DataStore`, or `FusedLocationProviderClient`
  — everything comes through `viewModel.uiState` and three actions:
  `setOfficeLocation()`, `markAttendance()`, `retryLocationUpdates()`.
- Distance formatting (`"120m away"` vs `"1.2km away"`) is presentation-only string
  formatting, not business logic.
- A one-shot `LaunchedEffect(uiState.errorMessage)` surfaces action failures as a Snackbar
  without needing an event-queue abstraction.

## Testing strategy

35 JVM unit tests, zero instrumentation/Robolectric:

| Layer | What's tested | How |
|---|---|---|
| `OfficeLocationDataStore` | mapping logic (both/either/neither key present) | `preferencesOf()` — pure JVM, no Context needed |
| `CalculateDistanceUseCase` | Haversine against independently-derived expected values | plain math, no mocking |
| `ValidateAttendanceLocationUseCase` | exact boundary (0/50/50.01/500m) | a small `FixedDistanceUseCase` subclass (no mocking library in the project) for exact floats, plus real-coordinate integration tests |
| `AttendanceViewModel` | reactive updates, permission/services/temporary-failure mapping, retry-recovery, save/mark success & failure | `FakeAttendanceRepository` (MutableStateFlow/MutableSharedFlow), `kotlinx-coroutines-test` |
| `AttendanceScreenState` | screen-mode branching incl. priority ordering and the permission-revoked-mid-session branch | pure function, no Compose runtime |

Deliberately **not** unit-tested (documented, not an oversight): `Location.toLocationData()`,
the `LocationManagerCompat` check, and the `rememberLocationPermissionState()` composable —
all require the real Android framework/Activity, which would mean Robolectric or
instrumentation. Given the assignment's own guidance to avoid over-building test
infrastructure, these were covered by manual device testing instead (see below).

## What manual device testing caught that unit tests couldn't

Unit tests fake the location source, so they can't catch timing bugs in the real
`FusedLocationProviderClient`. Running the app on an emulator end-to-end (grant permission →
set office location → move mock GPS → mark attendance → move out of range) surfaced the
`onLocationAvailability` grace-period bug described above. This is the reason the retry
mechanism is empirically confirmed working, not just unit-test-confirmed.

## Known trade-offs (intentional, not oversights)

- **`setOfficeLocation()` briefly runs a second, independent GPS subscription** alongside
  the continuous one (via its own `.first()` call). Both clean up correctly via
  `awaitClose` — no leak — but it means a few seconds of redundant polling on each tap.
  Avoiding this would mean sharing the location flow (e.g. `shareIn`), which was judged
  unnecessary complexity for what it saves.
- **`buildSnapshot()` computes the Haversine distance twice** per location update (once
  directly for display, once again inside `ValidateAttendanceLocationUseCase`). Cheap pure
  trig, called every few seconds — not worth changing the use case's public contract to
  avoid.
- **`retryLocationUpdates()` fires unconditionally on every `ON_RESUME`**, even when
  nothing changed (e.g. pulling down the notification shade). Matches the assignment's
  explicit ask for resume-triggered recovery; the cost is a brief GPS re-subscription each
  time, invisible to the user.
- **Attendance-marked state is sticky** — once marked, it stays shown even if the user
  later walks outside the radius. No reset mechanism exists yet; explicitly deferred as
  "local success state for now, we'll polish UX later" per the assignment's own phrasing.

## Running it

```bash
./gradlew assembleDebug     # build
./gradlew testDebugUnitTest # 35 unit tests
./gradlew installDebug      # install on a connected device/emulator
```

Needs `local.properties` with `sdk.dir` pointing at the Android SDK (gitignored, machine-specific).
