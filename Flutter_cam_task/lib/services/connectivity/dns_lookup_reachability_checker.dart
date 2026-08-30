import 'dart:io';

import 'internet_reachability_checker.dart';

/// A DNS lookup is a cheap, dependency-free way to distinguish "has a
/// network interface" from "can actually reach the internet" - no HTTP
/// client or extra package needed, since dart:io provides it directly.
class DnsLookupReachabilityChecker implements InternetReachabilityChecker {
  const DnsLookupReachabilityChecker({
    this.lookupHost = 'example.com',
    this.timeout = const Duration(seconds: 3),
  });

  final String lookupHost;
  final Duration timeout;

  @override
  Future<bool> isReachable() async {
    try {
      final result = await InternetAddress.lookup(lookupHost).timeout(timeout);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
