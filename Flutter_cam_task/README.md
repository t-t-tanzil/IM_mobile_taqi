# Camera Sync — Camera Capture & Upload Queue (Flutter)

A Flutter app with a custom camera UI (pinch/slider/quick-select zoom, tap-to-focus,
front/back camera switching), batch capture into a persistent local upload queue, and a
resilient sync engine that survives offline periods, app kills, and device reboots —
including automatic background synchronization via WorkManager.

## Features

- Custom camera preview: pinch-to-zoom, a vertical slider, and quick-select zoom buttons,
  all driving the same clamped zoom state.
- Front/back camera switching.
- Tap-to-focus with a visual indicator at the tap point.
- Batch photo capture, added to a persistent upload queue as one unit.
- Upload Manager screen: live connectivity status, per-batch status (pending / uploading /
  failed / synced), real photo thumbnails, manual retry, and a persistent "New Batch"
  action.
- Automatic retry when connectivity is restored — no button press required.
- Background sync via WorkManager, sharing the same queue and sync logic as the foreground
  app.
- Fixed 2-second splash screen and double-back-press-to-exit.

## Architecture

Clean Architecture in four layers, with a `flutter_bloc` Cubit as the sole
state-management mechanism:

```
presentation/   Cubit + State (Equatable) + View, one pair per feature
domain/         entities, repository interfaces, use cases, the sync engine itself
data/           repository implementations + concrete data sources (camera plugin, SharedPreferences, mock API)
services/       connectivity and background-sync abstractions + their platform implementations
core/           constants, typed errors, DI (get_it), small utilities
```

DI is `get_it` (`core/di/service_locator.dart`): `CameraCubit` and the use cases are
**factories** (fresh per screen/call); `SyncEngine`, both repositories, both data sources,
`UploadCubit`, and `BackgroundSyncService` are **lazy singletons** — one upload queue and
one sync engine for the whole app, shared between the camera screen and the Upload Manager
screen.

**Camera flow:**

```
CameraPreviewScreen → CameraCubit → CaptureImage (use case) → CameraRepository (interface)
   → CameraDataSource (interface) → FlutterCameraDataSource (only file that imports package:camera)
```

**Upload/sync flow — every trigger converges on the same `SyncEngine` instance:**

```
PendingUploadsScreen → UploadCubit → SyncPendingUploads (use case) → SyncEngine
   → UploadRepository (interface) → UploadRepositoryImpl
   → UploadQueueDataSource (SharedPreferences) + UploadDataSource (mock API)
```

| Trigger | Path |
|---|---|
| App startup | `UploadCubit` constructor → `SyncPendingUploads()` |
| Connectivity restored | `UploadCubit`'s connectivity-stream listener → same call |
| Manual "Sync now" / per-batch retry | `UploadCubit.retry()` → same call |
| WorkManager (background) | `callbackDispatcher()` → `SyncPendingUploads(freshSyncEngine)` → same call |

## Key Implementation Details

- **Zoom is not physical lens switching.** The quick-select buttons (`0.5, 1, 2, 3, 5`,
  filtered down in `zoom_button_calculator.dart` to whatever the active lens actually
  supports via `getMinZoomLevel()`/`getMaxZoomLevel()`) all set the **same** continuous
  zoom value the pinch gesture and slider set — one field (`CameraState.zoomLevel`), three
  inputs. This is the `camera` plugin's single-lens digital/optical zoom range, **not** a
  way to jump between a device's separate ultra-wide/wide/telephoto lenses the way a native
  camera app's 0.5x/1x/2x buttons typically do.
- **Front/back camera switching is real lens switching**, distinct from the zoom buttons
  above: the flip-camera control calls `CameraController`/`availableCameras()` to find the
  opposite `CameraLensDirection`, initializes a *new* controller on that physical camera,
  and only disposes the previous controller after the new one succeeds — and only after the
  UI has already dropped to a loading state, so the live preview widget is never left
  pointed at a controller mid-disposal. The in-progress capture batch is preserved across a
  switch; zoom range is re-fetched since front/back cameras commonly differ.
- **Tap-to-focus** normalizes the tap to a `0..1` coordinate (`NormalizedFocusPoint`),
  forwards it to `setFocusPoint`/`setExposurePoint`, and shows a ring at the raw tap
  `Offset` that auto-clears after 1.5s via a cancelable `Timer`.
- **Batch capture** copies each shot from the plugin's temp file into the app's persistent
  documents directory under a generated id; the in-memory batch is only cleared after it's
  confirmed persisted to the queue, so a failed persistence attempt never silently drops
  captured photos.
- **Splash screen** (`presentation/splash/splash_screen.dart`) fades in, holds for exactly
  2 seconds via a cancelable `Timer`, then fades into the camera screen.
- **Double-back-press-to-exit** — the camera screen (the app's root route) is wrapped in a
  `PopScope` that shows a "Press back again to exit" SnackBar on the first back press and
  calls `SystemNavigator.pop()` on a second press within 2 seconds. Scoped to the root
  screen only — the Upload Manager screen still pops normally with one back press.

## Queue & Persistence

`SharedPreferencesUploadQueueDataSource` stores the entire queue as one JSON array under a
single `SharedPreferences` key. Each batch has a status:

```
pending ──(sync attempt)──► uploading ──(success)──► [removed from queue + local files deleted]
   ▲                            │
   └────────(failure)───────────┘
                                 (stays "failed", remains in the queue, retried on the next sync trigger)
```

- Every write (`_writeAll`) is one atomic `SharedPreferences.setString` call — a process
  kill mid-write lands either the old value or the new one, never a torn one.
- **Process-death / reboot recovery**: any batch found stuck in `uploading` on the first
  read after a (re)start is recovered back to `pending`, so a kill mid-upload can't leave a
  batch permanently invisible to the sync engine. Corrupted JSON is treated as an empty
  queue rather than crashing; a single malformed record inside an otherwise-valid array is
  skipped without losing the rest.
- Local image files are deleted only *after* the mock API call has actually returned
  success — never before, never on failure.
- `SyncEngine._runSync()` processes syncable batches (`pending` + `failed`) strictly one at
  a time in a `for` loop, never concurrently.
- There is no separate "uploaded" history list — a batch simply leaves the queue on
  success.

## Connectivity & Synchronization

`ConnectivityPlusService` does not treat "an interface is connected" (from
`connectivity_plus`) as proof of internet access. It layers a **DNS reachability probe**
on top (`DnsLookupReachabilityChecker`, `InternetAddress.lookup('example.com')`) before
ever reporting `online`, and applies `.distinct()` so repeated identical statuses (e.g.
Wi-Fi flapping while still genuinely online) don't re-trigger redundant syncs. Connectivity
being restored is itself a sync trigger — no button press is needed for a previously-failed
batch to retry once the network comes back.

## Background Processing

`WorkManagerBackgroundSyncService.schedulePeriodicSync()` registers a periodic WorkManager
task (`NetworkType.connected` constraint, `ExistingPeriodicWorkPolicy.keep` — idempotent,
which is what prevents duplicate periodic jobs across the app's several scheduling call
sites). The background isolate (`background_sync_callback_dispatcher.dart`) builds its
**own minimal dependency chain** — a fresh `SharedPreferencesUploadQueueDataSource`,
`MockUploadDataSource`, and `ConnectivityPlusService` — and never touches `get_it`,
`BuildContext`, widgets, or any Cubit, since none of those exist in a background isolate.
It calls straight through `SyncPendingUploads → SyncEngine.sync()`, the same entry point
every other trigger uses. `sync_result_mapper.dart` maps `SyncResult` to the boolean
WorkManager's worker contract expects — only `completedWithFailures` reports failure,
deferring entirely to WorkManager's own backoff policy.

**`flutter test` cannot execute a real WorkManager job** — the unit suite stops at the pure
Dart boundary (`sync_result_mapper_test.dart`). Background execution was confirmed via live
**Android emulator verification**: `adb logcat` showed `WM-WorkerWrapper` starting the
worker and a fresh Flutter engine spinning up in that isolate, with a batch queued while
offline confirmed gone from the UI after the worker ran — evidence both isolates share the
same persisted queue. A full `adb reboot` with a pending batch queued, followed by
reopening the app, was also verified to leave the batch still queued.

**Android-only, by design.** `WorkManagerBackgroundSyncService`'s every method is a no-op
off Android (`Platform.isAndroid` guard). This was added after actually running the app on
the iOS Simulator: the `workmanager_apple` plugin (0.9.10) submits a `BGTaskScheduler`
request *before* registering its launch handler, which iOS rejects outright —
`BGTaskScheduler.submitTaskRequest` → `_handleSubmissionWithoutRegistrationForTaskRequest`,
a guaranteed `SIGABRT` crash on first launch, confirmed via the crash log's symbolicated
backtrace. That's a bug in the plugin's iOS implementation, not something fixable from this
app's Dart code or `Info.plist` (which already lists the correct
`BGTaskSchedulerPermittedIdentifiers` entry). Guarding it off means the rest of the app —
camera, capture, the persistent queue, and every *foreground* sync trigger (startup,
connectivity restored, manual retry) — works correctly on iOS; only the periodic background
safety net is Android-only.

## Testing

**79 tests, `flutter test` — all passing. `flutter analyze` — no issues.**

Notable coverage: `sync_engine_test.dart` (sequential-not-concurrent uploads, stale-
`uploading` recovery, files deleted only after confirmed success, missing-file handling),
`camera_cubit_test.dart` (zoom clamping, focus indicator timing, capture success/failure,
and 5 dedicated tests for `switchCamera()` — lens toggling, zoom-range refresh, batch
preservation across a switch, the not-ready guard, and failure handling), `upload_cubit_test.dart`
(a dedicated test shares one `SyncEngine` instance across retry + connectivity-restore + a
simulated third trigger and asserts exactly one execution, not three),
`shared_preferences_upload_queue_data_source_test.dart` (stale-recovery, corrupted JSON),
`sync_result_mapper_test.dart` (the WorkManager result-mapping contract).

- **Real Android device verification (Pixel 7)**: the visual redesign, real capture with a
  live camera feed, front/back camera switching, and double-back-press-to-exit were all
  verified live on a physical Pixel 7 — this is also where two real UI bugs (a color
  contrast issue in the out-of-range/error state on real hardware, and an early flip-camera
  layout overlap) were caught and fixed.
- **Android emulator verification**: the full capture → queue → sync flow, a stress pass of
  rapid consecutive camera switches, the splash screen timing, and the WorkManager/reboot
  evidence described above — on the Android emulator (`Pixel_9_Pro` AVD) via `adb`, used
  after the Pixel 7 became unavailable partway through this engagement.
- **iOS Simulator verification**: `flutter run` on an iPhone 17 (iOS 26.2) simulator. This
  surfaced two real, fixed issues — the `IPHONEOS_DEPLOYMENT_TARGET` in
  `ios/Runner.xcodeproj/project.pbxproj` had to be raised from 13.0 to 14.0 (`workmanager`'s
  iOS package requires it), and the WorkManager/`BGTaskScheduler` crash described in
  **Background Processing** above. After both fixes: the splash screen, the camera
  permission flow, the app's own graceful "no usable camera" handling (the Simulator has no
  real camera hardware), and the Upload Manager screen (including its live connectivity
  pill) were all confirmed working via screenshots — see **Screenshots** below. Capture and
  the full upload flow were not exercised on iOS, since the Simulator cannot provide a real
  camera feed, and no physical iOS device was used.
- **Release build verification**: `flutter build apk --release` succeeds locally.

## Screenshots

| | |
|---|---|
| ![Camera preview](screenshots/camera_preview.png) Camera preview, live feed | ![Tap to focus](screenshots/tap_to_focus.png) Tap-to-focus indicator at the tapped point |
| ![Batch captured](screenshots/batch_captured.png) A 3-photo batch captured, ready to add to the queue | ![Pending uploads](screenshots/pending_uploads.png) A queued batch in the pending-uploads list |
| ![A queued batch, pending state](screenshots/upload_failed.png) A queued batch shown in its "Pending" state | ![Empty queue after a successful sync](screenshots/retry_success.png) Empty queue after a successful sync |
| ![Reboot persistence](screenshots/reboot_persistence.png) The queued batch still present after a full device reboot | |

**iOS Simulator (current build, redesigned UI):**

| | |
|---|---|
| ![iOS splash screen](screenshots/ios_splash.png) The splash screen on an iPhone 17 simulator (iOS 26.2) | ![iOS Upload Manager](screenshots/ios_upload_manager.png) The redesigned Upload Manager screen on the same simulator, live connectivity pill included |

*The first table's captures are real, from earlier Android emulator testing, not staged —
but they predate the current visual redesign (dark "Upload Manager" theme,
connection-status pill, colored batch cards with real thumbnails, the bottom "Upload Batch"
action, front/back camera switching, and the splash screen), so the layout/colors shown no
longer match the current build — the underlying states and data are still accurate.
`upload_failed.png` is named for the scenario it was captured during, but the frame that
was saved actually shows the batch in its "Pending" state, not a "Failed" badge — captioned
accurately above rather than as originally named. The iOS table's two captures **are** from
the current redesigned build. **No screenshot of the zoom controls exists in this
repository**: the emulator's/simulator's virtual camera reports a zoom range too narrow for
the quick-select buttons to clear their filter, so a meaningful capture of them would need
a physical device. No screenshot of the redesigned Upload Manager screen or the splash
screen on Android exists yet, and no screenshot of the flip-camera control or a live camera
feed on iOS exists (the Simulator has no real camera).*

## Project Structure

```
lib/
├── core/            constants, typed errors, DI (get_it)
├── domain/          entities, repository interfaces, use cases, SyncEngine
├── data/            camera/upload data sources + repository implementations
├── services/        connectivity + background-sync abstractions and implementations
└── presentation/
    ├── camera/      CameraCubit/State, CameraPreviewScreen, zoom + focus widgets
    ├── uploads/     UploadCubit/State, PendingUploadsScreen (Upload Manager)
    ├── splash/      SplashScreen
    └── theme/       AppColors / AppTheme
```

## How to Run

**Requirements:** Flutter SDK (Dart `^3.12.2`, this repo built/tested against Flutter
3.44.x). Android (device or emulator) is the primary verified target, including background
sync; iOS runs on the Simulator (Xcode required) but has no real camera there and no
background sync (see **Known Limitations**).

```bash
git clone https://github.com/t-t-tanzil/IM_mobile_taqi.git
cd IM_mobile_taqi/Flutter_cam_task
flutter pub get
flutter run
```

```bash
flutter analyze
flutter test
```

## Release APK

```bash
flutter build apk --release
```

The output APK lands at `Flutter_cam_task/build/app/outputs/flutter-apk/app-release.apk`.
This repository does not host a pre-built APK or download link — build it locally with the
command above.

The release build type currently signs with the **debug keystore**
(`android/app/build.gradle.kts`), matching the default Flutter template — there is no
custom release signing config in this project. This is acceptable for an assessment
submission; a real release would need a dedicated, non-debug signing key.

## Known Limitations & Trade-offs

- **Zoom buttons are not physical lens switching** — see Key Implementation Details above.
  Front/back camera switching is real lens switching; the 0.5x–5x buttons are not.
- **Cross-isolate concurrency**: `SyncEngine._isSyncing` is an in-memory boolean, correct
  within one isolate (verified by a test firing three simultaneous calls), but it is not a
  cross-process mutex — the WorkManager isolate builds its own separate `SyncEngine`
  instance. The realistic overlap window (foreground sync at the exact moment the
  background worker also fires) is narrow, and WorkManager itself guarantees at most one
  execution of a given unique periodic job. A production system against a real (non-mock)
  API without inherent idempotency would want a persisted cross-process lock or an
  idempotency key on the upload request.
- **Mocked upload API** — `MockUploadDataSource` is a deterministic success/failure
  stand-in, never a real HTTP call, per the assignment's note that no real API would be
  provided.
- **Background sync is Android-only.** The `workmanager_apple` (iOS) plugin has a real bug
  in its `BGTaskScheduler` registration ordering that crashes the app on launch — confirmed
  by actually running it on the iOS Simulator, not assumed. Every method on
  `WorkManagerBackgroundSyncService` is now a no-op off Android as a result (see
  **Background Processing**). Camera, capture, the persistent queue, and foreground sync are
  unaffected on iOS.
- **No physical device was used for iOS.** iOS verification was on the Simulator only,
  which has no real camera — capture and the full upload flow were not exercised there.
  Android verification included both a real device (Pixel 7) and an emulator — see
  **Testing**.
- **Screenshots predate the visual redesign on Android, and the zoom controls are not
  captured on either platform** — see the Screenshots section above.

## Generative AI Usage

Generative AI was used as a development assistant throughout — architecture, the camera
UI, the sync engine, tests, and this documentation — with all output reviewed, adapted, and
verified, including live testing on a real Android device, an Android emulator, and the iOS
Simulator (which is what produced the WorkManager evidence above, the front/back-camera-
switch crash fix, a rendering bug in the redesigned Upload Manager list, the iOS
`BGTaskScheduler` crash and its fix, and other issues static analysis alone would not have
caught, such as an `async*`/broadcast-stream subscription-timing race in early sync-engine
work). Representative direction given during the engagement included: building the
persistent upload queue before the camera UI, with an explicit test list covering
corrupted-data and stale-`uploading` recovery; requiring every sync trigger (`UploadCubit`,
connectivity, WorkManager, manual retry) to converge on one `SyncEngine.sync()` rather than
re-implementing the algorithm per trigger; not trusting `connectivity_plus`'s interface
signal alone and layering a real reachability check; keeping the WorkManager isolate's
dependency chain fully separate from `get_it`/UI state; verifying background execution live
via `adb logcat` rather than accepting "the code should work"; a visual redesign to match
the assignment's reference screenshots, adding real front/back camera switching, a splash
screen, and double-back-press-to-exit; and, most recently, actually running the app on the
iOS Simulator rather than leaving that claim untested, which is what found and fixed the
`BGTaskScheduler` crash, plus this documentation pass.
