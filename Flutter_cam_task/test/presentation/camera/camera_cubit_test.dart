import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/core/errors/camera_failure.dart';
import 'package:camera_sync/data/repositories/camera_repository_impl.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/normalized_focus_point.dart';
import 'package:camera_sync/domain/usecases/capture_image.dart';
import 'package:camera_sync/presentation/camera/camera_cubit.dart';
import 'package:camera_sync/presentation/camera/camera_state.dart';

import '../../fakes/fake_camera_data_source.dart';

void main() {
  late FakeCameraDataSource dataSource;
  late CameraCubit cubit;

  setUp(() {
    dataSource = FakeCameraDataSource();
    final repository = CameraRepositoryImpl(dataSource);
    cubit = CameraCubit(repository, CaptureImage(repository));
  });

  tearDown(() {
    cubit.close();
  });

  test('initial state is initializing with no batch images', () {
    expect(cubit.state.status, CameraStatus.initializing);
    expect(cubit.state.batchImages, isEmpty);
  });

  test('successful initialization moves to ready with the zoom range applied', () async {
    dataSource.zoomRange = (min: 1.0, max: 8.0);

    await cubit.initializeCamera();

    expect(cubit.state.status, CameraStatus.ready);
    expect(cubit.state.minZoom, 1.0);
    expect(cubit.state.maxZoom, 8.0);
    expect(cubit.state.zoomLevel, 1.0);
    expect(cubit.state.availableZoomLevels, [1.0, 2.0, 3.0, 5.0]);
  });

  test('permission failure during initialization produces the permission-denied status', () async {
    dataSource.initializeError = const CameraPermissionDenied();

    await cubit.initializeCamera();

    expect(cubit.state.status, CameraStatus.permissionDenied);
    expect(cubit.state.errorMessage, isNotNull);
  });

  test('unavailable camera failure produces the unavailable status', () async {
    dataSource.initializeError = const CameraUnavailable();

    await cubit.initializeCamera();

    expect(cubit.state.status, CameraStatus.unavailable);
  });

  test('an unexpected initialization failure produces the error status', () async {
    dataSource.initializeError = Exception('boom');

    await cubit.initializeCamera();

    expect(cubit.state.status, CameraStatus.error);
  });

  test('setZoomLevel clamps to the camera-reported range', () async {
    dataSource.zoomRange = (min: 1.0, max: 4.0);
    await cubit.initializeCamera();

    cubit.setZoomLevel(10.0);
    expect(cubit.state.zoomLevel, 4.0);

    cubit.setZoomLevel(0.1);
    expect(cubit.state.zoomLevel, 1.0);
  });

  test('setZoomLevel is ignored before the camera is ready', () {
    cubit.setZoomLevel(2.0);

    expect(cubit.state.zoomLevel, 1.0);
  });

  test('pinch, slider, and buttons all update the same zoomLevel field', () async {
    dataSource.zoomRange = (min: 1.0, max: 5.0);
    await cubit.initializeCamera();

    cubit.setZoomLevel(2.0); // simulates a zoom button tap
    expect(cubit.state.zoomLevel, 2.0);

    cubit.setZoomLevel(3.5); // simulates a slider drag
    expect(cubit.state.zoomLevel, 3.5);

    cubit.setZoomLevel(1.0 * 1.8); // simulates a pinch gesture's base * scale
    expect(cubit.state.zoomLevel, closeTo(1.8, 0.0001));
  });

  test('zoom buttons are built from the reported min/max capabilities', () async {
    dataSource.zoomRange = (min: 1.0, max: 4.0);

    await cubit.initializeCamera();

    expect(cubit.state.availableZoomLevels, [1.0, 2.0, 3.0]);
    expect(cubit.state.availableZoomLevels, isNot(contains(0.5)));
  });

  test('focus indicator appears at the tapped position and clears after the timeout', () {
    fakeAsync((async) {
      cubit.initializeCamera();
      async.flushMicrotasks();

      const tapPosition = Offset(120, 340);
      cubit.setFocusPoint(const NormalizedFocusPoint(x: 0.3, y: 0.6), tapPosition);

      expect(cubit.state.focusIndicatorPosition, tapPosition);

      async.elapse(const Duration(milliseconds: 1600));

      expect(cubit.state.focusIndicatorPosition, isNull);
    });
  });

  test('capture success appends the image to the current batch', () async {
    await cubit.initializeCamera();
    dataSource.imageToReturn = CapturedImage(
      id: '1',
      localFilePath: '/tmp/1.jpg',
      capturedAt: DateTime(2024, 1, 1),
    );

    await cubit.captureImage();

    expect(cubit.state.batchImages, hasLength(1));
    expect(cubit.state.batchImages.first.id, '1');
    expect(cubit.state.isCapturing, isFalse);
  });

  test('capture failure produces a capture error without touching the batch', () async {
    await cubit.initializeCamera();
    dataSource.captureError = const CaptureStorageFailure();

    await cubit.captureImage();

    expect(cubit.state.batchImages, isEmpty);
    expect(cubit.state.captureErrorMessage, isNotNull);
    expect(cubit.state.isCapturing, isFalse);
  });

  test('switchCamera flips isFrontCamera and re-applies the new zoom range', () async {
    dataSource.zoomRange = (min: 1.0, max: 4.0);
    await cubit.initializeCamera();
    expect(cubit.state.isFrontCamera, isFalse);

    dataSource.zoomRange = (min: 1.0, max: 1.0); // front cameras often can't zoom
    await cubit.switchCamera();

    expect(dataSource.switchCameraCallCount, 1);
    expect(cubit.state.isFrontCamera, isTrue);
    expect(cubit.state.minZoom, 1.0);
    expect(cubit.state.maxZoom, 1.0);
    expect(cubit.state.zoomLevel, 1.0);
  });

  test('switchCamera back to the rear camera flips isFrontCamera again', () async {
    await cubit.initializeCamera();
    await cubit.switchCamera();
    expect(cubit.state.isFrontCamera, isTrue);

    await cubit.switchCamera();

    expect(dataSource.switchCameraCallCount, 2);
    expect(cubit.state.isFrontCamera, isFalse);
  });

  test('switchCamera preserves the current in-memory batch', () async {
    await cubit.initializeCamera();
    dataSource.imageToReturn = CapturedImage(
      id: '1',
      localFilePath: '/tmp/1.jpg',
      capturedAt: DateTime(2024, 1, 1),
    );
    await cubit.captureImage();
    expect(cubit.state.batchImages, hasLength(1));

    await cubit.switchCamera();

    expect(cubit.state.batchImages, hasLength(1));
  });

  test('switchCamera is ignored before the camera is ready', () async {
    await cubit.switchCamera();

    expect(dataSource.switchCameraCallCount, 0);
  });

  test('a failed switchCamera surfaces an error without crashing', () async {
    await cubit.initializeCamera();
    dataSource.switchCameraError = Exception('no second camera');

    await cubit.switchCamera();

    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.status, CameraStatus.ready);
  });
}
