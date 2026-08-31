import 'package:camera/camera.dart';

import '../../domain/entities/captured_image.dart';
import '../../domain/entities/normalized_focus_point.dart';

abstract interface class CameraDataSource {
  Future<void> initialize();

  /// Switches between the back and front camera, re-initializing the
  /// controller on the newly-selected lens. A no-op if the device has no
  /// second camera to switch to.
  Future<void> switchCamera();

  Future<CapturedImage> captureImage();

  Future<void> setZoomLevel(double zoomLevel);

  Future<({double min, double max})> getZoomRange();

  Future<void> setFocusPoint(NormalizedFocusPoint point);

  Future<void> dispose();

  /// Exposed only so the presentation layer can render the live preview via
  /// package:camera's CameraPreview widget, which requires a CameraController
  /// directly - there is no controller-free way to render it. This is a
  /// deliberate, narrow exception to keeping plugin types out of
  /// presentation; it is not used for any camera control logic, which all
  /// flows through CameraRepository instead. Domain never sees this type.
  CameraController? get previewController;
}
