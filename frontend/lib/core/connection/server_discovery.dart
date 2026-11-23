import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'discovery_stub.dart' if (dart.library.io) 'discovery_io.dart' as transport;
import 'discovery_types.dart';
import 'server_connection.dart';

/// False in a web browser, which has no UDP sockets: the address must be typed.
const bool networkSearchAvailable = transport.discoverySearchSupported;

/// The UDP port the server answers on (EXCELENCE_DISCOVERY_PORT).
const int defaultDiscoveryPort = 8765;

/// A server that answered and proved it knows our access token.
@immutable
class DiscoveredServer {
  const DiscoveredServer({required this.name, required this.address});

  /// The server PC's name.
  final String name;

  /// Like `http://192.168.1.30:8000`.
  final String address;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredServer && other.address == address && other.name == name;

  @override
  int get hashCode => Object.hash(name, address);
}

/// Hex HMAC-SHA256 of [nonce] keyed with [token] - what the server sends back
/// instead of the token (see backend/discovery.py).
String discoveryProof(String token, String nonce) {
  return Hmac(sha256, utf8.encode(token)).convert(utf8.encode(nonce)).toString();
}

/// 16 random bytes as 32 hex digits.
String newDiscoveryNonce([Random? random]) {
  final source = random ?? Random.secure();

  return List.generate(
    16,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

List<int> encodeDiscoveryRequest(String nonce) {
  return utf8.encode(jsonEncode({'excelence': 'discover', 'v': 1, 'nonce': nonce}));
}

/// The server described by one received datagram, or null when it is not a
/// valid answer to OUR question: wrong format or version, a different number
/// echoed back, a proof made with another token, or a sender that is not a
/// usable network address.
DiscoveredServer? parseDiscoveryReply({
  required List<int> data,
  required String senderHost,
  required String nonce,
  required String token,
}) {
  try {
    final decoded = jsonDecode(utf8.decode(data));

    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    if (decoded['excelence'] != 'here' || decoded['v'] != 1) {
      return null;
    }

    if (decoded['nonce'] != nonce || decoded['proof'] != discoveryProof(token, nonce)) {
      return null;
    }

    final port = decoded['port'];

    if (port is! int || port < 1 || port > 65535) {
      return null;
    }

    final check = checkServerAddress('http://$senderHost:$port');

    if (!check.isValid) {
      return null;
    }

    final name = decoded['name'];

    return DiscoveredServer(
      name: name is String ? name : '',
      address: check.address!,
    );
  } catch (_) {
    return null;
  }
}

typedef UdpDiscover = Future<List<UdpReply>> Function({
  required List<int> request,
  required int port,
  required Duration timeout,
});

/// Looks for servers on the local network that know [token]. Several can
/// answer; the same server is listed once. An empty list means none was
/// found (or the platform cannot search).
Future<List<DiscoveredServer>> findServers({
  required String token,
  int port = defaultDiscoveryPort,
  Duration timeout = const Duration(seconds: 3),
  UdpDiscover? udp,
  String? nonce,
}) async {
  if (token.isEmpty) {
    return const [];
  }

  final number = nonce ?? newDiscoveryNonce();
  final replies = await (udp ?? transport.udpDiscover)(
    request: encodeDiscoveryRequest(number),
    port: port,
    timeout: timeout,
  );

  final found = <DiscoveredServer>[];

  for (final reply in replies) {
    final server = parseDiscoveryReply(
      data: reply.data,
      senderHost: reply.host,
      nonce: number,
      token: token,
    );

    if (server != null && !found.contains(server)) {
      found.add(server);
    }
  }

  return found;
}
