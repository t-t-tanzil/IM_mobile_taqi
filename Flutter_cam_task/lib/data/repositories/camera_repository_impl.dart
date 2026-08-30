import '../../domain/entities/captured_image.dart';
import '../../domain/entities/normalized_focus_point.dart';
import '../../domain/repositories/camera_repository.dart';
import '../camera/camera_data_source.dart';

/// Pure delegation to the camera data source - no business logic of its
/// own. Behavior depends entirely on the (currently stubbed) data source.
class CameraRepositoryImpl implements CameraRepository {
  const CameraRepositoryImpl(this._dataSource);

  final CameraDataSource _dataSource;

  @override
  Future<void> initializeCamera() => _dataSource.initialize();

  @override
  Future<CapturedImage> captureImage() => _dataSource.captureImage();

  @override
  Future<void> setZoomLevel(double zoomLevel) => _dataSource.setZoomLevel(zoomLevel);

  @override
  Future<({double min, double max})> getZoomRange() => _dataSource.getZoomRange();

  @override
  Future<void> setFocusPoint(NormalizedFocusPoint point) => _dataSource.setFocusPoint(point);

  @override
  Future<void> dispose() => _dataSource.dispose();
}
