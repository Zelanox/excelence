/// Build-time options. The server address and access token are NOT set
/// here any more: the user enters them in the app (Settings > Connection)
/// and they are kept on the device, so one build works on any network.
class ApiConfig {
  const ApiConfig._();

  /// Optional: pre-fills the server address on a device that has none saved,
  /// for development (`--dart-define=API_BASE_URL=http://192.168.1.20:8000`).
  /// Empty by default - there is deliberately no localhost fallback.
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// The name other people see for this client when several share a
  /// document (`--dart-define=CLIENT_NAME=Sara`). Empty means "Guest".
  /// Shown by the server's /sessions listing today; a name-entry field in
  /// Settings can replace this later.
  static const String clientName = String.fromEnvironment('CLIENT_NAME');
}
