import 'dart:io';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/errors/camera_failure.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/captured_image.dart';
import '../../domain/entities/normalized_focus_point.dart';
import 'camera_data_source.dart';

/// Adapts the `camera` plugin into [CameraDataSource]. CameraController and
/// XFile must never leave this file - everything above this layer only
/// ever sees domain types (with the one documented exception of
/// [previewController], needed purely for rendering).
///
/// Permission is only *checked* here (read-only), never requested - the
/// actual request/settings UX belongs to the presentation layer.
class FlutterCameraDataSource implements CameraDataSource {
  CameraController? _controller;

  @override
  CameraController? get previewController => _controller;

  @override
  Future<void> initialize() async {
    final permissionStatus = await Permission.camera.status;
    if (!permissionStatus.isGranted) {
      throw const CameraPermissionDenied();
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw const CameraUnavailable();
    }

    final camera = cameras.firstWhere(
      (description) => description.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller.initialize();
    } on CameraException catch (exception) {
      await controller.dispose();
      throw _mapInitializationException(exception);
    }

    // Replace any previous controller only after the new one succeeds, and
    // dispose the old one so we never leak or hold two open controllers.
    final previous = _controller;
    _controller = controller;
    await previous?.dispose();
  }

  CameraFailure _mapInitializationException(CameraException exception) {
    const permissionCodes = {
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    };
    if (permissionCodes.contains(exception.code)) {
      return const CameraPermissionDenied();
    }
    return const CameraInitializationFailed();
  }

  @override
  Future<CapturedImage> captureImage() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraInitializationFailed();
    }

    final XFile file;
    try {
      file = await controller.takePicture();
    } on CameraException {
      throw const CameraInitializationFailed();
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final id = IdGenerator.generate();
      final savedPath = '${directory.path}/$id.jpg';
      await File(file.path).copy(savedPath);

      return CapturedImage(id: id, localFilePath: savedPath, capturedAt: DateTime.now());
    } on FileSystemException {
      throw const CaptureStorageFailure();
    }
  }

  @override
  Future<void> setZoomLevel(double zoomLevel) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      await controller.setZoomLevel(zoomLevel.clamp(min, max));
    } on CameraException {
      throw const ZoomUnsupported();
    }
  }

  @override
  Future<({double min, double max})> getZoomRange() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return (min: 1.0, max: 1.0);
    }
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      return (min: min, max: max);
    } on CameraException {
      throw const ZoomUnsupported();
    }
  }

  @override
  Future<void> setFocusPoint(NormalizedFocusPoint point) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      final offset = Offset(point.x, point.y);
      await controller.setFocusPoint(offset);
      await controller.setExposurePoint(offset);
    } on CameraException {
      throw const FocusUnsupported();
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
