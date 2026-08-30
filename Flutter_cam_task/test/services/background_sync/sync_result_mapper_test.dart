import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/domain/sync/sync_result.dart';
import 'package:camera_sync/services/background_sync/sync_result_mapper.dart';

void main() {
  test('completed maps to success', () {
    expect(mapSyncResultToWorkManagerSuccess(SyncResult.completed), isTrue);
  });

  test('nothingToSync maps to success', () {
    expect(mapSyncResultToWorkManagerSuccess(SyncResult.nothingToSync), isTrue);
  });

  test('skippedOffline maps to success, not retry, to avoid hammering the device', () {
    expect(mapSyncResultToWorkManagerSuccess(SyncResult.skippedOffline), isTrue);
  });

  test('alreadyInProgress maps to success - another trigger already owns this run', () {
    expect(mapSyncResultToWorkManagerSuccess(SyncResult.alreadyInProgress), isTrue);
  });

  test('completedWithFailures maps to failure so WorkManager applies its own backoff retry', () {
    expect(mapSyncResultToWorkManagerSuccess(SyncResult.completedWithFailures), isFalse);
  });
}
