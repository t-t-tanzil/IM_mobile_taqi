import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_service.dart';
import 'dns_lookup_reachability_checker.dart';
import 'internet_reachability_checker.dart';

/// Wraps connectivity_plus for interface-level change notifications, then
/// confirms with an actual reachability check before reporting `online` -
/// "a network interface is present" is not treated as sufficient proof of
/// internet access. `.distinct()` on the stream avoids re-emitting for
/// repeated identical statuses (e.g. Wi-Fi flapping while genuinely still
/// online), which is what keeps repeated ONLINE signals from triggering
/// redundant sync attempts downstream.
class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService({
    Connectivity? connectivity,
    InternetReachabilityChecker? reachabilityChecker,
  })  : _connectivity = connectivity ?? Connectivity(),
        _reachabilityChecker = reachabilityChecker ?? const DnsLookupReachabilityChecker();

  final Connectivity _connectivity;
  final InternetReachabilityChecker _reachabilityChecker;

  @override
  Stream<ConnectivityStatus> observeConnectivity() {
    return _connectivity.onConnectivityChanged
        .asyncMap(_resolveStatus)
        .distinct();
  }

  @override
  Future<ConnectivityStatus> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    return _resolveStatus(results);
  }

  Future<ConnectivityStatus> _resolveStatus(List<ConnectivityResult> results) async {
    final hasInterface = results.any((result) => result != ConnectivityResult.none);
    if (!hasInterface) return ConnectivityStatus.offline;

    final reachable = await _reachabilityChecker.isReachable();
    return reachable ? ConnectivityStatus.online : ConnectivityStatus.offline;
  }
}
