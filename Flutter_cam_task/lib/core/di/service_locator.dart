import 'package:get_it/get_it.dart';

import '../../data/camera/camera_data_source.dart';
import '../../data/camera/flutter_camera_data_source.dart';
import '../../data/local/shared_preferences_upload_queue_data_source.dart';
import '../../data/local/upload_queue_data_source.dart';
import '../../data/remote/mock_upload_data_source.dart';
import '../../data/remote/upload_data_source.dart';
import '../../data/repositories/camera_repository_impl.dart';
import '../../data/repositories/upload_repository_impl.dart';
import '../../domain/repositories/camera_repository.dart';
import '../../domain/repositories/upload_repository.dart';
import '../../domain/sync/sync_engine.dart';
import '../../domain/usecases/capture_image.dart';
import '../../domain/usecases/create_batch.dart';
import '../../domain/usecases/get_pending_uploads.dart';
import '../../domain/usecases/sync_pending_uploads.dart';
import '../../presentation/camera/camera_cubit.dart';
import '../../presentation/uploads/upload_cubit.dart';
import '../../services/background_sync/background_sync_service.dart';
import '../../services/background_sync/workmanager_background_sync_service.dart';
import '../../services/connectivity/connectivity_plus_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/connectivity/dns_lookup_reachability_checker.dart';
import '../../services/connectivity/internet_reachability_checker.dart';

final GetIt getIt = GetIt.instance;

/// Registers the dependency graph: presentation -> domain -> data/services.
/// Kept as plain lazy/factory registrations - no need for anything more
/// elaborate at this stage.
void setupServiceLocator() {
  // Services
  getIt.registerLazySingleton<InternetReachabilityChecker>(
    () => const DnsLookupReachabilityChecker(),
  );
  getIt.registerLazySingleton<ConnectivityService>(
    () => ConnectivityPlusService(reachabilityChecker: getIt()),
  );
  getIt.registerLazySingleton<BackgroundSyncService>(
    () => const WorkManagerBackgroundSyncService(),
  );

  // Data sources
  getIt.registerLazySingleton<CameraDataSource>(
    () => FlutterCameraDataSource(),
  );
  getIt.registerLazySingleton<UploadQueueDataSource>(
    () => SharedPreferencesUploadQueueDataSource(),
  );
  getIt.registerLazySingleton<UploadDataSource>(
    () => MockUploadDataSource(),
  );

  // Repositories
  getIt.registerLazySingleton<CameraRepository>(
    () => CameraRepositoryImpl(getIt()),
  );
  getIt.registerLazySingleton<UploadRepository>(
    () => UploadRepositoryImpl(getIt(), getIt()),
  );

  // Sync engine - one central instance, shared by every trigger.
  getIt.registerLazySingleton(() => SyncEngine(getIt(), getIt()));

  // Use cases
  getIt.registerFactory(() => CaptureImage(getIt()));
  getIt.registerFactory(() => CreateBatch(getIt()));
  getIt.registerFactory(() => GetPendingUploads(getIt()));
  getIt.registerFactory(() => SyncPendingUploads(getIt()));

  // Presentation
  getIt.registerFactory(() => CameraCubit(getIt(), getIt()));
  // UploadCubit is a singleton, not a factory: the pending-upload queue is
  // app-wide state shared between the camera screen and the pending
  // uploads screen, unlike CameraCubit which is tightly scoped to one
  // camera session. Consumers must use BlocProvider.value (not
  // BlocProvider(create:...)) so it's never auto-closed by a screen unmount.
  getIt.registerLazySingleton(
    () => UploadCubit(getIt(), getIt(), getIt(), getIt(), getIt(), getIt()),
  );
}
