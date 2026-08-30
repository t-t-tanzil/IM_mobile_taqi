import '../entities/image_batch.dart';
import '../repositories/upload_repository.dart';

class CreateBatch {
  const CreateBatch(this._uploadRepository);

  final UploadRepository _uploadRepository;

  Future<void> call(ImageBatch batch) => _uploadRepository.addBatch(batch);
}
