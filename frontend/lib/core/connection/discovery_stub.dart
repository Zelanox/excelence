import 'discovery_types.dart';

/// False: this platform cannot search at all.
const bool discoverySearchSupported = false;

/// Platforms without raw UDP sockets (the browser): nothing can be found
/// automatically, so the address has to be typed.
Future<List<UdpReply>> udpDiscover({
  required List<int> request,
  required int port,
  required Duration timeout,
}) async {
  return const [];
}
