import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/spreadsheet/models/file_action_result.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

/// Round B2: the three File menu calls turn every kind of answer into a
/// result with a message the user can read. No real server is involved; the
/// HTTP client is replaced.

class Call {
  Call(this.method, this.path, this.body);

  final String method;
  final String path;
  final Object? body;
}

Future<(FileActionResult, List<Call>, ApiClient)> run(
  Future<FileActionResult> Function(SpreadsheetService service) action,
  http.Response Function(http.Request request) answer, {
  String? session = 'old-session',
}) async {
  final calls = <Call>[];
  final api = ApiClient(baseUrl: 'http://server:8000/')..documentSession = session;
  final service = SpreadsheetService(api);

  final result = await http.runWithClient(
    () => action(service),
    () => MockClient((request) async {
      calls.add(
        Call(
          request.method,
          request.url.path,
          request.body.isEmpty ? null : jsonDecode(request.body),
        ),
      );
      return answer(request);
    }),
  );

  return (result, calls, api);
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('saveAs posts the new name and returns the name the server used', () async {
    final (result, calls, api) = await run(
      (service) => service.saveAs('copy.xlsx'),
      (_) => json({'success': true, 'filename': 'book.xlsx', 'new_name': 'copy.xlsx'}),
    );

    expect(result.ok, isTrue);
    expect(result.name, 'copy.xlsx');
    expect(calls.single.method, 'POST');
    expect(calls.single.path, '/documents/save-as');
    expect(calls.single.body, {'new_name': 'copy.xlsx'});
    expect(api.documentSession, 'old-session'); // Save as does not end the session
  });

  test('a refusal passes the server message through unchanged', () async {
    final (result, _, _) = await run(
      (service) => service.saveAs('copy.xlsx'),
      (_) => json({
        'success': false,
        'message': 'A document named copy.xlsx already exists. Choose another name.',
      }),
    );

    expect(result.ok, isFalse);
    expect(result.message, 'A document named copy.xlsx already exists. Choose another name.');
    expect(result.saveFailed, isFalse);
  });

  test('a refusal with no message still says something', () async {
    final (result, _, _) = await run(
      (service) => service.saveAs('copy.xlsx'),
      (_) => json({'success': false}),
    );

    expect(result.ok, isFalse);
    expect(result.message, isNotEmpty);
  });

  test('renameOpen succeeds, forgets the closed session and returns the new name', () async {
    final (result, calls, api) = await run(
      (service) => service.renameOpen('new.xlsx'),
      (_) => json({'success': true, 'old_name': 'book.xlsx', 'new_name': 'new.xlsx'}),
    );

    expect(result.ok, isTrue);
    expect(result.name, 'new.xlsx');
    expect(calls.single.path, '/documents/rename-open');
    expect(calls.single.body, {'new_name': 'new.xlsx'});
    expect(api.documentSession, isNull);
  });

  test('a refused rename keeps the session', () async {
    final (result, _, api) = await run(
      (service) => service.renameOpen('new.xlsx'),
      (_) => json({
        'success': false,
        'message': 'Other people are working in this document. Ask them to leave first.',
      }),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('Other people'));
    expect(api.documentSession, 'old-session');
  });

  test('deleteOpen sends no body, returns the deleted name and forgets the session', () async {
    final (result, calls, api) = await run(
      (service) => service.deleteOpen(),
      (_) => json({'success': true, 'filename': 'book.xlsx'}),
    );

    expect(result.ok, isTrue);
    expect(result.name, 'book.xlsx');
    expect(calls.single.path, '/documents/delete-open');
    expect(calls.single.body, isNull);
    expect(api.documentSession, isNull);
  });

  test('a refused delete keeps the session', () async {
    final (result, _, api) = await run(
      (service) => service.deleteOpen(),
      (_) => json({'success': false, 'message': 'Could not delete the document.'}),
    );

    expect(result.ok, isFalse);
    expect(api.documentSession, 'old-session');
  });

  test('HTTP 409 means the document is no longer open on the server', () async {
    final (result, _, _) = await run(
      (service) => service.saveAs('copy.xlsx'),
      (_) => json({'detail': 'SESSION_NOT_OPEN: that document is no longer open on the server'}, 409),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('no longer open'));
    expect(result.message, isNot(contains('SESSION_NOT_OPEN')));
  });

  test('another HTTP error gives a friendly message with the code, not the body', () async {
    final (result, _, _) = await run(
      (service) => service.renameOpen('new.xlsx'),
      (_) => http.Response('<html>Traceback (most recent call last)</html>', 500),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('500'));
    expect(result.message, isNot(contains('Traceback')));
    expect(result.message, isNot(contains('<html>')));
  });

  test('an unreadable answer is reported as such', () async {
    for (final body in ['not json', '[1, 2]', '']) {
      final (result, _, _) = await run(
        (service) => service.saveAs('copy.xlsx'),
        (_) => http.Response(body, 200),
      );

      expect(result.ok, isFalse, reason: 'body: $body');
      expect(result.message, contains('could not be read'), reason: 'body: $body');
    }
  });

  test('no connection gives the connection message, never an exception', () async {
    final calls = <Call>[];
    final api = ApiClient(baseUrl: 'http://server:8000')..documentSession = 's';

    final results = await http.runWithClient(
      () async => [
        await SpreadsheetService(api).saveAs('a.xlsx'),
        await SpreadsheetService(api).renameOpen('a.xlsx'),
        await SpreadsheetService(api).deleteOpen(),
      ],
      () => MockClient((request) async {
        calls.add(Call(request.method, request.url.path, null));
        throw http.ClientException('Connection refused');
      }),
    );

    expect(calls, hasLength(3));

    for (final result in results) {
      expect(result.ok, isFalse);
      expect(result.message, contains("Can't reach the server"));
    }

    expect(api.documentSession, 's');
  });
}
