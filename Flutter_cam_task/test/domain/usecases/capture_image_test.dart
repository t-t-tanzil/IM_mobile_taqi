import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/data/repositories/camera_repository_impl.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/usecases/capture_image.dart';

import '../../fakes/fake_camera_data_source.dart';

void main() {
  test('CaptureImage forwards the repository result', () async {
    final fakeDataSource = FakeCameraDataSource()
      ..imageToReturn = CapturedImage(
        id: '1',
        localFilePath: '/tmp/1.jpg',
        capturedAt: DateTime(2024, 1, 1),
      );
    final repository = CameraRepositoryImpl(fakeDataSource);
    final useCase = CaptureImage(repository);

    final result = await useCase();

    expect(result.id, '1');
    expect(result.localFilePath, '/tmp/1.jpg');
  });
}
