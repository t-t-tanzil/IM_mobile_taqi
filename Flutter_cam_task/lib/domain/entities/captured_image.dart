import 'package:equatable/equatable.dart';

/// A single captured photo. Deliberately just a file-path reference, not
/// image bytes - large binary data must never live in domain models or in
/// SharedPreferences.
class CapturedImage extends Equatable {
  const CapturedImage({
    required this.id,
    required this.localFilePath,
    required this.capturedAt,
  });

  final String id;
  final String localFilePath;
  final DateTime capturedAt;

  @override
  List<Object?> get props => [id, localFilePath, capturedAt];
}
