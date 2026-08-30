import 'package:camera_sync/data/remote/upload_data_source.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';

class FakeUploadDataSource implements UploadDataSource {
  bool shouldSucceed = true;
  final List<ImageBatch> uploadedBatches = [];

  @override
  Future<void> upload(ImageBatch batch) async {
    if (shouldSucceed) {
      uploadedBatches.add(batch);
    } else {
      throw Exception('Simulated upload failure');
    }
  }
}
