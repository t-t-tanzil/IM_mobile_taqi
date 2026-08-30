import 'package:equatable/equatable.dart';

import 'captured_image.dart';
import 'upload_status.dart';

/// A group of images captured together and queued for upload as a unit.
/// Multiple batches can be pending at once.
class ImageBatch extends Equatable {
  const ImageBatch({
    required this.id,
    required this.images,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final List<CapturedImage> images;
  final DateTime createdAt;
  final UploadStatus status;

  ImageBatch copyWith({
    List<CapturedImage>? images,
    UploadStatus? status,
  }) {
    return ImageBatch(
      id: id,
      images: images ?? this.images,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [id, images, createdAt, status];
}
