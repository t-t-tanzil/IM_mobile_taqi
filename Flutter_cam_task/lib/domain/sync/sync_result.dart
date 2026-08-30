/// Lets the presentation layer show meaningful feedback for a sync
/// attempt without knowing anything about how SyncEngine works internally.
enum SyncResult {
  /// All syncable batches uploaded successfully (queue may still be empty
  /// if there was nothing to do besides that - see [nothingToSync] for the
  /// "nothing existed at all" case).
  completed,

  /// At least one batch uploaded successfully, but at least one failed.
  completedWithFailures,

  /// No attempt was made at all - the device is offline.
  skippedOffline,

  /// The queue had no pending/failed batches to process.
  nothingToSync,

  /// A sync was already running; this call was a no-op rather than a
  /// second concurrent attempt.
  alreadyInProgress,
}
