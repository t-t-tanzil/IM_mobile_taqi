# Attendance — Geo-Fenced Attendance (Native Android)

A native Android application built with **Kotlin + Jetpack Compose** that allows a user to configure an office location from GPS, continuously track their distance from that location, and mark attendance only when they are within a **50-meter radius**.

The project follows **Clean Architecture + MVVM**, uses **Kotlin Flow** as the primary state-management mechanism, **Hilt** for dependency injection, and **Jetpack DataStore** for local persistence.

---

## Features

- Save the office location once using the device's current GPS position.
- Persist the configured office latitude and longitude locally.
- Display the saved office location in a map-style preview with a location pin.
- Continuously track the user's current GPS position.
- Calculate live distance from the office using the Haversine formula.
- Display distance using a circular progress gauge.
- Change the distance gauge to an out-of-range state when the user is more than 50 meters away.
- Allow attendance marking only when the user is within the 50-meter radius.
- Display clear **in-range / out-of-range** status information.
- Provide distinct handling for:
  - Location permission denied
  - Location permission permanently denied
  - Location services disabled
  - Temporary GPS unavailability
- Recover correctly when the user returns from system Settings after changing location permissions/services.
- Display attendance confirmation with the time attendance was marked.
- Double-back-press-to-exit behavior.
- Forced dark theme matching the assessment reference design.
- JVM unit tests for core business logic and state transitions.

---

# UI Overview

The main attendance screen follows the assessment's reference design:

```text
┌─────────────────────────────────────┐
│                                     │
│          OFFICE LOCATION            │
│                                     │
│       ┌─────────────────────┐       │
│       │                     │       │
│       │       📍 PIN        │       │
│       │                     │       │
│       │     LAT / LONG      │       │
│       │                     │       │
│       └─────────────────────┘       │
│                                     │
│       ┌─────────────────────┐       │
│       │      DISTANCE       │       │
│       │                     │       │
│       │        ◯            │       │
│       │       12m            │       │
│       │                     │       │
│       └─────────────────────┘       │
│                                     │
│      You are 12m away from office   │
│       Within attendance range       │
│                                     │
│   ┌─────────────────────────────┐   │
│   │                             │   │
│   │      Mark Attendance        │   │
│   │                             │   │
│   │   AVAILABLE 09:00 - 10:30   │   │
│   └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

When the user is **more than 50 meters away**, the distance gauge and status change to the out-of-range state:

```text
┌─────────────────────────────────────┐
│                                     │
│          OFFICE LOCATION            │
│                                     │
│       ┌─────────────────────┐       │
│       │         📍          │       │
│       │     LAT / LONG      │       │
│       └─────────────────────┘       │
│                                     │
│             🔴                       │
│          OUT OF RANGE               │
│                                     │
│      You are 120m away              │
│                                     │
│       OUT OF RANGE                  │
│       Move within 50m of the        │
│       office to mark attendance.    │
│                                     │
│   ┌─────────────────────────────┐   │
│   │      Mark Attendance        │   │
│   │          DISABLED           │   │
│   └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

The circular gauge represents **distance travelled away from the configured office**, rather than proximity to the office.

- `0m` → empty gauge
- Increasing distance → increasing gauge progress
- `200m+` → full gauge
- `>50m` → red out-of-range state
- `≤50m` → attendance eligible

---

# Architecture

The application follows a three-layer Clean Architecture structure:

```text
┌──────────────────────────────────────────────┐
│                 PRESENTATION                 │
│                                              │
│  AttendanceScreen                            │
│  AttendanceViewModel                         │
│  AttendanceUiState                           │
│  Permission / Screen State                   │
│                                              │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│                    DOMAIN                    │
│                                              │
│  Models                                      │
│  Repository Interfaces                       │
│  Use Cases                                   │
│                                              │
│  CalculateDistanceUseCase                    │
│  ValidateAttendanceLocationUseCase           │
│  GetOfficeLocationUseCase                    │
│  SaveOfficeLocationUseCase                   │
│  GetCurrentLocationUseCase                   │
│                                              │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│                     DATA                     │
│                                              │
│  AttendanceRepositoryImpl                    │
│  OfficeLocationDataStore                     │
│  FusedLocationDataSource                     │
│  Hilt DI                                     │
│                                              │
│  Jetpack DataStore                           │
│  FusedLocationProviderClient                 │
│                                              │
└──────────────────────────────────────────────┘
```

The dependency direction is intentionally one-way:

```text
Presentation
     │
     ▼
  Domain
     │
     ▼
   Data
```

The **domain layer contains no Android framework dependencies**, allowing the core business rules to be tested directly on the JVM.

---

# Reactive Data Flow

The application uses Kotlin `Flow` and `StateFlow` as the primary state-management mechanism.

```text
                    ┌──────────────────────┐
                    │      DataStore       │
                    │                      │
                    │ Saved office lat/lon │
                    └──────────┬───────────┘
                               │
                               ▼
                 GetOfficeLocationUseCase
                               │
                               │
                               ▼
                        OfficeLocation
                               │
                               │
                               ▼
                         ┌───────────┐
                         │  combine  │
                         └─────┬─────┘
                               │
                               ▲
                               │
                 GetCurrentLocationUseCase
                               │
                               │
                    ┌──────────┴──────────┐
                    │                     │
                    ▼                     ▼
             Current GPS Fix       Retry Trigger
                    │
                    ▼
        CalculateDistanceUseCase
                    │
                    ▼
         ValidateAttendanceLocation
                    │
                    ▼
          AttendanceUiState
                    │
                    ▼
          AttendanceViewModel
                    │
                    ▼
          AttendanceScreen
```

`AttendanceViewModel` combines the saved office location and current GPS location into a single reactive state.

Distance and attendance eligibility are therefore **derived values**, rather than independently maintained mutable state.

This avoids creating a second source of truth for whether the user is inside the attendance radius.

---

# Location & Geofencing

## Office Location

The user can configure the office location from the device's current GPS position.

The saved coordinates are persisted as:

```text
office_latitude
office_longitude
```

Both values are written together using a single DataStore `edit {}` transaction.

A location is considered configured only when both latitude and longitude are available.

---

## Distance Calculation

Distance is calculated using the **Haversine formula**.

```text
CalculateDistanceUseCase
        │
        ▼
Current Latitude / Longitude
        +
Office Latitude / Longitude
        │
        ▼
     Haversine
        │
        ▼
 Distance in meters
```

The implementation uses:

```text
EARTH_RADIUS_METERS = 6,371,000.0
```

The result is exposed as meters and used by both the UI and attendance validation logic.

---

# 50-Meter Attendance Rule

Attendance is allowed only when:

```text
distance <= 50 meters
```

The boundary is intentionally **inclusive**.

```text
0m ─────────────────── 50m ────────────────►
│                         │
│       ELIGIBLE          │    OUT OF RANGE
│                         │
└─────────────────────────┴─────────────────
                       boundary
```

Therefore:

| Distance | Attendance |
|---:|:---|
| 0m | Allowed |
| 10m | Allowed |
| 49.9m | Allowed |
| 50.0m | Allowed |
| 50.01m | Disabled |
| 100m | Disabled |

The radius rule is centralized in:

```text
ValidateAttendanceLocationUseCase
```

This prevents UI code from independently implementing the geofence rule.

---

# Distance Gauge

The circular gauge communicates how far the user is from the office.

It is intentionally a **distance gauge**, not a "remaining distance" gauge.

```text
Distance

0m             50m                  200m+
│               │                     │
▼               ▼                     ▼

○───────────────◔──────────────────────●
empty           threshold              full
```

The gauge reaches full progress at:

```text
DISTANCE_GAUGE_MAX_METERS = 200m
```

Distances beyond 200m remain visually capped at a full ring.

When the user crosses the 50-meter boundary:

```text
≤ 50m
  ↓
Normal state
  ↓
Attendance enabled
```

and:

```text
> 50m
  ↓
Red out-of-range state
  ↓
Attendance disabled
```

The gauge progress calculation is implemented as a pure function and is independently unit-tested.

---

# Attendance Action

The **Mark Attendance** action is placed inside a dedicated card matching the reference UI.

The card contains:

- Attendance action
- Lock/action icon
- Mark Attendance button
- Availability text

The button is enabled only when:

```text
isWithinAttendanceRadius == true
```

The enabled button uses the intended green accent.

When the user is outside the allowed radius, the button remains disabled while the surrounding card maintains its neutral visual treatment.

After a successful attendance action, the application displays a confirmation state containing the time attendance was marked.

---

# Availability Window

The UI displays:

```text
AVAILABLE 09:00 AM - 10:30 AM
```

This text is currently **static** and exists to match the assessment reference design.

It is not currently backed by:

- Device time
- Server configuration
- A schedule database
- A remote attendance system

The actual attendance gate is determined exclusively by the **50-meter location rule**.

---

# Permission Handling

Location permission handling is separated from location availability.

```text
LocationPermissionStatus

├── Granted
├── Denied
└── PermanentlyDenied
```

Location availability is handled separately:

```text
LocationAvailability

├── Unknown
├── Available
└── Unavailable
      ├── PermissionMissing
      ├── LocationServicesDisabled
      └── TemporarilyUnavailable
```

A pure function:

```text
resolveAttendanceScreenMode()
```

maps these signals to the appropriate UI state.

This keeps permission and location-service decisions out of the composable UI itself.

---

# Permission Recovery

The application re-checks permission and location state whenever the screen resumes.

```text
App resumes
     │
     ▼
permissionState.refresh()
     │
     ▼
viewModel.retryLocationUpdates()
     │
     ▼
Re-evaluate permission
     │
     ├── Granted
     │
     ├── Denied
     │
     ├── Permanently denied
     │
     └── Location services disabled
```

This covers cases such as:

- User grants permission from Settings.
- User enables location services from Settings.
- Permission state changes while the application is backgrounded.
- The location stream encounters a permission-related failure.

The permission state is intentionally **symmetric**: `refresh()` can both upgrade and downgrade the state.

For example:

```text
Granted → Denied
Denied  → Granted
```

This prevents the UI from remaining in a stale "permission granted" state.

---

# Transient GPS Unavailability

A newly registered location listener may temporarily report that location is unavailable before the first usable GPS fix arrives.

To avoid displaying an incorrect error state immediately, the implementation provides an **8-second grace period**.

```text
Location subscription
        │
        ▼
Location unavailable
        │
        ├── Real location arrives
        │        │
        │        ▼
        │      Normal state
        │
        └── No location after grace period
                 │
                 ▼
          Temporary failure UI
```

The grace period is cancelled early when a valid location becomes available.

This behavior was discovered and verified during live emulator testing rather than being assumed from static code inspection.

---

# Location Services Disabled

Permission being granted does not necessarily mean that the device's location services are enabled.

The application independently checks:

```text
LocationManagerCompat.isLocationEnabled
```

This produces a dedicated location-services-disabled state rather than incorrectly reporting the user as simply outside the attendance radius.

---

# Persistence

The office location is persisted using **Jetpack DataStore Preferences**.

```text
DataStore
│
├── office_latitude
└── office_longitude
```

Both values are written in one transaction:

```kotlin
dataStore.edit {
    it[latitudeKey] = latitude
    it[longitudeKey] = longitude
}
```

This ensures that latitude and longitude are updated atomically.

If the values are incomplete, the application treats the office location as unconfigured.

An `IOException` while reading the preferences is recovered as an empty preference state rather than crashing the application.

---

## Attendance State

Attendance-marked state is intentionally **not persisted**.

```text
AttendanceViewModel
        │
        ├── attendanceMarked
        └── markedAt
```

These values exist only in the ViewModel's in-memory state.

Consequently, they reset after:

- Process death
- Application restart
- A new ViewModel instance

There is intentionally no attendance history database or server integration in this assessment.

---

# Testing

The project contains **40 JVM unit tests with 0 failures**.

Tests can be executed with:

```bash
./gradlew testDebugUnitTest
```

## Test Coverage

| Test Class | Tests | Focus |
|---|---:|---|
| `AttendanceViewModelTest` | 12 | Reactive updates, eligibility, permission/service mapping, retry recovery, save/mark success & failure |
| `AttendanceScreenStateTest` | 8 | Screen-mode decision table and permission recovery |
| `ValidateAttendanceLocationUseCaseTest` | 6 | 50m boundary and inclusive radius |
| `DistanceGaugeProgressTest` | 5 | Gauge progress mapping |
| `OfficeLocationDataStoreMappingTest` | 4 | DataStore mapping and missing values |
| `CalculateDistanceUseCaseTest` | 4 | Haversine distance calculation |
| `GetCurrentLocationUseCaseTest` | 1 | Location forwarding |

### Total

```text
40 tests
0 failures
```

---

# Emulator Verification

The following behaviors were verified using a real Android emulator:

- Location permission request flow
- Permission denied flow
- Permanently denied flow
- Location services disabled
- Temporary GPS unavailability
- Mock GPS positioning
- Within/outside 50m transitions
- Attendance button enable/disable behavior
- Attendance success state
- Permission recovery after returning from a backgrounded state

Mock GPS positions were supplied using:

```bash
adb emu geo fix
```

The permission-revocation scenario was also tested live.

An important platform-level observation was made during that test: Android terminates the application process when runtime location permission is revoked through the tested mechanism. Therefore, that live scenario primarily exercised the cold-start permission path. The narrower `refresh()` downgrade branch is covered deterministically by `AttendanceScreenStateTest`.

This distinction is documented intentionally rather than claiming stronger live verification than was actually achieved.

---

# Physical Device Verification

The redesigned visual UI was also verified on a real Android device.

The following were checked:

- Map-style office location preview
- Saved coordinates display
- Circular distance gauge
- In-range state
- Out-of-range red state
- Disabled attendance button
- Enabled attendance button
- Attendance action card
- Double-back-press-to-exit behavior

The physical-device pass caught visual differences that were not obvious from emulator testing, including the out-of-range color and enabled-button styling, which were subsequently adjusted.

---

# Release Build Verification

Both debug and release build configurations were verified locally.

```bash
./gradlew assembleDebug
./gradlew :app:assembleRelease
```

The release APK is generated at:

```text
app/build/outputs/apk/release/app-release.apk
```

The release artifact was also verified with Android's APK signing verification tooling.

---

# Screenshots

Screenshots included in the repository demonstrate the major functional states of the application.

| Screenshot | Demonstrates |
|---|---|
| ![permission_request.png](screenshots/permission_request.png) | Location permission request |
| ![office_setup.png](screenshots/office_setup.png) | No office location configured |
| ![outside_range.png](screenshots/outside_range.png) | Outside 50m radius |
| ![within_range.png](screenshots/within_range.png) | Within 50m radius |
| ![attendance_marked.png](screenshots/attendance_marked.png) | Successful attendance state |
| ![permission_revoked_midsession.png](screenshots/permission_revoked_midsession.png) | Permission recovery flow |

Screenshots were captured from live application runs rather than being manually staged.

Mock GPS positions were supplied using:

```bash
adb emu geo fix
```

The screenshots represent actual application states and are stored under:

```text
android-attendance/screenshots/
```

---

# Project Structure

```text
android-attendance/
│
├── app/
│   └── src/
│       ├── main/
│       │   └── java/
│       │       └── com/geofence/attendance/
│       │           │
│       │           ├── data/
│       │           │   ├── datastore/
│       │           │   ├── location/
│       │           │   └── repository/
│       │           │
│       │           ├── domain/
│       │           │   ├── model/
│       │           │   ├── repository/
│       │           │   └── usecase/
│       │           │
│       │           ├── presentation/
│       │           │   ├── attendance/
│       │           │   └── splash/
│       │           │
│       │           ├── ui/
│       │           │   └── theme/
│       │           │
│       │           ├── App.kt
│       │           └── MainActivity.kt
│       │
│       └── test/
│           └── ...
│
├── screenshots/
├── build.gradle.kts
├── settings.gradle.kts
├── gradlew
└── README.md
```

### Main Components

```text
AttendanceScreen
       │
       ▼
AttendanceViewModel
       │
       ├──────────────► GetOfficeLocationUseCase
       │
       ├──────────────► GetCurrentLocationUseCase
       │
       ├──────────────► SaveOfficeLocationUseCase
       │
       ├──────────────► CalculateDistanceUseCase
       │
       └──────────────► ValidateAttendanceLocationUseCase
```

---

# Key Implementation Decisions

## Kotlin Flow Instead of Multiple Mutable UI States

The location pipeline is reactive:

```text
Office Location Flow
        +
Current Location Flow
        │
        ▼
     combine()
        │
        ▼
LocationSnapshot
        │
        ▼
AttendanceUiState
```

This avoids manually synchronizing:

- Current distance
- Attendance eligibility
- Office location
- Current GPS state

---

## Domain-Level Distance Validation

The 50-meter rule is implemented in the domain layer rather than directly inside Compose.

This allows the same rule to be tested independently of:

- Android UI
- GPS hardware
- Compose
- Activity lifecycle

---

## DataStore for Small Local State

DataStore was chosen instead of a database because the assessment only requires two persisted values:

```text
latitude
longitude
```

A relational database would introduce unnecessary complexity for this scope.

---

## Fused Location Provider

`FusedLocationProviderClient` is wrapped behind a data-source abstraction.

The domain layer therefore does not depend directly on Google Play Services types.

```text
FusedLocationProviderClient
          │
          ▼
FusedLocationDataSource
          │
          ▼
AttendanceRepository
          │
          ▼
Domain
```

---

# Known Limitations & Engineering Trade-offs

The following limitations are intentional and are documented rather than hidden.

### Static Map Preview

The office map is currently a lightweight static map-style preview containing:

- Map/grid styling
- Location pin
- Saved latitude/longitude

It is **not a live Google Maps integration**.

No Google Maps API key is required for the current implementation.

The code contains documentation describing the changes required to replace the preview with a real `GoogleMap` composable if needed.

---

### Static Availability Window

The:

```text
AVAILABLE 09:00 AM - 10:30 AM
```

text is currently static.

It does not represent a real attendance schedule and does not independently enable or disable attendance.

---

### Attendance State Is In-Memory

The attendance success state is held in the ViewModel.

It is not persisted to DataStore or a backend.

This is intentional because the assessment does not require attendance history or server-side attendance storage.

---

### Brief Secondary GPS Subscription

`setOfficeLocation()` creates a short-lived GPS subscription to obtain the current location.

The continuous location stream remains independently managed.

The subscriptions are correctly cleaned up, although this results in a small amount of redundant location work when setting the office location.

This was considered acceptable for the scope of the assignment.

---

### Resume Retry

`retryLocationUpdates()` is triggered whenever the application resumes.

This also means a brief re-subscription can occur when the application resumes without a meaningful location change.

The behavior is intentionally simple and ensures recovery after returning from system Settings.

---

### Gauge Calculation

The distance gauge caps visually at 200 meters.

Distances beyond that point remain represented by a full ring rather than continuing beyond the available UI range.

---

# Security & Repository Hygiene

The repository does not contain:

- Production credentials
- API secrets
- Keystore files
- Signing passwords
- Local machine configuration

Signing configuration is kept local through:

```text
keystore.properties
```

and is excluded through `.gitignore`.

A fresh clone can therefore build without requiring access to private signing material.

---

# How to Run

## Requirements

- Android Studio
- Android SDK
- JDK 17
- Android 8.0+ / API 26+
- Android device or emulator with location support

---

## Clone

```bash
git clone https://github.com/t-t-tanzil/IM_mobile_taqi.git
cd IM_mobile_taqi/android-attendance
```

---

## Build & Install Debug APK

```bash
./gradlew installDebug
```

Alternatively, open the `android-attendance` directory in Android Studio and run the application from the IDE.

---

## Run Unit Tests

```bash
./gradlew testDebugUnitTest
```

Expected result:

```text
40 tests
0 failures
```

---

## Build Release APK

```bash
./gradlew :app:assembleRelease
```

The resulting APK is generated at:

```text
app/build/outputs/apk/release/app-release.apk
```

---

# Release Signing

Release signing is optional and local-only.

The project checks for:

```text
keystore.properties
```

If signing properties are present, the configured keystore is used.

If no local keystore is available, the project falls back to debug signing so that a fresh clone remains buildable without private signing material.

Example local configuration:

```properties
storeFile=keystore/release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

The keystore and `keystore.properties` are intentionally not committed to the repository.

---

# Architecture Documentation

For a deeper technical walkthrough, see:

```text
ARCHITECTURE.md
```

The architecture document covers:

- Reactive location pipeline
- Dependency direction
- State management
- Permission state transitions
- DataStore persistence
- Location subscription lifecycle
- Background/recovery behavior
- Engineering trade-offs

---

# Generative AI Usage

Generative AI was used as a development assistant throughout the project.

AI assistance was used for areas including:

- Initial architecture planning
- Clean Architecture structure
- Kotlin and Jetpack Compose implementation
- Location and permission handling
- Flow-based state management
- Unit-test generation
- UI implementation
- Debugging
- Documentation

All generated output was reviewed, adapted, tested, and verified before being included.

Importantly, live device/emulator testing was used to validate behavior rather than relying solely on generated code or static reasoning.

For example, emulator testing exposed the transient GPS availability issue, which resulted in the introduction of the grace-period behavior.

The final implementation and documentation therefore represent a combination of AI-assisted development and manual engineering review/verification.

---

# Summary

This project implements a complete native Android geo-fenced attendance flow:

```text
┌──────────────────┐
│ Configure Office │
│   from GPS       │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Persist Location │
│    DataStore     │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Track Current GPS│
│      Flow        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Calculate Haversine
│     Distance     │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────┐
│ Validate ≤ 50 meters    │
└───────────┬─────────────┘
            │
       ┌────┴────┐
       │         │
       ▼         ▼
   Within 50m   > 50m
       │         │
       ▼         ▼
    Enabled    Disabled
       │         │
       ▼         ▼
    Mark       Out of
  Attendance   Range
```

The implementation prioritizes:

- Clear separation of concerns
- Reactive state management
- Testable domain logic
- Explicit permission/recovery states
- Atomic local persistence
- Live GPS-driven UI
- Honest documentation of limitations and trade-offs
- Verification through both automated tests and live device/emulator testing
