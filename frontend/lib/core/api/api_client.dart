import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    required this.baseUrl,
  });

  final String baseUrl;

  Future<http.Response> get(String endpoint) {
    return http.get(Uri.parse('$baseUrl$endpoint'));
  }

  Future<http.Response> post(
    String endpoint, {
    Object? body,
  }) {
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      body: body,
    );
  }

  Future<http.Response> put(
    String endpoint, {
    Object? body,
  }) {
    return http.put(
      Uri.parse('$baseUrl$endpoint'),
      body: body,
    );
  }

  Future<http.Response> delete(String endpoint) {
    return http.delete(Uri.parse('$baseUrl$endpoint'));
  }
}