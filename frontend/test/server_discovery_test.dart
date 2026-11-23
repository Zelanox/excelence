import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/connection/discovery_types.dart';
import 'package:frontend/core/connection/server_discovery.dart';

/// Finding the server on the network: the proof, the messages, and what is
/// accepted as an answer. Nothing here uses a real socket.

const token = 'a-long-enough-secret';
const nonce = '00112233445566778899aabbccddeeff';

// Computed by the server's own code (backend/discovery.py compute_proof), so
// both sides are proven to make the same HMAC.
const knownProof = '3f392e30a372242f3af6b54d264a6b1de9e09e58cdfd23d885eb0bcfac571293';

List<int> reply({
  String kind = 'here',
  int v = 1,
  String name = 'TEST-PC',
  Object? port = 8000,
  String number = nonce,
  String? proof,
  String proofToken = token,
}) {
  return utf8.encode(
    jsonEncode({
      'excelence': kind,
      'v': v,
      'name': name,
      'port': port,
      'nonce': number,
      'proof': proof ?? discoveryProof(proofToken, number),
    }),
  );
}

DiscoveredServer? parse(List<int> data, {String host = '192.168.1.30', String number = nonce, String withToken = token}) {
  return parseDiscoveryReply(data: data, senderHost: host, nonce: number, token: withToken);
}

void main() {
  group('messages', () {
    test('the proof is the same HMAC the server makes', () {
      expect(discoveryProof(token, nonce), knownProof);
    });

    test('the proof depends on the token and on the number', () {
      expect(discoveryProof('another-long-secret', nonce), isNot(knownProof));
      expect(discoveryProof(token, 'ff' * 16), isNot(knownProof));
    });

    test('a nonce is 32 hex digits and differs every time', () {
      final first = newDiscoveryNonce();
      final second = newDiscoveryNonce();

      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second, isNot(first));
      expect(newDiscoveryNonce(Random(1)), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('the question has the format the server expects', () {
      final decoded = jsonDecode(utf8.decode(encodeDiscoveryRequest(nonce)));

      expect(decoded, {'excelence': 'discover', 'v': 1, 'nonce': nonce});
    });
  });

  group('parseDiscoveryReply', () {
    test('accepts a valid answer and builds the address from the sender', () {
      final server = parse(reply());

      expect(server?.name, 'TEST-PC');
      expect(server?.address, 'http://192.168.1.30:8000');
    });

    test('uses the port the server announces', () {
      expect(parse(reply(port: 9123))?.address, 'http://192.168.1.30:9123');
    });

    test('a missing name is allowed', () {
      final data = utf8.encode(jsonEncode({
        'excelence': 'here',
        'v': 1,
        'port': 8000,
        'nonce': nonce,
        'proof': discoveryProof(token, nonce),
      }));

      expect(parse(data)?.name, '');
    });

    test('ignores an answer made with another token', () {
      expect(parse(reply(proofToken: 'someone-elses-secret')), isNull);
      expect(parse(reply(), withToken: 'someone-elses-secret'), isNull);
    });

    test('ignores an answer to a different question', () {
      expect(parse(reply(number: 'ff' * 16)), isNull);
      expect(parse(reply(proof: 'not-the-proof')), isNull);
    });

    test('ignores wrong kinds, versions and ports', () {
      expect(parse(reply(kind: 'discover')), isNull);
      expect(parse(reply(v: 2)), isNull);
      expect(parse(reply(port: '8000')), isNull);
      expect(parse(reply(port: 0)), isNull);
      expect(parse(reply(port: 70000)), isNull);
    });

    test('ignores junk', () {
      expect(parse(utf8.encode('hello')), isNull);
      expect(parse(utf8.encode('[]')), isNull);
      expect(parse(const <int>[]), isNull);
      expect(parse(const [0xff, 0xfe, 0x00]), isNull);
    });

    test('never accepts a localhost sender', () {
      expect(parse(reply(), host: '127.0.0.1'), isNull);
      expect(parse(reply(), host: '0.0.0.0'), isNull);
    });
  });

  group('findServers', () {
    Future<List<DiscoveredServer>> search(
      List<UdpReply> replies, {
      String withToken = token,
      void Function(List<int> request, int port, Duration timeout)? onSend,
    }) {
      return findServers(
        token: withToken,
        nonce: nonce,
        timeout: const Duration(seconds: 2),
        udp: ({required request, required port, required timeout}) async {
          onSend?.call(request, port, timeout);
          return replies;
        },
      );
    }

    test('without a token nothing is sent', () async {
      var sent = false;

      final found = await search(const [], withToken: '', onSend: (_, __, ___) => sent = true);

      expect(found, isEmpty);
      expect(sent, isFalse);
    });

    test('sends the question to the discovery port and waits for the timeout', () async {
      List<int>? request;
      int? port;
      Duration? timeout;

      await search(const [], onSend: (r, p, t) {
        request = r;
        port = p;
        timeout = t;
      });

      expect(jsonDecode(utf8.decode(request!))['nonce'], nonce);
      expect(port, 8765);
      expect(timeout, const Duration(seconds: 2));
    });

    test('lists each valid server once and drops everything else', () async {
      final found = await search([
        UdpReply(reply(), '192.168.1.30'),
        UdpReply(reply(), '192.168.1.30'),                       // repeated answer
        UdpReply(reply(name: 'OTHER-PC', port: 8001), '192.168.1.31'),
        UdpReply(reply(proofToken: 'someone-elses-secret'), '192.168.1.99'),
        UdpReply(utf8.encode('junk'), '192.168.1.98'),
        UdpReply(reply(), '127.0.0.1'),
      ]);

      expect(found, const [
        DiscoveredServer(name: 'TEST-PC', address: 'http://192.168.1.30:8000'),
        DiscoveredServer(name: 'OTHER-PC', address: 'http://192.168.1.31:8001'),
      ]);
    });

    test('nothing answered gives an empty list', () async {
      expect(await search(const []), isEmpty);
    });
  });
}
