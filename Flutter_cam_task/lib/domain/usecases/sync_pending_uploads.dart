import '../sync/sync_engine.dart';
import '../sync/sync_result.dart';

/// Thin entry point onto SyncEngine.sync() - the single synchronization
/// algorithm. Manual retry, connectivity restoration, and app startup all
/// call this same use case rather than talking to SyncEngine directly, or
/// (worse) re-implementing any part of the sync algorithm themselves.
class SyncPendingUploads {
  const SyncPendingUploads(this._syncEngine);

  final SyncEngine _syncEngine;

  Future<SyncResult> call() => _syncEngine.sync();
}
