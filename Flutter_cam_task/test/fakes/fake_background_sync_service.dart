import 'package:camera_sync/services/background_sync/background_sync_service.dart';

/// Records calls instead of touching any platform channel - the real
/// [WorkManagerBackgroundSyncService] talks to the `workmanager` plugin,
/// which has no meaningful behavior under `flutter test`.
class FakeBackgroundSyncService implements BackgroundSyncService {
  int initializeCallCount = 0;
  int scheduleCallCount = 0;
  int cancelCallCount = 0;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<void> schedulePeriodicSync() async {
    scheduleCallCount++;
  }

  @override
  Future<void> cancelScheduledSync() async {
    cancelCallCount++;
  }
}
