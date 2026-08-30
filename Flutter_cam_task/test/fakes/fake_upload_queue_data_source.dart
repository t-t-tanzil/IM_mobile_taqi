import 'dart:async';

import 'package:camera_sync/data/local/upload_queue_data_source.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';

class FakeUploadQueueDataSource implements UploadQueueDataSource {
  final Map<String, ImageBatch> _batches = {};
  final StreamController<List<ImageBatch>> _controller = StreamController.broadcast();

  /// If set, thrown by [saveBatch] instead of succeeding.
  Object? saveError;

  void _emit() => _controller.add(_batches.values.toList());

  @override
  Future<void> saveBatch(ImageBatch batch) async {
    final error = saveError;
    if (error != null) throw error;
    _batches[batch.id] = batch;
    _emit();
  }

  @override
  Future<void> updateBatch(ImageBatch batch) async {
    _batches[batch.id] = batch;
    _emit();
  }

  @override
  Future<void> removeBatch(String batchId) async {
    _batches.remove(batchId);
    _emit();
  }

  @override
  Stream<List<ImageBatch>> observeBatches() async* {
    // Matches the real data source's contract: always emit the current
    // snapshot first, then forward live updates.
    yield _batches.values.toList();
    yield* _controller.stream;
  }
}
