import 'package:camera/camera.dart';
import 'package:camera_sync/data/camera/camera_data_source.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/normalized_focus_point.dart';

class FakeCameraDataSource implements CameraDataSource {
  bool initializeCalled = false;
  CapturedImage? imageToReturn;
  double? lastZoomLevel;
  NormalizedFocusPoint? lastFocusPoint;
  ({double min, double max}) zoomRange = (min: 1.0, max: 1.0);

  /// If set, thrown by [initialize] instead of succeeding.
  Object? initializeError;

  /// If set, thrown by [captureImage] instead of succeeding.
  Object? captureError;

  @override
  CameraController? get previewController => null;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<CapturedImage> captureImage() async {
    final error = captureError;
    if (error != null) throw error;
    return imageToReturn ??
        CapturedImage(
          id: 'fake',
          localFilePath: '/fake/path.jpg',
          capturedAt: DateTime(2024),
        );
  }

  @override
  Future<void> setZoomLevel(double zoomLevel) async {
    lastZoomLevel = zoomLevel;
  }

  @override
  Future<({double min, double max})> getZoomRange() async => zoomRange;

  @override
  Future<void> setFocusPoint(NormalizedFocusPoint point) async {
    lastFocusPoint = point;
  }

  @override
  Future<void> dispose() async {}
}
