/// Explicit pending-upload state for an [ImageBatch]. `success` is
/// transient - a batch is removed from the queue once it reaches success,
/// it is not expected to be persisted in that state.
enum UploadStatus {
  pending,
  uploading,
  success,
  failed,
}
