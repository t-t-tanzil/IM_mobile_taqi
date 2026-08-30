import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/image_batch.dart';
import '../../domain/entities/upload_status.dart';
import 'image_batch_json_mapper.dart';
import 'upload_queue_data_source.dart';

/// Persists batch metadata (ids, local file paths, timestamps, status) as
/// JSON in SharedPreferences - never raw image bytes. Images themselves
/// live in application-accessible local storage (written by the camera
/// data source via path_provider); only their paths are stored here.
///
/// On the first read after app start, any batch stuck in `uploading` is
/// recovered back to `pending` - see [_recoverStaleUploading].
class SharedPreferencesUploadQueueDataSource implements UploadQueueDataSource {
  SharedPreferences? _preferencesInstance;
  List<ImageBatch>? _cache;
  final StreamController<List<ImageBatch>> _controller =
      StreamController<List<ImageBatch>>.broadcast();

  Future<SharedPreferences> get _preferences async =>
      _preferencesInstance ??= await SharedPreferences.getInstance();

  Future<List<ImageBatch>> _readAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final prefs = await _preferences;
    final raw = prefs.getString(AppConstants.uploadQueueStorageKey);
    final decoded = raw == null || raw.isEmpty ? const <ImageBatch>[] : _decodeBatches(raw);

    final recovered = _recoverStaleUploading(decoded);
    _cache = recovered;
    if (!identical(recovered, decoded)) {
      // Persist the recovery so the corrected status survives future reads.
      await _writeAll(recovered);
    }
    return recovered;
  }

  /// Parses the persisted JSON array, skipping any individual record that
  /// fails to parse rather than losing (or crashing on) the whole queue. If
  /// the payload itself isn't valid JSON/a list at all, starts from an
  /// empty queue - it never silently treats corrupted data as a valid batch.
  List<ImageBatch> _decodeBatches(String raw) {
    final List<dynamic> entries;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      entries = decoded;
    } on FormatException {
      return const [];
    }

    final batches = <ImageBatch>[];
    for (final entry in entries) {
      try {
        batches.add(imageBatchFromJson(entry as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return batches;
  }

  List<ImageBatch> _recoverStaleUploading(List<ImageBatch> batches) {
    final hasStale = batches.any((batch) => batch.status == UploadStatus.uploading);
    if (!hasStale) return batches;
    return batches
        .map(
          (batch) => batch.status == UploadStatus.uploading
              ? batch.copyWith(status: UploadStatus.pending)
              : batch,
        )
        .toList();
  }

  Future<void> _writeAll(List<ImageBatch> batches) async {
    _cache = batches;
    final prefs = await _preferences;
    final encoded = jsonEncode(batches.map(imageBatchToJson).toList());
    await prefs.setString(AppConstants.uploadQueueStorageKey, encoded);
    _controller.add(List.unmodifiable(batches));
  }

  @override
  Future<void> saveBatch(ImageBatch batch) async {
    final batches = [...await _readAll(), batch];
    await _writeAll(batches);
  }

  @override
  Future<void> updateBatch(ImageBatch batch) async {
    final batches = (await _readAll())
        .map((existing) => existing.id == batch.id ? batch : existing)
        .toList();
    await _writeAll(batches);
  }

  @override
  Future<void> removeBatch(String batchId) async {
    final batches = (await _readAll()).where((batch) => batch.id != batchId).toList();
    await _writeAll(batches);
  }

  @override
  Stream<List<ImageBatch>> observeBatches() async* {
    yield await _readAll();
    yield* _controller.stream;
  }
}
