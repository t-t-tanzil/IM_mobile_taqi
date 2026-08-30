import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:camera_sync/core/constants/app_constants.dart';
import 'package:camera_sync/data/local/image_batch_json_mapper.dart';
import 'package:camera_sync/data/local/shared_preferences_upload_queue_data_source.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';

ImageBatch _batch(String id, {UploadStatus status = UploadStatus.pending, int imageCount = 1}) {
  return ImageBatch(
    id: id,
    images: List.generate(
      imageCount,
      (i) => CapturedImage(
        id: '$id-img-$i',
        localFilePath: '/tmp/$id-$i.jpg',
        capturedAt: DateTime(2024, 1, 1),
      ),
    ),
    createdAt: DateTime(2024, 1, 1),
    status: status,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('save then load returns the same batch', () async {
    final dataSource = SharedPreferencesUploadQueueDataSource();
    final batch = _batch('batch-1');

    await dataSource.saveBatch(batch);
    final batches = await dataSource.observeBatches().first;

    expect(batches, [batch]);
  });

  test('a fresh data source instance reloads a batch persisted by a previous instance', () async {
    final first = SharedPreferencesUploadQueueDataSource();
    await first.saveBatch(_batch('batch-1'));

    // A new instance simulates an app restart - nothing is shared in memory.
    final second = SharedPreferencesUploadQueueDataSource();
    final batches = await second.observeBatches().first;

    expect(batches, hasLength(1));
    expect(batches.single.id, 'batch-1');
  });

  test('observeBatches reflects each new batch added to the queue', () async {
    final dataSource = SharedPreferencesUploadQueueDataSource();

    await dataSource.saveBatch(_batch('batch-1'));
    expect((await dataSource.observeBatches().first).length, 1);

    await dataSource.saveBatch(_batch('batch-2'));
    expect((await dataSource.observeBatches().first).length, 2);
  });

  test('multiple batches persist independently', () async {
    final dataSource = SharedPreferencesUploadQueueDataSource();

    await dataSource.saveBatch(_batch('batch-1', imageCount: 2));
    await dataSource.saveBatch(_batch('batch-2', imageCount: 3));

    final batches = await dataSource.observeBatches().first;
    expect(batches.map((b) => b.id), containsAll(['batch-1', 'batch-2']));
  });

  test('a failed batch remains persisted across a simulated restart', () async {
    final dataSource = SharedPreferencesUploadQueueDataSource();
    await dataSource.saveBatch(_batch('batch-1', status: UploadStatus.failed));

    final reloaded = SharedPreferencesUploadQueueDataSource();
    final batches = await reloaded.observeBatches().first;

    expect(batches.single.status, UploadStatus.failed);
  });

  test('status updates persist', () async {
    final dataSource = SharedPreferencesUploadQueueDataSource();
    final batch = _batch('batch-1');
    await dataSource.saveBatch(batch);

    await dataSource.updateBatch(batch.copyWith(status: UploadStatus.failed));

    final reloaded = SharedPreferencesUploadQueueDataSource();
    final batches = await reloaded.observeBatches().first;
    expect(batches.single.status, UploadStatus.failed);
  });

  test('batch removal works and does not affect other batches', () async {
    final dataSource = SharedPreferencesUploadQueueDataSource();
    await dataSource.saveBatch(_batch('batch-1'));
    await dataSource.saveBatch(_batch('batch-2'));

    await dataSource.removeBatch('batch-1');

    final batches = await dataSource.observeBatches().first;
    expect(batches.map((b) => b.id), ['batch-2']);
  });

  test('a batch stuck in uploading is recovered to pending on the next startup', () async {
    final first = SharedPreferencesUploadQueueDataSource();
    await first.saveBatch(_batch('batch-1', status: UploadStatus.uploading));

    // Simulates the app being killed mid-upload and restarted.
    final second = SharedPreferencesUploadQueueDataSource();
    final batches = await second.observeBatches().first;

    expect(batches.single.status, UploadStatus.pending);
  });

  test('a corrupted queue payload does not crash - it starts from an empty queue', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.uploadQueueStorageKey: 'not valid json{{{',
    });
    final dataSource = SharedPreferencesUploadQueueDataSource();

    final batches = await dataSource.observeBatches().first;

    expect(batches, isEmpty);
  });

  test('one malformed record is skipped without losing the rest of the queue', () async {
    final validBatch = _batch('batch-1');
    final payload = jsonEncode([
      imageBatchToJson(validBatch),
      {'id': 'broken'}, // missing required fields
    ]);
    SharedPreferences.setMockInitialValues({AppConstants.uploadQueueStorageKey: payload});
    final dataSource = SharedPreferencesUploadQueueDataSource();

    final batches = await dataSource.observeBatches().first;

    expect(batches, [validBatch]);
  });
}
