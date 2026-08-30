import '../entities/image_batch.dart';
import '../entities/upload_status.dart';
import '../repositories/upload_repository.dart';
import '../../services/connectivity/connectivity_service.dart';
import 'sync_result.dart';

/// The single synchronization algorithm in the app. Manual retry,
/// connectivity restoration, application startup, and (in a later phase)
/// the background worker all funnel through this one sync() method -
/// nothing else may re-implement upload-attempt logic. Processes batches
/// strictly sequentially (not concurrently), which is simpler, safer for
/// mobile devices, and sufficient at this scale.
///
/// Deliberately touches only [UploadRepository] and [ConnectivityService]
/// (both plain interfaces) - never SharedPreferences, the camera plugin,
/// Flutter widgets, or the filesystem directly; file existence checks and
/// deletion are the repository's responsibility.
class SyncEngine {
  SyncEngine(this._uploadRepository, this._connectivityService);

  final UploadRepository _uploadRepository;
  final ConnectivityService _connectivityService;

  // A plain instance-scoped flag is enough here: sync() has no `await`
  // between checking and setting it, so Dart's single-threaded event loop
  // guarantees no other call can interleave between those two lines - no
  // heavier lock/mutex primitive is needed for this to be race-free.
  bool _isSyncing = false;

  Future<SyncResult> sync() async {
    if (_isSyncing) return SyncResult.alreadyInProgress;
    _isSyncing = true;
    try {
      return await _runSync();
    } finally {
      _isSyncing = false;
    }
  }

  Future<SyncResult> _runSync() async {
    final connectivity = await _connectivityService.checkConnectivity();
    if (connectivity == ConnectivityStatus.offline) {
      return SyncResult.skippedOffline;
    }

    final batches = await _uploadRepository.getPendingBatches();
    // Only Pending/Failed are eligible - Uploading may represent a
    // still-in-progress attempt (startup recovery already converts any
    // stale Uploading left over from a killed app back to Pending).
    final syncable = batches
        .where(
          (batch) =>
              batch.status == UploadStatus.pending || batch.status == UploadStatus.failed,
        )
        .toList();

    if (syncable.isEmpty) {
      return SyncResult.nothingToSync;
    }

    var anyFailure = false;
    for (final batch in syncable) {
      final succeeded = await _uploadOne(batch);
      if (!succeeded) anyFailure = true;
    }

    return anyFailure ? SyncResult.completedWithFailures : SyncResult.completed;
  }

  Future<bool> _uploadOne(ImageBatch batch) async {
    await _uploadRepository.updateBatchStatus(batch.id, UploadStatus.uploading);

    try {
      await _uploadRepository.uploadBatch(batch);
    } catch (_) {
      await _uploadRepository.updateBatchStatus(batch.id, UploadStatus.failed);
      return false;
    }

    // Upload confirmed successful. Remove from the queue first: if this
    // itself throws, we deliberately do NOT delete the files below - the
    // batch is still referenced by the queue (as Uploading) and must stay
    // retryable rather than end up pointing at files that no longer exist.
    // A harmless duplicate re-upload on the next sync is an acceptable
    // trade-off versus silently losing the batch or corrupting the queue.
    try {
      await _uploadRepository.removeBatch(batch.id);
    } catch (_) {
      return true;
    }

    await _uploadRepository.deleteBatchFiles(batch);
    return true;
  }
}
