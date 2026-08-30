import 'dart:io';

import '../../core/errors/upload_failure.dart';
import '../../domain/entities/image_batch.dart';
import '../../domain/entities/upload_status.dart';
import '../../domain/repositories/upload_repository.dart';
import '../local/upload_queue_data_source.dart';
import '../remote/upload_data_source.dart';

/// Combines the local queue with the remote (mock) upload. Contains exactly
/// one piece of business-adjacent logic - verifying local files exist
/// before attempting an upload - everything else is a direct data-source
/// call. The actual synchronization algorithm (what to upload, when, and
/// how failures are handled) lives in SyncEngine, not here.
class UploadRepositoryImpl implements UploadRepository {
  const UploadRepositoryImpl(this._queueDataSource, this._uploadDataSource);

  final UploadQueueDataSource _queueDataSource;
  final UploadDataSource _uploadDataSource;

  @override
  Future<void> addBatch(ImageBatch batch) => _queueDataSource.saveBatch(batch);

  @override
  Future<List<ImageBatch>> getPendingBatches() => observePendingBatches().first;

  @override
  Stream<List<ImageBatch>> observePendingBatches() => _queueDataSource.observeBatches();

  @override
  Future<void> updateBatchStatus(String batchId, UploadStatus status) async {
    final batch = await _findBatch(batchId);
    if (batch == null) return;
    await _queueDataSource.updateBatch(batch.copyWith(status: status));
  }

  @override
  Future<void> removeBatch(String batchId) => _queueDataSource.removeBatch(batchId);

  @override
  Future<void> uploadBatch(ImageBatch batch) async {
    for (final image in batch.images) {
      if (!File(image.localFilePath).existsSync()) {
        throw MissingLocalFileFailure('Missing local file: ${image.localFilePath}');
      }
    }
    await _uploadDataSource.upload(batch);
  }

  @override
  Future<void> deleteBatchFiles(ImageBatch batch) async {
    for (final image in batch.images) {
      try {
        final file = File(image.localFilePath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // Best-effort only - see the doc comment on the interface method.
      }
    }
  }

  Future<ImageBatch?> _findBatch(String batchId) async {
    final batches = await getPendingBatches();
    for (final batch in batches) {
      if (batch.id == batchId) return batch;
    }
    return null;
  }
}
