/// Distinguishes *why* the camera failed so the UI can react appropriately
/// instead of crashing. Used by the data layer once camera handling is
/// implemented.
sealed class CameraFailure {
  const CameraFailure(this.message);

  final String message;
}

class CameraPermissionDenied extends CameraFailure {
  const CameraPermissionDenied([super.message = 'Camera permission has not been granted']);
}

class CameraInitializationFailed extends CameraFailure {
  const CameraInitializationFailed([super.message = 'The camera failed to initialize']);
}

class CameraUnavailable extends CameraFailure {
  const CameraUnavailable([super.message = 'No usable camera is available on this device']);
}

class FocusUnsupported extends CameraFailure {
  const FocusUnsupported([super.message = 'This camera does not support manual focus']);
}

class ZoomUnsupported extends CameraFailure {
  const ZoomUnsupported([super.message = 'This camera does not support adjustable zoom']);
}

class CaptureStorageFailure extends CameraFailure {
  const CaptureStorageFailure([super.message = 'Failed to save the captured image']);
}
