import '../../domain/entities/captured_image.dart';
import '../../domain/entities/image_batch.dart';
import '../../domain/entities/upload_status.dart';

const _statusPending = 'pending';
const _statusUploading = 'uploading';
const _statusFailed = 'failed';
const _statusSuccess = 'success';

/// Controlled string representation for persistence - never the raw Dart
/// enum name, so renaming an enum value later can't silently corrupt
/// already-persisted data.
String uploadStatusToJson(UploadStatus status) => switch (status) {
      UploadStatus.pending => _statusPending,
      UploadStatus.uploading => _statusUploading,
      UploadStatus.failed => _statusFailed,
      UploadStatus.success => _statusSuccess,
    };

/// Never silently coerces an unrecognized value - a corrupted/unknown
/// status must surface as an explicit error, not default to pending or
/// success.
UploadStatus uploadStatusFromJson(String value) => switch (value) {
      _statusPending => UploadStatus.pending,
      _statusUploading => UploadStatus.uploading,
      _statusFailed => UploadStatus.failed,
      _statusSuccess => UploadStatus.success,
      _ => throw FormatException('Unknown upload status: "$value"'),
    };

Map<String, dynamic> capturedImageToJson(CapturedImage image) => {
      'id': image.id,
      'localFilePath': image.localFilePath,
      'capturedAt': image.capturedAt.toIso8601String(),
    };

CapturedImage capturedImageFromJson(Map<String, dynamic> json) {
  final id = json['id'];
  final localFilePath = json['localFilePath'];
  final capturedAt = json['capturedAt'];
  if (id is! String || localFilePath is! String || capturedAt is! String) {
    throw const FormatException('Malformed CapturedImage record');
  }
  return CapturedImage(
    id: id,
    localFilePath: localFilePath,
    capturedAt: DateTime.parse(capturedAt),
  );
}

Map<String, dynamic> imageBatchToJson(ImageBatch batch) => {
      'id': batch.id,
      'createdAt': batch.createdAt.toIso8601String(),
      'status': uploadStatusToJson(batch.status),
      'images': batch.images.map(capturedImageToJson).toList(),
    };

ImageBatch imageBatchFromJson(Map<String, dynamic> json) {
  final id = json['id'];
  final createdAt = json['createdAt'];
  final status = json['status'];
  final images = json['images'];
  if (id is! String || createdAt is! String || status is! String || images is! List) {
    throw const FormatException('Malformed ImageBatch record');
  }
  return ImageBatch(
    id: id,
    createdAt: DateTime.parse(createdAt),
    status: uploadStatusFromJson(status),
    images: images.map((entry) => capturedImageFromJson(entry as Map<String, dynamic>)).toList(),
  );
}
