import '../../domain/entities/image_batch.dart';

abstract interface class UploadQueueDataSource {
  Future<void> saveBatch(ImageBatch batch);

  Future<void> updateBatch(ImageBatch batch);

  Future<void> removeBatch(String batchId);

  /// Reconstructed from persisted storage - must survive app restart.
  Stream<List<ImageBatch>> observeBatches();
}
