import 'package:equatable/equatable.dart';

import '../../domain/entities/image_batch.dart';
import '../../domain/sync/sync_result.dart';

/// Sentinel used so [UploadState.copyWith] can distinguish "leave a
/// nullable field unchanged" from "explicitly clear it".
class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// Empty queue by default - populated as soon as UploadCubit subscribes to
/// the persisted queue. Per-batch status (pending/uploading/failed) lives
/// on each ImageBatch itself and is already reflected reactively through
/// [batches]; [isSyncing]/[lastSyncResult] are about the sync *pass* as a
/// whole, not any one batch.
class UploadState extends Equatable {
  const UploadState({
    this.batches = const [],
    this.isAddingBatch = false,
    this.isSyncing = false,
    this.lastSyncResult,
    this.errorMessage,
  });

  final List<ImageBatch> batches;

  /// True while the current camera batch is being persisted to the queue.
  final bool isAddingBatch;

  /// True while a SyncEngine.sync() pass is in flight.
  final bool isSyncing;

  /// The outcome of the most recent sync pass, for one-off UI feedback
  /// (e.g. a snackbar) - not a running status.
  final SyncResult? lastSyncResult;
  final String? errorMessage;

  UploadState copyWith({
    List<ImageBatch>? batches,
    bool? isAddingBatch,
    bool? isSyncing,
    Object? lastSyncResult = _unset,
    Object? errorMessage = _unset,
  }) {
    return UploadState(
      batches: batches ?? this.batches,
      isAddingBatch: isAddingBatch ?? this.isAddingBatch,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncResult:
          identical(lastSyncResult, _unset) ? this.lastSyncResult : lastSyncResult as SyncResult?,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [batches, isAddingBatch, isSyncing, lastSyncResult, errorMessage];
}
