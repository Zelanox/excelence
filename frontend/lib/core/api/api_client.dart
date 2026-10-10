import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.accessToken,
  });

  final String baseUrl;

  /// Sent as `Authorization: Bearer <token>` on every request when set -
  /// needed when the server was started with EXCELENCE_ACCESS_TOKEN.
  final String? accessToken;

  /// [baseUrl] without a trailing slash, so `$_root/endpoint` never
  /// produces a double slash when someone configures "http://host:8000/".
  String get _root =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Map<String, String> _headers({bool json = false}) {
    final token = accessToken;

    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(String endpoint) {
    return http.get(
      Uri.parse('$_root$endpoint'),
      headers: _headers(),
    );
  }

  Future<http.Response> post(
    String endpoint, {
    Object? body,
  }) {
    return http.post(
      Uri.parse('$_root$endpoint'),
      headers: _headers(json: true),
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> put(
    String endpoint, {
    Object? body,
  }) {
    return http.put(
      Uri.parse('$_root$endpoint'),
      headers: _headers(json: true),
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint) {
    return http.delete(
      Uri.parse('$_root$endpoint'),
      headers: _headers(),
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

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }
}
