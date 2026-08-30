import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/data/repositories/upload_repository_impl.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';
import 'package:camera_sync/domain/usecases/create_batch.dart';
import 'package:camera_sync/domain/usecases/get_pending_uploads.dart';

import '../../fakes/fake_upload_data_source.dart';
import '../../fakes/fake_upload_queue_data_source.dart';

void main() {
  test('CreateBatch persists a batch that GetPendingUploads then observes', () async {
    final queueDataSource = FakeUploadQueueDataSource();
    final repository = UploadRepositoryImpl(queueDataSource, FakeUploadDataSource());
    final createBatch = CreateBatch(repository);
    final getPendingUploads = GetPendingUploads(repository);

    final batch = ImageBatch(
      id: 'batch-1',
      images: [
        CapturedImage(id: 'img-1', localFilePath: '/tmp/1.jpg', capturedAt: DateTime(2024, 1, 1)),
      ],
      createdAt: DateTime(2024, 1, 1),
      status: UploadStatus.pending,
    );

    final future = getPendingUploads().first;
    await createBatch(batch);

    final batches = await future;
    expect(batches, [batch]);
  });
}
