import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/connection/server_connection.dart';

/// The server address: what is accepted, what is refused (localhost above
/// all), how it is stored on the device, and how a connection is tested.

void main() {
  group('checkServerAddress', () {
    String? cleaned(String raw) => checkServerAddress(raw).address;
    AddressProblem? problem(String raw) => checkServerAddress(raw).problem;

    test('accepts a normal address and cleans it up', () {
      expect(cleaned('http://192.168.1.20:8000'), 'http://192.168.1.20:8000');
      expect(cleaned('  192.168.1.20:8000  '), 'http://192.168.1.20:8000');
      expect(cleaned('http://192.168.1.20:8000/'), 'http://192.168.1.20:8000');
      expect(cleaned('HTTP://MyPC:8000'), 'http://mypc:8000');
      expect(cleaned('https://sheets.example.com'), 'https://sheets.example.com');
      expect(cleaned('https://sheets.example.com:8443'), 'https://sheets.example.com:8443');
      expect(cleaned('http://[fe80::1]:8000'), 'http://[fe80::1]:8000');
    });

    test('refuses an empty address', () {
      expect(problem(''), AddressProblem.empty);
      expect(problem('   '), AddressProblem.empty);
    });

    test('refuses every way of writing localhost', () {
      for (final raw in [
        'localhost:8000',
        'http://localhost:8000',
        'http://LOCALHOST:8000',
        'http://app.localhost:8000',
        'http://127.0.0.1:8000',
        'http://127.1.2.3:8000',
        'http://[::1]:8000',
        'http://0.0.0.0:8000',
      ]) {
        expect(problem(raw), AddressProblem.loopback, reason: raw);
      }
    });

    test('plain http needs a port', () {
      expect(problem('http://192.168.1.20'), AddressProblem.missingPort);
      expect(problem('hello'), AddressProblem.missingPort);
    });

    test('nothing may follow the port', () {
      expect(problem('http://192.168.1.20:8000/api'), AddressProblem.hasPath);
      expect(problem('http://192.168.1.20:8000?x=1'), AddressProblem.hasPath);
      expect(problem('user@192.168.1.20:8000'), AddressProblem.hasPath);
    });

    test('refuses other kinds of address and impossible ports', () {
      expect(problem('ftp://192.168.1.20:8000'), AddressProblem.notWebAddress);
      expect(problem('http://192.168.1.20:99999'), AddressProblem.notWebAddress);
      expect(problem('http://192.168.1.20:0'), AddressProblem.notWebAddress);
    });

    test('every problem and result has a message for the user', () {
      for (final p in AddressProblem.values) {
        expect(addressProblemMessage(p), isNotEmpty);
      }
      for (final r in ConnectionTestResult.values) {
        expect(connectionResultMessage(r), isNotEmpty);
      }
      expect(addressProblemMessage(AddressProblem.loopback), contains('192.168'));
    });
  });

  group('ServerConnectionStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('has no address until the user enters one', () async {
      expect(await const ServerConnectionStore().load(), isNull);
    });

    test('saves and loads the address and token', () async {
      const store = ServerConnectionStore();

      expect(
        await store.save(
          const ServerConnection(address: 'http://192.168.1.20:8000', token: 'secret-token-123'),
        ),
        isTrue,
      );

      final loaded = await store.load();

      expect(loaded?.address, 'http://192.168.1.20:8000');
      expect(loaded?.token, 'secret-token-123');
    });

    test('a saved address without a token loads with an empty token', () async {
      SharedPreferences.setMockInitialValues({'server_address': 'http://192.168.1.20:8000'});

      expect((await const ServerConnectionStore().load())?.token, '');
    });

    test('a saved localhost address is ignored, so it can never be used', () async {
      SharedPreferences.setMockInitialValues({
        'server_address': 'http://localhost:8000',
        'server_token': 'x',
      });

      expect(await const ServerConnectionStore().load(), isNull);
    });

    test('a changed address replaces the old one', () async {
      const store = ServerConnectionStore();
      await store.save(const ServerConnection(address: 'http://10.0.0.5:8000'));
      await store.save(const ServerConnection(address: 'http://10.0.0.9:8001', token: 'new-token-1234'));

      final loaded = await store.load();

      expect(loaded?.address, 'http://10.0.0.9:8001');
      expect(loaded?.token, 'new-token-1234');
    });
  });

  group('testServerConnection', () {
    const healthy = '{"application":"Excelence","status":"running"}';

    Future<ConnectionTestResult> run(
      Future<http.Response> Function(http.Request) handler, {
      String token = '',
      Duration timeout = const Duration(seconds: 5),
    }) {
      return testServerConnection(
        address: 'http://192.168.1.20:8000',
        token: token,
        client: MockClient(handler),
        timeout: timeout,
      );
    }

    test('ok when an Excelence server answers', () async {
      http.Request? seen;

      final result = await run((request) async {
        seen = request;
        return http.Response(healthy, 200);
      });

      expect(result, ConnectionTestResult.ok);
      expect(seen!.url.toString(), 'http://192.168.1.20:8000/');
    });

    test('sends the token only when there is one', () async {
      final headers = <Map<String, String>>[];

      Future<http.Response> handler(http.Request request) async {
        headers.add(request.headers);
        return http.Response(healthy, 200);
      }

      await run(handler, token: 'secret-token-123');
      await run(handler);

      expect(headers[0]['Authorization'], 'Bearer secret-token-123');
      expect(headers[1].containsKey('Authorization'), isFalse);
    });

    test('wrong token when the server answers 401 or 403', () async {
      expect(await run((_) async => http.Response('no', 401)), ConnectionTestResult.wrongToken);
      expect(await run((_) async => http.Response('no', 403)), ConnectionTestResult.wrongToken);
    });

    test('not an Excelence server when something else answers', () async {
      expect(await run((_) async => http.Response('<html>router</html>', 200)), ConnectionTestResult.notExcelence);
      expect(await run((_) async => http.Response('', 404)), ConnectionTestResult.notExcelence);
      expect(await run((_) async => http.Response('', 500)), ConnectionTestResult.notExcelence);
    });

    test('unreachable when the request fails', () async {
      expect(
        await run((_) async => throw http.ClientException('connection refused')),
        ConnectionTestResult.unreachable,
      );
    });

    test('timed out when nothing answers', () async {
      final never = Completer<http.Response>();

      expect(
        await run((_) => never.future, timeout: const Duration(milliseconds: 20)),
        ConnectionTestResult.timedOut,
      );
    });
  });
}
