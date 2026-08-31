import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show Offset;

import '../../domain/entities/captured_image.dart';

/// A clear status model instead of a pile of independent booleans.
enum CameraStatus {
  initializing,
  ready,

  /// Not granted yet, or denied once - the system dialog can still be shown.
  permissionDenied,

  /// The OS will no longer show its own dialog - the user must open Settings.
  permissionPermanentlyDenied,

  /// No usable camera hardware is available.
  unavailable,

  /// Initialization failed for a reason other than permission/availability.
  error,
}

/// Sentinel used so [CameraState.copyWith] can distinguish "leave this
/// nullable field unchanged" from "explicitly set it to null".
class _Unset {
  const _Unset();
}

const _unset = _Unset();

class CameraState extends Equatable {
  const CameraState({
    this.status = CameraStatus.initializing,
    this.zoomLevel = 1.0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.availableZoomLevels = const [1.0],
    this.isFrontCamera = false,
    this.focusIndicatorPosition,
    this.batchImages = const [],
    this.isCapturing = false,
    this.errorMessage,
    this.captureErrorMessage,
  });

  final CameraStatus status;
  final double zoomLevel;
  final double minZoom;
  final double maxZoom;
  final List<double> availableZoomLevels;
  final bool isFrontCamera;

  /// Null when the focus indicator is hidden.
  final Offset? focusIndicatorPosition;
  final List<CapturedImage> batchImages;
  final bool isCapturing;
  final String? errorMessage;
  final String? captureErrorMessage;

  int get batchImageCount => batchImages.length;

  CameraState copyWith({
    CameraStatus? status,
    double? zoomLevel,
    double? minZoom,
    double? maxZoom,
    List<double>? availableZoomLevels,
    bool? isFrontCamera,
    Object? focusIndicatorPosition = _unset,
    List<CapturedImage>? batchImages,
    bool? isCapturing,
    Object? errorMessage = _unset,
    Object? captureErrorMessage = _unset,
  }) {
    return CameraState(
      status: status ?? this.status,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      availableZoomLevels: availableZoomLevels ?? this.availableZoomLevels,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      focusIndicatorPosition: identical(focusIndicatorPosition, _unset)
          ? this.focusIndicatorPosition
          : focusIndicatorPosition as Offset?,
      batchImages: batchImages ?? this.batchImages,
      isCapturing: isCapturing ?? this.isCapturing,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      captureErrorMessage: identical(captureErrorMessage, _unset)
          ? this.captureErrorMessage
          : captureErrorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
        status,
        zoomLevel,
        minZoom,
        maxZoom,
        availableZoomLevels,
        isFrontCamera,
        focusIndicatorPosition,
        batchImages,
        isCapturing,
        errorMessage,
        captureErrorMessage,
      ];
}
