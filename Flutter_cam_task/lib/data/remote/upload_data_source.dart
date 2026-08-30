import '../../domain/entities/image_batch.dart';

/// Structured as though a real HTTP implementation could replace
/// MockUploadDataSource later without touching anything above this layer.
abstract interface class UploadDataSource {
  Future<void> upload(ImageBatch batch);
}
