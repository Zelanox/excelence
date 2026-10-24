/// The server accepts display names of at most this many characters.
const int maxLiveNameLength = 40;

/// The WebSocket address for a document, built from the server's normal
/// base URL (`http://host:8000` becomes `ws://host:8000`, `https` becomes
/// `wss`). Parameters are percent-encoded by [Uri].
///
/// The access token travels in the address because browsers cannot set
/// headers on a WebSocket; see docs/COLLABORATION.md ("The access token on a
/// WebSocket") for what that means for logs.
Uri liveAddress({
  required String baseUrl,
  required String document,
  required String clientId,
  String? name,
  int since = 0,
  String? token,
}) {
  final base = Uri.parse(baseUrl);
  final path = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final cleanName = _cleanName(name);

  return Uri(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '$path/spreadsheet/live',
    queryParameters: {
      'document': document,
      'client': clientId,
      if (cleanName.isNotEmpty) 'name': cleanName,
      'since': '$since',
      if (token != null && token.isNotEmpty) 'token': token,
    },
  );
}

String _cleanName(String? name) {
  final trimmed = name?.trim() ?? '';

  if (trimmed.runes.length <= maxLiveNameLength) {
    return trimmed;
  }

  return String.fromCharCodes(trimmed.runes.take(maxLiveNameLength)).trim();
}
