import '../entities/image_batch.dart';
import '../repositories/upload_repository.dart';

class GetPendingUploads {
  const GetPendingUploads(this._uploadRepository);

  final UploadRepository _uploadRepository;

  Stream<List<ImageBatch>> call() => _uploadRepository.observePendingBatches();
}
