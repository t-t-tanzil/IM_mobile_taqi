import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/data/local/image_batch_json_mapper.dart';
import 'package:camera_sync/domain/entities/captured_image.dart';
import 'package:camera_sync/domain/entities/image_batch.dart';
import 'package:camera_sync/domain/entities/upload_status.dart';

void main() {
  test('ImageBatch survives a JSON round-trip', () {
    final batch = ImageBatch(
      id: 'batch-1',
      images: [
        CapturedImage(
          id: 'img-1',
          localFilePath: '/tmp/1.jpg',
          capturedAt: DateTime(2024, 1, 1, 10),
        ),
      ],
      createdAt: DateTime(2024, 1, 1, 9),
      status: UploadStatus.pending,
    );

    final restored = imageBatchFromJson(imageBatchToJson(batch));

    expect(restored, batch);
  });

  test('multiple images within a batch survive serialization', () {
    final batch = ImageBatch(
      id: 'batch-2',
      images: List.generate(
        5,
        (i) => CapturedImage(
          id: 'img-$i',
          localFilePath: '/tmp/$i.jpg',
          capturedAt: DateTime(2024, 1, 1),
        ),
      ),
      createdAt: DateTime(2024, 1, 1),
      status: UploadStatus.failed,
    );

    final restored = imageBatchFromJson(imageBatchToJson(batch));

    expect(restored.images, batch.images);
    expect(restored.images, hasLength(5));
  });

  test('every upload status round-trips through its string representation', () {
    for (final status in UploadStatus.values) {
      expect(uploadStatusFromJson(uploadStatusToJson(status)), status);
    }
  });

  test('an unknown persisted status throws instead of silently mapping to a valid one', () {
    expect(() => uploadStatusFromJson('archived'), throwsFormatException);
  });

  test('a malformed batch record throws instead of producing a corrupt ImageBatch', () {
    expect(() => imageBatchFromJson({'id': 'batch-1'}), throwsFormatException);
  });
}
