import 'dart:async';

import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';
import 'package:camera_sync/domain/repositories/upload_repository.dart';

/// A direct, reactive fake of the whole repository - used for SyncEngine
/// and UploadCubit tests so they don't depend on the real file-existence
/// check in UploadRepositoryImpl (which is tested separately, with real
/// temp files, in upload_repository_impl_test.dart).
class FakeUploadRepository implements UploadRepository {
  final Map<String, ImageBatch> _batches = {};
  final StreamController<List<ImageBatch>> _controller = StreamController.broadcast();

  final List<String> uploadedBatchIds = [];
  final List<String> deletedFilesForBatchIds = [];

  /// batchId -> error to throw from uploadBatch for that specific batch.
  final Map<String, Object> uploadErrors = {};

  bool removeBatchShouldFail = false;

  // Tracks whether uploadBatch is ever called while a previous call for
  // this fake hasn't finished yet - lets tests assert sequential (not
  // concurrent) processing.
  int _concurrentUploads = 0;
  int maxConcurrentUploads = 0;

  void seed(ImageBatch batch) {
    _batches[batch.id] = batch;
  }

  ImageBatch? batchById(String id) => _batches[id];

  void _emit() => _controller.add(_batches.values.toList());

  @override
  Future<void> addBatch(ImageBatch batch) async {
    _batches[batch.id] = batch;
    _emit();
  }

  @override
  Future<List<ImageBatch>> getPendingBatches() async => _batches.values.toList();

  @override
  Stream<List<ImageBatch>> observePendingBatches() async* {
    yield _batches.values.toList();
    yield* _controller.stream;
  }

  @override
  Future<void> updateBatchStatus(String batchId, UploadStatus status) async {
    final batch = _batches[batchId];
    if (batch != null) {
      _batches[batchId] = batch.copyWith(status: status);
      _emit();
    }
  }

  @override
  Future<void> removeBatch(String batchId) async {
    if (removeBatchShouldFail) {
      throw Exception('Simulated removeBatch failure');
    }
    _batches.remove(batchId);
    _emit();
  }

  @override
  Future<void> deleteBatchFiles(ImageBatch batch) async {
    deletedFilesForBatchIds.add(batch.id);
  }

  @override
  Future<void> uploadBatch(ImageBatch batch) async {
    _concurrentUploads++;
    if (_concurrentUploads > maxConcurrentUploads) {
      maxConcurrentUploads = _concurrentUploads;
    }
    uploadedBatchIds.add(batch.id);
    // A deterministic (not random) yield, so tests can prove uploads are
    // processed one-at-a-time rather than concurrently: if SyncEngine ever
    // fired these without awaiting each one, this delay would let a second
    // call's _concurrentUploads++ overlap with this one still being active.
    await Future<void>.delayed(Duration.zero);
    _concurrentUploads--;

    final error = uploadErrors[batch.id];
    if (error != null) throw error;
  }
}
