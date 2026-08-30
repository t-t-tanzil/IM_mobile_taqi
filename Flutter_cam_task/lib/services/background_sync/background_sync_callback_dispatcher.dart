import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/constants/app_constants.dart';
import '../../data/local/shared_preferences_upload_queue_data_source.dart';
import '../../data/remote/mock_upload_data_source.dart';
import '../../data/repositories/upload_repository_impl.dart';
import '../../domain/sync/sync_engine.dart';
import '../../domain/usecases/sync_pending_uploads.dart';
import '../connectivity/connectivity_plus_service.dart';
import 'sync_result_mapper.dart';

/// Registered once via `Workmanager().initialize` in
/// [WorkManagerBackgroundSyncService.initialize]. Android/iOS invoke this in
/// a fresh background isolate that shares no memory with the running app -
/// it cannot assume any foreground-isolate state (no `getIt` graph, no
/// BuildContext, no widgets, no CameraController, no CameraCubit or
/// UploadCubit). It builds its own minimal dependency chain pointed at the
/// SAME persistent SharedPreferences-backed queue and the same mock API,
/// then calls straight through SyncPendingUploads -> SyncEngine.sync() -
/// the single source of truth for the sync algorithm. Nothing here
/// re-implements any part of that algorithm.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName != AppConstants.backgroundSyncTaskName) return true;

    final syncPendingUploads = SyncPendingUploads(_buildSyncEngine());
    final result = await syncPendingUploads();
    return mapSyncResultToWorkManagerSuccess(result);
  });
}

SyncEngine _buildSyncEngine() {
  final uploadRepository = UploadRepositoryImpl(
    SharedPreferencesUploadQueueDataSource(),
    MockUploadDataSource(),
  );
  return SyncEngine(uploadRepository, ConnectivityPlusService());
}
