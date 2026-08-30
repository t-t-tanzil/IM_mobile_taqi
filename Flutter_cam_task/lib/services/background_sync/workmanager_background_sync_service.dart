import 'package:workmanager/workmanager.dart';

import '../../core/constants/app_constants.dart';
import 'background_sync_callback_dispatcher.dart';
import 'background_sync_service.dart';

/// Thin wrapper around the `workmanager` plugin - registration only. The
/// actual sync algorithm lives in [SyncEngine] and is invoked from
/// [callbackDispatcher]; nothing here duplicates it.
class WorkManagerBackgroundSyncService implements BackgroundSyncService {
  const WorkManagerBackgroundSyncService();

  /// A periodic run is only a safety net for triggers that were missed
  /// while the app wasn't running (e.g. connectivity returned while
  /// killed) - startup, connectivity-restore, and manual retry already
  /// cover the live-app case. 30 minutes keeps that net reasonably tight
  /// without waking the device aggressively; Android enforces a 15-minute
  /// floor on periodic work regardless.
  static const Duration _periodicSyncFrequency = Duration(minutes: 30);

  @override
  Future<void> initialize() {
    return Workmanager().initialize(callbackDispatcher);
  }

  @override
  Future<void> schedulePeriodicSync() {
    return Workmanager().registerPeriodicTask(
      AppConstants.backgroundSyncUniqueWorkName,
      AppConstants.backgroundSyncTaskName,
      frequency: _periodicSyncFrequency,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  @override
  Future<void> cancelScheduledSync() {
    return Workmanager().cancelByUniqueName(AppConstants.backgroundSyncUniqueWorkName);
  }
}
