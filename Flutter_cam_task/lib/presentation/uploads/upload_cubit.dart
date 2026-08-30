import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utils/id_generator.dart';
import '../../domain/entities/captured_image.dart';
import '../../domain/entities/image_batch.dart';
import '../../domain/entities/upload_status.dart';
import '../../domain/repositories/upload_repository.dart';
import '../../domain/sync/sync_result.dart';
import '../../domain/usecases/create_batch.dart';
import '../../domain/usecases/get_pending_uploads.dart';
import '../../domain/usecases/sync_pending_uploads.dart';
import '../../services/background_sync/background_sync_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import 'upload_state.dart';

/// Owns the persistent pending-upload queue and requests synchronization -
/// it never performs an upload itself. Every trigger (app startup,
/// connectivity restoration, the manual retry button, and the background
/// worker) funnels through the same [SyncPendingUploads] use case, which
/// itself just calls SyncEngine.sync(). Must not contain camera controller
/// logic - see CameraCubit for that.
class UploadCubit extends Cubit<UploadState> {
  UploadCubit(
    this._getPendingUploads,
    this._createBatch,
    this._uploadRepository,
    this._syncPendingUploads,
    ConnectivityService connectivityService,
    this._backgroundSyncService,
  ) : super(const UploadState()) {
    _queueSubscription = _getPendingUploads().listen(
      (batches) => emit(state.copyWith(batches: batches)),
      onError: (_) => emit(state.copyWith(errorMessage: 'Failed to load pending uploads')),
    );

    // Distinct online/offline transitions - the connectivity service
    // itself already dedupes repeated identical statuses, so every online
    // emission received here is a genuine transition worth syncing on.
    _connectivitySubscription = connectivityService.observeConnectivity().listen((status) {
      if (status == ConnectivityStatus.online) {
        unawaited(_runSync());
        unawaited(_backgroundSyncService.schedulePeriodicSync());
      }
    });

    // Application startup is itself one of the sync triggers.
    unawaited(_runSync());
    unawaited(_backgroundSyncService.schedulePeriodicSync());
  }

  final GetPendingUploads _getPendingUploads;
  final CreateBatch _createBatch;
  final UploadRepository _uploadRepository;
  final SyncPendingUploads _syncPendingUploads;
  final BackgroundSyncService _backgroundSyncService;

  StreamSubscription<List<ImageBatch>>? _queueSubscription;
  StreamSubscription<ConnectivityStatus>? _connectivitySubscription;

  /// Persists [images] as a new pending batch. Returns true only once the
  /// batch is safely persisted, so the caller (the camera flow) knows it's
  /// safe to clear its in-memory batch - the images must never be lost
  /// because persistence failed.
  Future<bool> addBatchToQueue(List<CapturedImage> images) async {
    if (images.isEmpty || state.isAddingBatch) return false;
    emit(state.copyWith(isAddingBatch: true, errorMessage: null));

    final batch = ImageBatch(
      id: IdGenerator.generate(),
      images: images,
      createdAt: DateTime.now(),
      status: UploadStatus.pending,
    );

    try {
      await _createBatch(batch);
      emit(state.copyWith(isAddingBatch: false));
      unawaited(_backgroundSyncService.schedulePeriodicSync());
      return true;
    } catch (_) {
      emit(state.copyWith(isAddingBatch: false, errorMessage: 'Failed to save the batch'));
      return false;
    }
  }

  Future<void> removeBatch(String batchId) async {
    try {
      await _uploadRepository.removeBatch(batchId);
    } catch (_) {
      emit(state.copyWith(errorMessage: 'Failed to remove the batch'));
    }
  }

  /// Requests a synchronization pass. This is the only thing the UI is
  /// allowed to do about a failed batch - it never uploads anything
  /// itself, whether this is a per-batch "Retry" tap or a general refresh.
  Future<void> retry() => _runSync();

  Future<void> _runSync() async {
    emit(state.copyWith(isSyncing: true, errorMessage: null));
    final result = await _syncPendingUploads();
    emit(state.copyWith(isSyncing: false, lastSyncResult: result));
    // A failed batch stays queued; make sure the periodic safety net is
    // (still) scheduled to pick it up even if the app is killed before
    // another live trigger fires.
    if (result == SyncResult.completedWithFailures) {
      unawaited(_backgroundSyncService.schedulePeriodicSync());
    }
  }

  @override
  Future<void> close() {
    _queueSubscription?.cancel();
    _connectivitySubscription?.cancel();
    return super.close();
  }
}
