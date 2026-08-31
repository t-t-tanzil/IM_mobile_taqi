import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/service_locator.dart';
import '../../domain/entities/image_batch.dart';
import '../../domain/entities/upload_status.dart';
import '../../domain/sync/sync_result.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'upload_cubit.dart';
import 'upload_state.dart';

class PendingUploadsScreen extends StatelessWidget {
  const PendingUploadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // UploadCubit is an app-wide singleton (see service_locator.dart) -
    // fetched directly rather than through a BlocProvider ancestor, since
    // there's exactly one instance for the whole app lifetime regardless of
    // which screen is showing.
    final uploadCubit = getIt<UploadCubit>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Manager'),
        actions: [
          BlocBuilder<UploadCubit, UploadState>(
            bloc: uploadCubit,
            builder: (context, state) {
              return IconButton(
                icon: state.isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.blue,
                        ),
                      )
                    : const Icon(Icons.sync),
                tooltip: 'Sync now',
                onPressed: state.isSyncing ? null : uploadCubit.retry,
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: BlocConsumer<UploadCubit, UploadState>(
        bloc: uploadCubit,
        listenWhen: (previous, current) =>
            current.lastSyncResult != null &&
            previous.lastSyncResult != current.lastSyncResult,
        listener: (context, state) {
          final message = _messageForSyncResult(state.lastSyncResult!);
          if (message != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              const _ConnectionStatusBar(),
              if (state.errorMessage != null)
                _ErrorBanner(message: state.errorMessage!),
              if (state.batches.isNotEmpty)
                _StatusSummary(
                  batches: state.batches,
                  isSyncing: state.isSyncing,
                ),
              Expanded(
                child: state.batches.isEmpty
                    ? const _EmptyView()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: state.batches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final batch = state.batches[index];
                          return _BatchTile(
                            batch: batch,
                            index: index,
                            onRemove: () => uploadCubit.removeBatch(batch.id),
                            onRetry:
                                batch.status == UploadStatus.failed &&
                                    !state.isSyncing
                                ? uploadCubit.retry
                                : null,
                          );
                        },
                      ),
              ),
              _NewBatchBar(onPressed: () => Navigator.of(context).maybePop()),
            ],
          );
        },
      ),
    );
  }

  /// completed/nothingToSync/alreadyInProgress are routine and don't need
  /// to interrupt the user - only the noteworthy outcomes get a snackbar.
  String? _messageForSyncResult(SyncResult result) => switch (result) {
    SyncResult.completed => null,
    SyncResult.nothingToSync => null,
    SyncResult.alreadyInProgress => null,
    SyncResult.skippedOffline =>
      "You're offline - uploads will resume automatically once connected.",
    SyncResult.completedWithFailures =>
      'Some uploads failed and remain in the queue.',
  };
}

/// A real, live connectivity readout - not a static "connected" label. Uses
/// the same [ConnectivityService] SyncEngine relies on internally, read
/// here only for display via a plain StreamBuilder; no new state
/// management or business logic is introduced.
class _ConnectionStatusBar extends StatelessWidget {
  const _ConnectionStatusBar();

  @override
  Widget build(BuildContext context) {
    final connectivity = getIt<ConnectivityService>();
    return StreamBuilder<ConnectivityStatus>(
      stream: connectivity.observeConnectivity(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        final (label, color) = switch (status) {
          ConnectivityStatus.online => ('Online', AppColors.green),
          ConnectivityStatus.offline => ('Offline', AppColors.red),
          null => ('Checking…', AppColors.neutral),
        };
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Counts derived purely from the real batch list already in [UploadState].
/// While a sync pass is running, an indeterminate progress bar reflects
/// that honestly - the app only tracks batch-level status, so a specific
/// percentage would be fabricated.
class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.batches, required this.isSyncing});

  final List<ImageBatch> batches;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final pending = batches
        .where((b) => b.status == UploadStatus.pending)
        .length;
    final uploading = batches
        .where((b) => b.status == UploadStatus.uploading)
        .length;
    final failed = batches.where((b) => b.status == UploadStatus.failed).length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'BATCH QUEUE',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '${batches.length} batch${batches.length == 1 ? '' : 'es'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isSyncing) ...[
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(
                minHeight: 5,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(AppColors.blue),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (pending > 0)
                _CountPill(
                  label: 'Pending',
                  count: pending,
                  color: AppColors.neutral,
                ),
              if (uploading > 0) ...[
                if (pending > 0) const SizedBox(width: 8),
                _CountPill(
                  label: 'Uploading',
                  count: uploading,
                  color: AppColors.blue,
                ),
              ],
              if (failed > 0) ...[
                if (pending > 0 || uploading > 0) const SizedBox(width: 8),
                _CountPill(
                  label: 'Failed',
                  count: failed,
                  color: AppColors.red,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_done_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No pending uploads',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Batches you queue from the camera will show up here.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({
    required this.batch,
    required this.index,
    required this.onRemove,
    this.onRetry,
  });

  final ImageBatch batch;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback? onRetry;

  String get _label => 'Batch ${(index + 1).toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) {
    final (accentColor, statusText) = switch (batch.status) {
      UploadStatus.pending => (AppColors.neutral, 'Waiting to sync'),
      UploadStatus.uploading => (AppColors.blue, 'Uploading now…'),
      UploadStatus.failed => (AppColors.red, 'Upload failed - tap retry'),
      UploadStatus.success => (AppColors.green, 'Synced'),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _BatchThumbnail(batch: batch),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: batch.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${batch.images.length} photo${batch.images.length == 1 ? '' : 's'} · ${_formatTime(batch.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (batch.status == UploadStatus.uploading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.blue,
                      ),
                    ),
                  )
                else if (onRetry != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppColors.blue),
                    tooltip: 'Retry',
                    onPressed: onRetry,
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute';
  }
}

/// A real thumbnail from the first captured photo in the batch - never a
/// fabricated preview. Falls back to an icon if the file is unreadable
/// (e.g. a batch persisted before its files finished writing, or removed
/// out from under the queue).
class _BatchThumbnail extends StatelessWidget {
  const _BatchThumbnail({required this.batch});

  final ImageBatch batch;

  @override
  Widget build(BuildContext context) {
    final firstImage = batch.images.isEmpty ? null : batch.images.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: firstImage == null
            ? const _ThumbnailFallback()
            : Image.file(
                File(firstImage.localFilePath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ThumbnailFallback(),
              ),
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.textSecondary,
        size: 22,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final UploadStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      UploadStatus.pending => ('Pending', AppColors.neutral),
      UploadStatus.uploading => ('Uploading', AppColors.blue),
      UploadStatus.failed => ('Failed', AppColors.red),
      UploadStatus.success => ('Success', AppColors.green),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Persistent bottom action - the real, existing way back to the camera to
/// start another batch is just popping this route (it's always pushed
/// directly on top of CameraPreviewScreen), surfaced here as a visible
/// button rather than only the AppBar back arrow.
class _NewBatchBar extends StatelessWidget {
  const _NewBatchBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.camera_alt_outlined, size: 20),
          label: const Text('New Batch'),
        ),
      ),
    );
  }
}
