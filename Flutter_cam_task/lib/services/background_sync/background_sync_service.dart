abstract interface class BackgroundSyncService {
  /// Registers the platform background-work callback. Must be called once
  /// at app startup, before scheduling any work.
  Future<void> initialize();

  Future<void> schedulePeriodicSync();

  Future<void> cancelScheduledSync();
}
