import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/data/repositories/camera_repository_impl.dart';
import 'package:camera_sync/data/repositories/upload_repository_impl.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/sync/sync_engine.dart';
import 'package:camera_sync/domain/usecases/capture_image.dart';
import 'package:camera_sync/domain/usecases/create_batch.dart';
import 'package:camera_sync/domain/usecases/get_pending_uploads.dart';
import 'package:camera_sync/domain/usecases/sync_pending_uploads.dart';
import 'package:camera_sync/presentation/camera/camera_cubit.dart';
import 'package:camera_sync/presentation/uploads/upload_cubit.dart';
import 'package:camera_sync/presentation/uploads/upload_state.dart';
import 'package:camera_sync/services/connectivity/connectivity_service.dart';

import '../fakes/fake_background_sync_service.dart';
import '../fakes/fake_camera_data_source.dart';
import '../fakes/fake_connectivity_service.dart';
import '../fakes/fake_upload_data_source.dart';
import '../fakes/fake_upload_queue_data_source.dart';

/// UploadCubit's batches field is driven by its subscription to the
/// persisted queue stream, not set directly - waits for that reactive
/// round-trip instead of guessing at a fixed delay.
Future<void> _waitUntil(UploadCubit cubit, bool Function(UploadState) predicate) async {
  if (predicate(cubit.state)) return;
  await cubit.stream.firstWhere(predicate).timeout(const Duration(seconds: 2));
}

// Replicates the exact orchestration CameraPreviewScreen performs when the
// user taps "Add to Pending Uploads": persist first, only clear the
// in-memory batch if persistence actually succeeded.
Future<void> _addCurrentBatchToQueue(CameraCubit cameraCubit, UploadCubit uploadCubit) async {
  final success = await uploadCubit.addBatchToQueue(cameraCubit.state.batchImages);
  if (success) {
    cameraCubit.clearCurrentBatch();
  }
}

void main() {
  late FakeCameraDataSource cameraDataSource;
  late CameraCubit cameraCubit;
  late FakeUploadQueueDataSource queueDataSource;
  late UploadCubit uploadCubit;

  setUp(() async {
    cameraDataSource = FakeCameraDataSource();
    final cameraRepository = CameraRepositoryImpl(cameraDataSource);
    cameraCubit = CameraCubit(cameraRepository, CaptureImage(cameraRepository));

    queueDataSource = FakeUploadQueueDataSource();
    final uploadRepository = UploadRepositoryImpl(queueDataSource, FakeUploadDataSource());
    // Offline: these tests are about camera -> queue persistence, not sync
    // behavior (covered in upload_cubit_test.dart/sync_engine_test.dart) -
    // this keeps UploadCubit's new startup/connectivity-triggered auto-sync
    // from attempting an upload against these batches' fake file paths.
    final connectivityService = FakeConnectivityService()..status = ConnectivityStatus.offline;
    final syncEngine = SyncEngine(uploadRepository, connectivityService);
    uploadCubit = UploadCubit(
      GetPendingUploads(uploadRepository),
      CreateBatch(uploadRepository),
      uploadRepository,
      SyncPendingUploads(syncEngine),
      connectivityService,
      FakeBackgroundSyncService(),
    );
    // Let UploadCubit's constructor-time subscriptions actually start
    // listening before any test mutates the queue.
    await Future<void>.delayed(Duration.zero);

    await cameraCubit.initializeCamera();
    for (var i = 0; i < 3; i++) {
      cameraDataSource.imageToReturn = CapturedImage(
        id: 'img-$i',
        localFilePath: '/tmp/$i.jpg',
        capturedAt: DateTime(2024, 1, 1),
      );
      await cameraCubit.captureImage();
    }
  });

  tearDown(() async {
    await cameraCubit.close();
    await uploadCubit.close();
  });

  test('finalizing the current batch persists it to the pending queue', () async {
    expect(cameraCubit.state.batchImages, hasLength(3));

    await _addCurrentBatchToQueue(cameraCubit, uploadCubit);
    await _waitUntil(uploadCubit, (s) => s.batches.isNotEmpty);

    expect(uploadCubit.state.batches, hasLength(1));
    expect(uploadCubit.state.batches.single.images, hasLength(3));
  });

  test('current batch clears after successful persistence', () async {
    await _addCurrentBatchToQueue(cameraCubit, uploadCubit);
    await _waitUntil(uploadCubit, (s) => s.batches.isNotEmpty);

    expect(cameraCubit.state.batchImages, isEmpty);
  });

  test('failed persistence does NOT clear the current batch', () async {
    queueDataSource.saveError = Exception('disk full');

    await _addCurrentBatchToQueue(cameraCubit, uploadCubit);

    expect(cameraCubit.state.batchImages, hasLength(3));
    expect(uploadCubit.state.batches, isEmpty);
  });
}
