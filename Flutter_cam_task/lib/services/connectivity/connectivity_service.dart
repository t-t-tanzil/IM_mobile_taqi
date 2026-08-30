/// `offline`/`online` only - never conflated with raw network-interface
/// presence. A device can have a Wi-Fi interface "connected" with no actual
/// internet access.
enum ConnectivityStatus { online, offline }

abstract interface class ConnectivityService {
  Stream<ConnectivityStatus> observeConnectivity();

  Future<ConnectivityStatus> checkConnectivity();
}
