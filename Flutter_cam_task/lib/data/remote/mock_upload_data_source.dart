import '../../core/errors/upload_failure.dart';
import '../../domain/entities/image_batch.dart';
import 'upload_data_source.dart';

/// Deterministic mock standing in for a real HTTP API - none was provided
/// for this assessment. No randomness: [shouldSucceed] is set explicitly,
/// never rolled, so tests are never flaky and behavior is fully
/// predictable. [simulatedLatency] is a fixed (not random) delay purely so
/// the "Uploading" state is visibly demonstrable in the UI; tests should
/// pass `Duration.zero` to keep the suite fast.
class MockUploadDataSource implements UploadDataSource {
  MockUploadDataSource({
    this.shouldSucceed = true,
    this.simulatedLatency = const Duration(milliseconds: 400),
  });

  bool shouldSucceed;
  Duration simulatedLatency;

  @override
  Future<void> upload(ImageBatch batch) async {
    if (simulatedLatency > Duration.zero) {
      await Future<void>.delayed(simulatedLatency);
    }
    if (!shouldSucceed) {
      throw const RemoteUploadFailure();
    }
  }
}
