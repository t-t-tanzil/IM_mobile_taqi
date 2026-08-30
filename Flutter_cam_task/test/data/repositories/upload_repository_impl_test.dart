import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/core/errors/upload_failure.dart';
import 'package:camera_sync/data/repositories/upload_repository_impl.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';

import '../../fakes/fake_upload_data_source.dart';
import '../../fakes/fake_upload_queue_data_source.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('upload_repository_impl_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('uploadBatch delegates to the data source when the local file exists', () async {
    final file = File('${tempDir.path}/1.jpg')..writeAsStringSync('fake image bytes');
    final batch = ImageBatch(
      id: 'batch-1',
      images: [
        CapturedImage(id: 'img-1', localFilePath: file.path, capturedAt: DateTime(2024, 1, 1)),
      ],
      createdAt: DateTime(2024, 1, 1),
      status: UploadStatus.pending,
    );
    final uploadDataSource = FakeUploadDataSource();
    final repository = UploadRepositoryImpl(FakeUploadQueueDataSource(), uploadDataSource);

    await repository.uploadBatch(batch);

    expect(uploadDataSource.uploadedBatches, [batch]);
  });

  test('uploadBatch throws MissingLocalFileFailure when a file is missing, without calling the data source', () async {
    final batch = ImageBatch(
      id: 'batch-1',
      images: [
        CapturedImage(
          id: 'img-1',
          localFilePath: '${tempDir.path}/does-not-exist.jpg',
          capturedAt: DateTime(2024, 1, 1),
        ),
      ],
      createdAt: DateTime(2024, 1, 1),
      status: UploadStatus.pending,
    );
    final uploadDataSource = FakeUploadDataSource();
    final repository = UploadRepositoryImpl(FakeUploadQueueDataSource(), uploadDataSource);

    await expectLater(
      repository.uploadBatch(batch),
      throwsA(isA<MissingLocalFileFailure>()),
    );
    expect(uploadDataSource.uploadedBatches, isEmpty);
  });

  test('deleteBatchFiles removes existing files and does not throw for already-missing ones', () async {
    final existing = File('${tempDir.path}/exists.jpg')..writeAsStringSync('data');
    final batch = ImageBatch(
      id: 'batch-1',
      images: [
        CapturedImage(id: 'img-1', localFilePath: existing.path, capturedAt: DateTime(2024, 1, 1)),
        CapturedImage(
          id: 'img-2',
          localFilePath: '${tempDir.path}/already-gone.jpg',
          capturedAt: DateTime(2024, 1, 1),
        ),
      ],
      createdAt: DateTime(2024, 1, 1),
      status: UploadStatus.pending,
    );
    final repository = UploadRepositoryImpl(FakeUploadQueueDataSource(), FakeUploadDataSource());

    await repository.deleteBatchFiles(batch);

    expect(existing.existsSync(), isFalse);
  });
}
