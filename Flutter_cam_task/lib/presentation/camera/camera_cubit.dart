import 'dart:async';

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/errors/camera_failure.dart';
import '../../domain/entities/normalized_focus_point.dart';
import '../../domain/repositories/camera_repository.dart';
import '../../domain/usecases/capture_image.dart';
import 'camera_state.dart';
import 'zoom_button_calculator.dart';

const _focusIndicatorDuration = Duration(milliseconds: 1500);

/// Owns all camera control state. Communicates with the camera plugin only
/// through [CameraRepository]/[CaptureImage] - never touches CameraController
/// or any other plugin type directly. Must not contain upload-queue logic -
/// see UploadCubit for that.
class CameraCubit extends Cubit<CameraState> {
  CameraCubit(this._cameraRepository, this._captureImage) : super(const CameraState());

  final CameraRepository _cameraRepository;
  final CaptureImage _captureImage;

  bool _isInitializing = false;
  Timer? _focusIndicatorTimer;

  /// Safe to call repeatedly (e.g. on app resume) - re-entrant calls while
  /// already initializing are ignored, and the underlying data source
  /// disposes any previous controller before creating a new one.
  Future<void> initializeCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;
    emit(state.copyWith(status: CameraStatus.initializing, errorMessage: null));

    try {
      await _cameraRepository.initializeCamera();
      final range = await _cameraRepository.getZoomRange();
      emit(
        state.copyWith(
          status: CameraStatus.ready,
          minZoom: range.min,
          maxZoom: range.max,
          zoomLevel: range.min,
          availableZoomLevels: buildZoomButtonValues(minZoom: range.min, maxZoom: range.max),
          errorMessage: null,
        ),
      );
    } on CameraFailure catch (failure) {
      emit(state.copyWith(status: _statusForFailure(failure), errorMessage: failure.message));
    } catch (_) {
      emit(
        state.copyWith(
          status: CameraStatus.error,
          errorMessage: 'An unexpected camera error occurred',
        ),
      );
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> requestPermission() async {
    final result = await Permission.camera.request();
    if (result.isGranted) {
      await initializeCamera();
    } else if (result.isPermanentlyDenied) {
      emit(
        state.copyWith(
          status: CameraStatus.permissionPermanentlyDenied,
          errorMessage: 'Camera permission has been permanently denied',
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: CameraStatus.permissionDenied,
          errorMessage: 'Camera permission is required to continue',
        ),
      );
    }
  }

  Future<void> openSettings() => openAppSettings();

  void setZoomLevel(double zoomLevel) {
    if (state.status != CameraStatus.ready) return;
    final clamped = zoomLevel.clamp(state.minZoom, state.maxZoom);
    emit(state.copyWith(zoomLevel: clamped));
    _cameraRepository.setZoomLevel(clamped).catchError((_) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: 'Zoom is not supported on this device'));
      }
    });
  }

  void setFocusPoint(NormalizedFocusPoint point, Offset uiPosition) {
    if (state.status != CameraStatus.ready) return;
    emit(state.copyWith(focusIndicatorPosition: uiPosition));
    _cameraRepository.setFocusPoint(point).catchError((_) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: 'Focus is not supported on this device'));
      }
    });

    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(_focusIndicatorDuration, () {
      if (!isClosed) {
        emit(state.copyWith(focusIndicatorPosition: null));
      }
    });
  }

  Future<void> captureImage() async {
    if (state.status != CameraStatus.ready || state.isCapturing) return;
    emit(state.copyWith(isCapturing: true, captureErrorMessage: null));

    try {
      final image = await _captureImage();
      emit(
        state.copyWith(
          isCapturing: false,
          batchImages: [...state.batchImages, image],
        ),
      );
    } on CameraFailure catch (failure) {
      emit(state.copyWith(isCapturing: false, captureErrorMessage: failure.message));
    } catch (_) {
      emit(state.copyWith(isCapturing: false, captureErrorMessage: 'Failed to capture image'));
    }
  }

  /// Clears the in-memory current batch. Intended to be called only after
  /// the batch has been safely persisted to the upload queue - never as a
  /// side effect of a failed persistence attempt, or the images would be
  /// lost from both places.
  void clearCurrentBatch() {
    emit(state.copyWith(batchImages: const []));
  }

  Future<void> disposeCamera() async {
    _focusIndicatorTimer?.cancel();
    await _cameraRepository.dispose();
  }

  CameraStatus _statusForFailure(CameraFailure failure) {
    return switch (failure) {
      CameraPermissionDenied() => CameraStatus.permissionDenied,
      CameraUnavailable() => CameraStatus.unavailable,
      CameraInitializationFailed() => CameraStatus.error,
      FocusUnsupported() => CameraStatus.error,
      ZoomUnsupported() => CameraStatus.error,
      CaptureStorageFailure() => CameraStatus.error,
    };
  }

  @override
  Future<void> close() {
    _focusIndicatorTimer?.cancel();
    return super.close();
  }
}
