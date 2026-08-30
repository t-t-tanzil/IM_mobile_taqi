import '../entities/captured_image.dart';
import '../repositories/camera_repository.dart';

class CaptureImage {
  const CaptureImage(this._cameraRepository);

  final CameraRepository _cameraRepository;

  Future<CapturedImage> call() => _cameraRepository.captureImage();
}
