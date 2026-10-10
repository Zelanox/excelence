/// Where the client finds the server, fixed at BUILD time with
/// `--dart-define` so the same code runs against a local server or a shared
/// one without edits:
///
///     flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.20:8000
///     flutter build web --dart-define=API_BASE_URL=https://sheets.example.com
///
/// With no flags it talks to a server on this machine, as before.
class ApiConfig {
  const ApiConfig._();

  /// Base URL of the Excelence server, with no trailing path.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// The server's shared access token (its EXCELENCE_ACCESS_TOKEN), or ''
  /// when the server doesn't require one.
  ///
  /// NOTE: a value passed with --dart-define is compiled into the client,
  /// so anyone who can load the app can read it. It keeps strangers on the
  /// network out of a trusted team's server; it is not per-user login.
  static const String accessToken = String.fromEnvironment('API_TOKEN');
}
