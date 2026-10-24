import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/live/live_address.dart';

void main() {
  test('http becomes ws and keeps the port', () {
    final uri = liveAddress(
      baseUrl: 'http://192.168.1.5:8000',
      document: 'abc123',
      clientId: 'client-alice-0001',
      name: 'Alice',
      since: 12,
    );

    expect(uri.scheme, 'ws');
    expect(uri.host, '192.168.1.5');
    expect(uri.port, 8000);
    expect(uri.path, '/spreadsheet/live');
    expect(uri.queryParameters, {
      'document': 'abc123',
      'client': 'client-alice-0001',
      'name': 'Alice',
      'since': '12',
    });
  });

  test('https becomes wss', () {
    final uri = liveAddress(
      baseUrl: 'https://sheets.example.com',
      document: 'd',
      clientId: 'client-alice-0001',
    );

    expect(uri.scheme, 'wss');
    expect(uri.host, 'sheets.example.com');
  });

  test('a trailing slash or a path prefix on the base is handled', () {
    final slash = liveAddress(
      baseUrl: 'http://localhost:8000/',
      document: 'd',
      clientId: 'client-alice-0001',
    );
    final prefix = liveAddress(
      baseUrl: 'http://localhost:8000/excelence/',
      document: 'd',
      clientId: 'client-alice-0001',
    );

    expect(slash.path, '/spreadsheet/live');
    expect(prefix.path, '/excelence/spreadsheet/live');
  });

  test('since defaults to 0 and a missing or empty name or token is left out', () {
    final uri = liveAddress(
      baseUrl: 'http://localhost:8000',
      document: 'd',
      clientId: 'client-alice-0001',
      name: '   ',
      token: '',
    );

    expect(uri.queryParameters, {
      'document': 'd',
      'client': 'client-alice-0001',
      'since': '0',
    });
  });

  test('an Arabic name and a token with special characters survive encoding', () {
    final uri = liveAddress(
      baseUrl: 'http://localhost:8000',
      document: 'd',
      clientId: 'client-salma-0002',
      name: 'سلمى أحمد',
      token: 'a b&c=d/é',
    );

    final parsed = Uri.parse(uri.toString());

    expect(parsed.queryParameters['name'], 'سلمى أحمد');
    expect(parsed.queryParameters['token'], 'a b&c=d/é');
  });

  test('a name longer than the server accepts is cut to 40 characters', () {
    final uri = liveAddress(
      baseUrl: 'http://localhost:8000',
      document: 'd',
      clientId: 'client-alice-0001',
      name: 'x' * 60,
    );

    expect(uri.queryParameters['name'], 'x' * maxLiveNameLength);
  });
}
