import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:camera_sync/core/di/service_locator.dart';
import 'package:camera_sync/main.dart';

void main() {
  setUp(() async {
    // UploadCubit (an app-wide singleton) subscribes to the real
    // SharedPreferences-backed queue on construction - without a mock store,
    // its platform channel call in a widget-test environment behaves
    // unpredictably.
    SharedPreferences.setMockInitialValues({});
    // getIt.reset() is asynchronous - unawaited, it can still be clearing
    // the registry after setupServiceLocator() has already re-registered
    // everything, wiping it back out from under whatever resolves next.
    await getIt.reset();
    setupServiceLocator();
  });

  testWidgets(
    'CameraPreviewScreen does not crash when platform channels are unavailable',
    (tester) async {
      // Camera/permission initialization is async and hits platform channels
      // that aren't mocked in a widget test - it must fail gracefully (into
      // the error/retry view) rather than throw. This is intentionally not a
      // camera-hardware test - see camera_cubit_test.dart for that coverage
      // via fakes.
      await tester.pumpWidget(const CameraSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    },
  );
}
