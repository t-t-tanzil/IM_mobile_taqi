import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/service_locator.dart';
import '../../domain/entities/image_batch.dart';
import '../../domain/entities/upload_status.dart';
import '../../domain/sync/sync_result.dart';
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
        title: const Text('Pending Uploads'),
        actions: [
          BlocBuilder<UploadCubit, UploadState>(
            bloc: uploadCubit,
            builder: (context, state) {
              return IconButton(
                icon: state.isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                tooltip: 'Sync now',
                onPressed: state.isSyncing ? null : uploadCubit.retry,
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<UploadCubit, UploadState>(
        bloc: uploadCubit,
        listenWhen: (previous, current) =>
            current.lastSyncResult != null && previous.lastSyncResult != current.lastSyncResult,
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
              if (state.errorMessage != null) _ErrorBanner(message: state.errorMessage!),
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
                            onRetry: batch.status == UploadStatus.failed && !state.isSyncing
                                ? uploadCubit.retry
                                : null,
                          );
                        },
                      ),
              ),
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
        SyncResult.completedWithFailures => 'Some uploads failed and remain in the queue.',
      };
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text('No pending uploads', style: Theme.of(context).textTheme.bodyLarge),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${batch.images.length} photo${batch.images.length == 1 ? '' : 's'}'),
                  Text(
                    _formatTime(batch.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _StatusChip(status: batch.status),
                ],
              ),
            ),
            Column(
              children: [
                if (batch.status == UploadStatus.uploading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (onRetry != null)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry',
                    onPressed: onRetry,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final UploadStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      UploadStatus.pending => ('Pending', Colors.blueGrey),
      UploadStatus.uploading => ('Uploading', Colors.blue),
      UploadStatus.failed => ('Failed', Colors.red),
      UploadStatus.success => ('Success', Colors.green),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
