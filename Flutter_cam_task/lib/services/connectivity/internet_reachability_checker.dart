/// A lightweight, actual reachability probe - deliberately separate from
/// "does a network interface exist" (connectivity_plus's own signal), since
/// a device can be associated with Wi-Fi/mobile data with no real internet
/// access behind it (captive portals, router with no WAN, airplane-mode
/// edge cases, etc).
abstract interface class InternetReachabilityChecker {
  Future<bool> isReachable();
}
