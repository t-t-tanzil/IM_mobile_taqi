import '../entities/captured_image.dart';
import '../entities/normalized_focus_point.dart';

/// Platform-independent camera control contract. No CameraController, XFile,
/// or other camera-plugin type may appear here or in anything that depends
/// on this interface.
abstract interface class CameraRepository {
  Future<void> initializeCamera();

  Future<CapturedImage> captureImage();

  /// Clamped by the implementation to the hardware's supported range.
  Future<void> setZoomLevel(double zoomLevel);

  /// The camera's supported zoom range, where available.
  Future<({double min, double max})> getZoomRange();

  /// Requests focus/exposure at the given normalized point, where supported.
  Future<void> setFocusPoint(NormalizedFocusPoint point);

  Future<void> dispose();
}
