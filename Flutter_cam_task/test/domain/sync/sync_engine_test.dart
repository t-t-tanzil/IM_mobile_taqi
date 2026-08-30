import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';
import 'package:camera_sync/domain/sync/sync_engine.dart';
import 'package:camera_sync/domain/sync/sync_result.dart';
import 'package:camera_sync/services/connectivity/connectivity_service.dart';

import '../../fakes/fake_connectivity_service.dart';
import '../../fakes/fake_upload_repository.dart';

ImageBatch _batch(String id, {UploadStatus status = UploadStatus.pending}) => ImageBatch(
      id: id,
      images: [
        CapturedImage(id: '$id-img', localFilePath: '/tmp/$id.jpg', capturedAt: DateTime(2024, 1, 1)),
      ],
      createdAt: DateTime(2024, 1, 1),
      status: status,
    );

void main() {
  late FakeUploadRepository repository;
  late FakeConnectivityService connectivity;
  late SyncEngine syncEngine;

  setUp(() {
    repository = FakeUploadRepository();
    connectivity = FakeConnectivityService()..status = ConnectivityStatus.online;
    syncEngine = SyncEngine(repository, connectivity);
  });

  test('no-op when the queue is empty', () async {
    final result = await syncEngine.sync();

    expect(result, SyncResult.nothingToSync);
    expect(repository.uploadedBatchIds, isEmpty);
  });

  test('skips when offline and does not attempt any upload', () async {
    connectivity.status = ConnectivityStatus.offline;
    repository.seed(_batch('b1'));

    final result = await syncEngine.sync();

    expect(result, SyncResult.skippedOffline);
    expect(repository.uploadedBatchIds, isEmpty);
    // The batch must not be touched just because we were offline.
    expect(repository.batchById('b1')!.status, UploadStatus.pending);
  });

  test('a pending batch uploads successfully', () async {
    repository.seed(_batch('b1'));

    final result = await syncEngine.sync();

    expect(result, SyncResult.completed);
    expect(repository.uploadedBatchIds, ['b1']);
  });

  test('a successful batch is removed from the queue', () async {
    repository.seed(_batch('b1'));

    await syncEngine.sync();

    expect(repository.batchById('b1'), isNull);
  });

  test('a failed upload remains queued', () async {
    repository.seed(_batch('b1'));
    repository.uploadErrors['b1'] = Exception('network error');

    await syncEngine.sync();

    expect(repository.batchById('b1'), isNotNull);
  });

  test('a failed upload status becomes Failed', () async {
    repository.seed(_batch('b1'));
    repository.uploadErrors['b1'] = Exception('network error');

    final result = await syncEngine.sync();

    expect(result, SyncResult.completedWithFailures);
    expect(repository.batchById('b1')!.status, UploadStatus.failed);
  });

  test('multiple batches process sequentially, not concurrently', () async {
    repository.seed(_batch('b1'));
    repository.seed(_batch('b2'));
    repository.seed(_batch('b3'));

    final result = await syncEngine.sync();

    expect(result, SyncResult.completed);
    expect(repository.uploadedBatchIds, ['b1', 'b2', 'b3']);
    expect(repository.maxConcurrentUploads, 1);
  });

  test('a missing local image produces a failure without crashing the sync', () async {
    repository.seed(_batch('b1'));
    repository.uploadErrors['b1'] = Exception('MissingLocalFileFailure-equivalent');

    final result = await syncEngine.sync();

    expect(result, SyncResult.completedWithFailures);
    expect(repository.batchById('b1')!.status, UploadStatus.failed);
  });

  test('an unexpected exception does not delete the batch', () async {
    repository.seed(_batch('b1'));
    repository.uploadErrors['b1'] = StateError('something totally unexpected');

    await syncEngine.sync();

    expect(repository.batchById('b1'), isNotNull);
    expect(repository.batchById('b1')!.status, UploadStatus.failed);
  });

  test('sync cannot run concurrently - a call while one is in flight is a no-op', () async {
    repository.seed(_batch('b1'));

    final first = syncEngine.sync();
    final second = syncEngine.sync();

    final results = await Future.wait([first, second]);

    expect(results, contains(SyncResult.alreadyInProgress));
    expect(results.where((r) => r != SyncResult.alreadyInProgress), hasLength(1));
  });

  test('repeated sync triggers do not duplicate uploads', () async {
    repository.seed(_batch('b1'));

    await Future.wait([syncEngine.sync(), syncEngine.sync(), syncEngine.sync()]);

    expect(repository.uploadedBatchIds, ['b1']);
  });

  test('only Pending and Failed batches are processed - Uploading is left alone', () async {
    repository.seed(_batch('pending-one', status: UploadStatus.pending));
    repository.seed(_batch('failed-one', status: UploadStatus.failed));
    repository.seed(_batch('uploading-one', status: UploadStatus.uploading));

    await syncEngine.sync();

    expect(repository.uploadedBatchIds, containsAll(['pending-one', 'failed-one']));
    expect(repository.uploadedBatchIds, isNot(contains('uploading-one')));
    // Untouched, not silently removed or reclassified.
    expect(repository.batchById('uploading-one')!.status, UploadStatus.uploading);
  });

  test('a batch is removed and its files are deleted only after a confirmed successful upload', () async {
    repository.seed(_batch('b1'));

    await syncEngine.sync();

    expect(repository.batchById('b1'), isNull);
    expect(repository.deletedFilesForBatchIds, ['b1']);
  });

  test('files are not deleted for a batch that failed to upload', () async {
    repository.seed(_batch('b1'));
    repository.uploadErrors['b1'] = Exception('boom');

    await syncEngine.sync();

    expect(repository.deletedFilesForBatchIds, isEmpty);
  });
}
