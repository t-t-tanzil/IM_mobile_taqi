import '../../domain/sync/sync_result.dart';

/// Maps a [SyncResult] to the boolean WorkManager's background task
/// contract expects: `true` = done, don't retry; `false` = failed, let
/// WorkManager's own backoff policy retry. This mapping is the only
/// retry-related decision made in the background-sync path - no second
/// backoff algorithm is implemented anywhere; WorkManager alone decides
/// *when* a retry happens.
///
/// - completed / nothingToSync: genuine success.
/// - skippedOffline: WorkManager's own network constraint should already
///   prevent this from happening, but if it does, treating it as success
///   (not retry) avoids hammering the device for a condition SyncEngine
///   already handled safely - the queue is untouched and will be picked up
///   by the next periodic run or an in-app trigger.
/// - alreadyInProgress: a foreground-triggered sync is already running
///   against the exact same queue; retrying here would just race it again
///   for no benefit.
/// - completedWithFailures: a genuine upload failure. This is the only
///   case that should trigger WorkManager's backoff retry.
bool mapSyncResultToWorkManagerSuccess(SyncResult result) {
  switch (result) {
    case SyncResult.completed:
    case SyncResult.nothingToSync:
    case SyncResult.skippedOffline:
    case SyncResult.alreadyInProgress:
      return true;
    case SyncResult.completedWithFailures:
      return false;
  }
}
