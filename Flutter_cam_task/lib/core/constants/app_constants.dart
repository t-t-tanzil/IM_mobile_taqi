/// App-wide constants, centralized so persistence keys and background-task
/// identifiers have a single source of truth once implemented.
class AppConstants {
  const AppConstants._();

  static const String uploadQueueStorageKey = 'pending_upload_batches';
  static const String capturedImagesDirectoryName = 'captured_images';

  static const String backgroundSyncTaskName = 'syncPendingUploadsTask';
  static const String backgroundSyncUniqueWorkName = 'com.geofence.camera_sync.periodicSync';
}
