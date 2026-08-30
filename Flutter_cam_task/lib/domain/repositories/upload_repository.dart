import '../entities/image_batch.dart';
import '../entities/upload_status.dart';

/// Combines the local persistent queue with the (mocked) remote upload.
/// Persistence must survive screen recreation and app restart.
abstract interface class UploadRepository {
  /// Persists a new batch to the local queue as [UploadStatus.pending].
  Future<void> addBatch(ImageBatch batch);

  /// A one-shot snapshot of the current queue.
  Future<List<ImageBatch>> getPendingBatches();

  /// Reconstructed from local persistence on every subscription/app start.
  /// A batch found stuck in [UploadStatus.uploading] (e.g. the app was
  /// killed mid-upload) is recovered back to [UploadStatus.pending] on the
  /// first read after app start.
  Stream<List<ImageBatch>> observePendingBatches();

  Future<void> updateBatchStatus(String batchId, UploadStatus status);

  /// Removes a batch from the queue. Never deletes its image files - call
  /// [deleteBatchFiles] separately once the caller has confirmed the
  /// upload actually succeeded (see SyncEngine).
  Future<void> removeBatch(String batchId);

  /// Best-effort deletion of a batch's local image files. Never throws -
  /// a failed deletion is not itself treated as an error, since by the
  /// time this is called the batch's upload has already been confirmed
  /// successful and it has already been removed from the queue.
  Future<void> deleteBatchFiles(ImageBatch batch);

  /// Attempts to upload one batch via the remote data source, after
  /// verifying every image's local file still exists. Completes normally
  /// on success; throws an UploadFailure and leaves the batch queued on
  /// failure - callers must not delete anything or mark the batch removed
  /// just because this threw.
  Future<void> uploadBatch(ImageBatch batch);
}
