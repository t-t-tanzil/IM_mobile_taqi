import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';
import 'package:camera_sync/domain/sync/sync_engine.dart';
import 'package:camera_sync/domain/sync/sync_result.dart';
import 'package:camera_sync/domain/usecases/create_batch.dart';
import 'package:camera_sync/domain/usecases/get_pending_uploads.dart';
import 'package:camera_sync/domain/usecases/sync_pending_uploads.dart';
import 'package:camera_sync/presentation/uploads/upload_cubit.dart';
import 'package:camera_sync/presentation/uploads/upload_state.dart';
import 'package:camera_sync/services/connectivity/connectivity_service.dart';

import '../../fakes/fake_background_sync_service.dart';
import '../../fakes/fake_connectivity_service.dart';
import '../../fakes/fake_upload_repository.dart';

/// UploadCubit's batches/isSyncing fields are driven by subscriptions, not
/// set directly - waits for the reactive round-trip instead of guessing at
/// a fixed delay.
Future<void> _waitUntil(UploadCubit cubit, bool Function(UploadState) predicate) async {
  if (predicate(cubit.state)) return;
  await cubit.stream.firstWhere(predicate).timeout(const Duration(seconds: 2));
}

List<CapturedImage> _images([int count = 1]) => List.generate(
      count,
      (i) => CapturedImage(id: '$i', localFilePath: '/tmp/$i.jpg', capturedAt: DateTime(2024, 1, 1)),
    );

void main() {
  late FakeUploadRepository repository;
  late FakeConnectivityService connectivity;
  // The SAME SyncEngine instance the cubit uses internally (via
  // SyncPendingUploads) - kept accessible here so tests can simulate other
  // trigger sources (e.g. "the future background worker") sharing the
  // exact same concurrency lock, the way they would in the real app where
  // SyncEngine is a DI singleton.
  late SyncEngine syncEngine;
  late FakeBackgroundSyncService backgroundSync;
  late UploadCubit cubit;

  setUp(() async {
    repository = FakeUploadRepository();
    connectivity = FakeConnectivityService()..status = ConnectivityStatus.online;
    syncEngine = SyncEngine(repository, connectivity);
    backgroundSync = FakeBackgroundSyncService();
    cubit = UploadCubit(
      GetPendingUploads(repository),
      CreateBatch(repository),
      repository,
      SyncPendingUploads(syncEngine),
      connectivity,
      backgroundSync,
    );
    // Let the constructor-time subscriptions (queue + connectivity) and the
    // startup sync actually start before any test mutates things.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => cubit.close());

  test('starts with an empty queue', () {
    expect(cubit.state.batches, isEmpty);
  });

  test('addBatchToQueue persists a batch and it appears in state', () async {
    final success = await cubit.addBatchToQueue(_images(3));
    await _waitUntil(cubit, (s) => s.batches.isNotEmpty);

    expect(success, isTrue);
    expect(cubit.state.batches, hasLength(1));
    expect(cubit.state.batches.single.images, hasLength(3));
  });

  test('addBatchToQueue does nothing for an empty image list', () async {
    final success = await cubit.addBatchToQueue(const []);

    expect(success, isFalse);
    expect(cubit.state.batches, isEmpty);
  });

  test('removeBatch removes it from state', () async {
    await cubit.addBatchToQueue(_images());
    await _waitUntil(cubit, (s) => s.batches.isNotEmpty);
    final batchId = cubit.state.batches.single.id;

    await cubit.removeBatch(batchId);
    await _waitUntil(cubit, (s) => s.batches.isEmpty);

    expect(cubit.state.batches, isEmpty);
  });

  test('retry() calls through to SyncEngine and a pending batch gets uploaded', () async {
    await cubit.addBatchToQueue(_images());
    await _waitUntil(cubit, (s) => s.batches.isNotEmpty);

    await cubit.retry();
    await _waitUntil(cubit, (s) => s.batches.isEmpty);

    expect(repository.uploadedBatchIds, hasLength(1));
    expect(cubit.state.batches, isEmpty);
  });

  test('sync state (isSyncing/lastSyncResult) is exposed correctly', () async {
    await cubit.addBatchToQueue(_images());
    await _waitUntil(cubit, (s) => s.batches.isNotEmpty);

    final syncFuture = cubit.retry();
    // isSyncing flips true synchronously as part of _runSync's first emit.
    expect(cubit.state.isSyncing, isTrue);

    await syncFuture;

    expect(cubit.state.isSyncing, isFalse);
    expect(cubit.state.lastSyncResult, SyncResult.completed);
  });

  test('a failed batch surfaces completedWithFailures and stays in the queue', () async {
    await cubit.addBatchToQueue(_images());
    await _waitUntil(cubit, (s) => s.batches.isNotEmpty);
    repository.uploadErrors[cubit.state.batches.single.id] = Exception('boom');

    await cubit.retry();
    await _waitUntil(cubit, (s) => s.lastSyncResult == SyncResult.completedWithFailures);

    expect(cubit.state.batches, hasLength(1));
    expect(cubit.state.batches.single.status, UploadStatus.failed);
  });

  test('connectivity going offline then online automatically triggers a sync', () async {
    connectivity.status = ConnectivityStatus.offline;
    connectivity.emit(ConnectivityStatus.offline);
    await cubit.addBatchToQueue(_images());
    await _waitUntil(cubit, (s) => s.batches.isNotEmpty);
    expect(repository.uploadedBatchIds, isEmpty);

    connectivity.status = ConnectivityStatus.online;
    connectivity.emit(ConnectivityStatus.online);
    await _waitUntil(cubit, (s) => s.batches.isEmpty);

    expect(repository.uploadedBatchIds, hasLength(1));
  });

  test(
    'retry + connectivity restoration + a third trigger sharing the same SyncEngine '
    'at the same time still result in exactly ONE sync execution, not three',
    () async {
      await cubit.addBatchToQueue(_images());
      await _waitUntil(cubit, (s) => s.batches.isNotEmpty);

      // Simulate: user taps Retry, connectivity flips online, and a
      // hypothetical third trigger (the future background worker) all
      // fire at approximately the same moment, all funnelling through the
      // exact same SyncEngine instance.
      final retryFuture = cubit.retry();
      connectivity.emit(ConnectivityStatus.online);
      final directSyncFuture = syncEngine.sync();

      await retryFuture;
      await directSyncFuture;
      await _waitUntil(cubit, (s) => s.batches.isEmpty);

      // Exactly one batch, uploaded exactly once - not three concurrent
      // upload attempts for the same batch.
      expect(repository.uploadedBatchIds, hasLength(1));
    },
  );

  group('background sync scheduling', () {
    test('app startup schedules the periodic safety net', () {
      // The constructor itself is the startup trigger - already exercised
      // by setUp(), so just assert on what it already did.
      expect(backgroundSync.scheduleCallCount, greaterThanOrEqualTo(1));
    });

    test('adding a batch schedules the periodic safety net', () async {
      final before = backgroundSync.scheduleCallCount;

      await cubit.addBatchToQueue(_images());
      await _waitUntil(cubit, (s) => s.batches.isNotEmpty);

      expect(backgroundSync.scheduleCallCount, greaterThan(before));
    });

    test('connectivity restoration schedules the periodic safety net', () async {
      connectivity.status = ConnectivityStatus.offline;
      connectivity.emit(ConnectivityStatus.offline);
      await Future<void>.delayed(Duration.zero);
      final before = backgroundSync.scheduleCallCount;

      connectivity.status = ConnectivityStatus.online;
      connectivity.emit(ConnectivityStatus.online);
      await Future<void>.delayed(Duration.zero);

      expect(backgroundSync.scheduleCallCount, greaterThan(before));
    });

    test('a sync that completes with failures schedules the periodic safety net', () async {
      await cubit.addBatchToQueue(_images());
      await _waitUntil(cubit, (s) => s.batches.isNotEmpty);
      repository.uploadErrors[cubit.state.batches.single.id] = Exception('boom');
      final before = backgroundSync.scheduleCallCount;

      await cubit.retry();
      await _waitUntil(cubit, (s) => s.lastSyncResult == SyncResult.completedWithFailures);

      expect(backgroundSync.scheduleCallCount, greaterThan(before));
    });

    test('a fully successful sync does not need the extra failure-triggered schedule call', () async {
      await cubit.addBatchToQueue(_images());
      await _waitUntil(cubit, (s) => s.batches.isNotEmpty);
      final beforeRetry = backgroundSync.scheduleCallCount;

      await cubit.retry();
      await _waitUntil(cubit, (s) => s.batches.isEmpty);

      // retry() itself never schedules (only its 4 named triggers do), so a
      // clean success adds nothing beyond whatever the earlier triggers
      // already scheduled.
      expect(backgroundSync.scheduleCallCount, beforeRetry);
    });
  });
}
