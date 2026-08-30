import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/core/errors/upload_failure.dart';
import 'package:camera_sync/data/remote/mock_upload_data_source.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';

ImageBatch _batch() => ImageBatch(
      id: 'batch-1',
      images: [
        CapturedImage(id: 'img-1', localFilePath: '/tmp/1.jpg', capturedAt: DateTime(2024, 1, 1)),
      ],
      createdAt: DateTime(2024, 1, 1),
      status: UploadStatus.pending,
    );

void main() {
  test('deterministic success completes normally', () async {
    final dataSource = MockUploadDataSource(shouldSucceed: true, simulatedLatency: Duration.zero);

    await expectLater(dataSource.upload(_batch()), completes);
  });

  test('deterministic failure throws RemoteUploadFailure', () async {
    final dataSource = MockUploadDataSource(shouldSucceed: false, simulatedLatency: Duration.zero);

    await expectLater(
      dataSource.upload(_batch()),
      throwsA(isA<RemoteUploadFailure>()),
    );
  });
}
