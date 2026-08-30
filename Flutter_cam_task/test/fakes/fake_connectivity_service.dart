import 'dart:async';

import 'package:camera_sync/services/connectivity/connectivity_service.dart';

class FakeConnectivityService implements ConnectivityService {
  final StreamController<ConnectivityStatus> _controller = StreamController.broadcast();
  ConnectivityStatus status = ConnectivityStatus.online;

  void emit(ConnectivityStatus newStatus) {
    status = newStatus;
    _controller.add(newStatus);
  }

  @override
  Stream<ConnectivityStatus> observeConnectivity() => _controller.stream;

  @override
  Future<ConnectivityStatus> checkConnectivity() async => status;
}
