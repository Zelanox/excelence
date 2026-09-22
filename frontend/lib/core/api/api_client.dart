import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    required this.baseUrl,
  });

  final String baseUrl;

  Future<http.Response> get(String endpoint) {
    return http.get(
      Uri.parse('$baseUrl$endpoint'),
    );
  }

  Future<http.Response> post(
    String endpoint, {
    Object? body,
  }) {
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> put(
    String endpoint, {
    Object? body,
  }) {
    return http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint) {
    return http.delete(
      Uri.parse('$baseUrl$endpoint'),
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
      Uri.parse('$baseUrl$endpoint'),
    )..files.add(
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