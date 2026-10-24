import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../live/live_address.dart';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.accessToken,
    this.clientName,
    String? clientId,
  }) : clientId = clientId ?? _newClientId();

  final String baseUrl;

  /// Identifies THIS running copy of the app to the server (a fresh random
  /// id each launch, so two tabs are two clients). Sent on every request as
  /// `X-Client-Id`; it is what lets the server put several people in one
  /// shared document and tell them apart. 24 hex characters, which fits the
  /// server's 8-64 letters/digits/-/_ rule.
  final String clientId;

  /// How this client is shown to others in a shared document. Sent
  /// percent-encoded (HTTP headers are ASCII; names may not be) as
  /// `X-Client-Name`. Null/blank means the server shows "Guest".
  String? clientName;

  /// The id of the shared document session this client is in, handed back
  /// by the server when a document is opened. Sent as `X-Document` so every
  /// later request runs against that document. Null before a document is
  /// open - and always null against a server that doesn't have sessions,
  /// which then simply behaves as it always did.
  String? documentSession;

  static String _newClientId() {
    final random = Random.secure();

    return List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Sent as `Authorization: Bearer <token>` on every request when set -
  /// needed when the server was started with EXCELENCE_ACCESS_TOKEN.
  final String? accessToken;

  /// [baseUrl] without a trailing slash, so `$_root/endpoint` never
  /// produces a double slash when someone configures "http://host:8000/".
  String get _root =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Map<String, String> _headers({bool json = false}) {
    final token = accessToken;

    final name = clientName?.trim();
    final session = documentSession;

    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'X-Client-Id': clientId,
      if (name != null && name.isNotEmpty)
        'X-Client-Name': Uri.encodeComponent(name),
      if (session != null && session.isNotEmpty) 'X-Document': session,
    };
  }

  /// Called when a request that can change the document is sent, and when it
  /// has finished (successfully or not). Live collaboration uses this to hold
  /// off reloading the document while this client's own change is on its way.
  void Function()? onWriteStarted;
  void Function()? onWriteFinished;

  Future<T> _tracked<T>(Future<T> Function() send) async {
    onWriteStarted?.call();

    try {
      return await send();
    } finally {
      onWriteFinished?.call();
    }
  }

  /// The address of the live (WebSocket) connection for the document this
  /// client is in, catching up from [since]. Throws if no document is open.
  Uri liveUri({required int since}) {
    final session = documentSession;

    if (session == null || session.isEmpty) {
      throw StateError('No document is open.');
    }

    return liveAddress(
      baseUrl: baseUrl,
      document: session,
      clientId: clientId,
      name: clientName,
      since: since,
      token: accessToken,
    );
  }

  /// Called when the server answers that it no longer has this client's
  /// document open (it was restarted, or forgot it). The app should open the
  /// document again.
  void Function()? onSessionLost;

  Future<http.Response> _checked(Future<http.Response> request) async {
    final response = await request;

    if (isSessionLostResponse(response.statusCode, response.body)) {
      onSessionLost?.call();
    }

    return response;
  }

  Future<http.Response> get(String endpoint) {
    return _checked(
      http.get(
        Uri.parse('$_root$endpoint'),
        headers: _headers(),
      ),
    );
  }

  Future<http.Response> post(
    String endpoint, {
    Object? body,
  }) {
    return _tracked(
      () => _checked(
        http.post(
          Uri.parse('$_root$endpoint'),
          headers: _headers(json: true),
          body: body == null ? null : jsonEncode(body),
        ),
      ),
    );
  }

  Future<http.Response> put(
    String endpoint, {
    Object? body,
  }) {
    return _tracked(
      () => _checked(
        http.put(
          Uri.parse('$_root$endpoint'),
          headers: _headers(json: true),
          body: body == null ? null : jsonEncode(body),
        ),
      ),
    );
  }

  Future<http.Response> delete(String endpoint) {
    return _tracked(
      () => _checked(
        http.delete(
          Uri.parse('$_root$endpoint'),
          headers: _headers(),
        ),
      ),
    );
  }

  /// Uploads raw file bytes as multipart/form-data under the field name
  /// "file" - matching the backend's `UploadFile = File(...)` parameter
  /// name in POST /documents/upload. Separate from post() because a
  /// JSON body and a multipart body are fundamentally different request
  /// shapes; http.MultipartRequest builds its own headers/boundary and
  /// can't be expressed through the jsonEncode(body) path above.
  Future<http.Response> uploadFile(
    String endpoint, {
    required List<int> bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_root$endpoint'),
    )
      ..headers.addAll(_headers())
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
        ),
      );

    return _tracked(() async {
      final streamedResponse = await request.send();
      return http.Response.fromStream(streamedResponse);
    });
  }
}

/// Whether an answer from the server means "I no longer have your document
/// open" (409 with the `SESSION_NOT_OPEN` code), as after a server restart.
bool isSessionLostResponse(int statusCode, String body) {
  return statusCode == 409 && body.contains('SESSION_NOT_OPEN');
}
