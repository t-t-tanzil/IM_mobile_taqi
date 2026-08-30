/// Distinguishes *why* an upload attempt failed. A batch must remain queued
/// for any of these - never deleted.
sealed class UploadFailure {
  const UploadFailure(this.message);

  final String message;
}

class OfflineFailure extends UploadFailure {
  const OfflineFailure([super.message = 'No internet connection is available']);
}

class RemoteUploadFailure extends UploadFailure {
  const RemoteUploadFailure([super.message = 'The upload failed']);
}

class InsufficientStorageFailure extends UploadFailure {
  const InsufficientStorageFailure([super.message = 'Not enough local storage is available']);
}

/// A CapturedImage's localFilePath no longer points to an existing file.
class MissingLocalFileFailure extends UploadFailure {
  const MissingLocalFileFailure([super.message = 'A local image file is missing']);
}
