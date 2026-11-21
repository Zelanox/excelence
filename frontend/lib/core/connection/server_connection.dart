import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';

/// Where this device finds the Excelence server, and the access token it
/// uses. Stored on THIS device (never on the server: the app needs the
/// address before it can ask the server for anything).
@immutable
class ServerConnection {
  const ServerConnection({required this.address, this.token = ''});

  /// Like `http://192.168.1.20:8000` (see [checkServerAddress]).
  final String address;

  /// The server's access token, or '' when the server has none.
  final String token;

  @override
  bool operator ==(Object other) =>
      other is ServerConnection &&
      other.address == address &&
      other.token == token;

  @override
  int get hashCode => Object.hash(address, token);
}

/// Why an address typed by the user cannot be used.
enum AddressProblem { empty, notWebAddress, loopback, missingPort, hasPath }

class AddressCheck {
  const AddressCheck.valid(String this.address) : problem = null;
  const AddressCheck.invalid(AddressProblem this.problem) : address = null;

  /// The cleaned-up address, when valid.
  final String? address;
  final AddressProblem? problem;

  bool get isValid => problem == null;
}

/// True for names that only ever mean "this device".
bool isLoopbackHost(String host) {
  final h = host.toLowerCase();

  if (h == 'localhost' ||
      h.endsWith('.localhost') ||
      h == '::1' ||
      h == '::' ||
      h == '0.0.0.0') {
    return true;
  }

  return RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(h);
}

final RegExp _explicitPort = RegExp(
  r'^[a-z][a-z0-9+.-]*://(?:\[[^\]]*\]|[^:/\[\]]*):(\d+)$',
  caseSensitive: false,
);

/// Checks and cleans an address typed by the user.
///
/// * a missing `http://` is added (`192.168.1.20:8000` works);
/// * `localhost`, `127.x.x.x`, `::1` and `0.0.0.0` are refused: they point at
///   the device itself, not at the PC that runs the server;
/// * plain `http` needs an explicit port; nothing may follow the port.
AddressCheck checkServerAddress(String raw) {
  var text = raw.trim();

  if (text.isEmpty) {
    return const AddressCheck.invalid(AddressProblem.empty);
  }

  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }

  if (!text.contains('://')) {
    text = 'http://$text';
  }

  final uri = Uri.tryParse(text);

  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return const AddressCheck.invalid(AddressProblem.notWebAddress);
  }

  if (uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return const AddressCheck.invalid(AddressProblem.hasPath);
  }

  final host = uri.host.toLowerCase();

  if (isLoopbackHost(host)) {
    return const AddressCheck.invalid(AddressProblem.loopback);
  }

  final match = _explicitPort.firstMatch(text);

  if (match == null && uri.scheme == 'http') {
    return const AddressCheck.invalid(AddressProblem.missingPort);
  }

  int? port;

  if (match != null) {
    port = int.tryParse(match.group(1)!);

    if (port == null || port < 1 || port > 65535) {
      return const AddressCheck.invalid(AddressProblem.notWebAddress);
    }
  }

  final shownHost = host.contains(':') ? '[$host]' : host;

  return AddressCheck.valid(
    '${uri.scheme}://$shownHost${port == null ? '' : ':$port'}',
  );
}

/// What to tell the user about an address that cannot be used.
String addressProblemMessage(AddressProblem problem) {
  switch (problem) {
    case AddressProblem.empty:
      return 'Enter the server address.';
    case AddressProblem.notWebAddress:
      return 'That is not a valid address. Example: http://192.168.1.20:8000';
    case AddressProblem.loopback:
      return "localhost cannot be used. Enter the network address of the PC that runs the server, for example http://192.168.1.20:8000";
    case AddressProblem.missingPort:
      return 'Add the port number. Example: http://192.168.1.20:8000';
    case AddressProblem.hasPath:
      return 'Enter only the address and the port, with nothing after them.';
  }
}

/// Keeps the address and token on this device.
class ServerConnectionStore {
  const ServerConnectionStore();

  static const _addressKey = 'server_address';
  static const _tokenKey = 'server_token';

  /// The saved connection, or - only when nothing valid is saved - an
  /// address given at build time (`--dart-define=API_BASE_URL=...`), or null
  /// when the user still has to enter one. There is no default address.
  Future<ServerConnection?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString(_addressKey);

      if (address != null && checkServerAddress(address).isValid) {
        return ServerConnection(
          address: address,
          token: prefs.getString(_tokenKey) ?? '',
        );
      }
    } catch (error) {
      debugPrint('[Connection] could not read the saved address: $error');
    }

    final preset = checkServerAddress(ApiConfig.baseUrl);

    return preset.isValid ? ServerConnection(address: preset.address!) : null;
  }

  /// Returns false if the device could not store it.
  Future<bool> save(ServerConnection connection) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAddress =
          await prefs.setString(_addressKey, connection.address);
      final savedToken = await prefs.setString(_tokenKey, connection.token);

      return savedAddress && savedToken;
    } catch (error) {
      debugPrint('[Connection] could not save the address: $error');

      return false;
    }
  }
}

/// Raised by whoever applies a new connection when it must not go ahead;
/// [message] is shown to the user as it is.
class ConnectionChangeBlocked implements Exception {
  const ConnectionChangeBlocked(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ConnectionTestResult { ok, unreachable, timedOut, wrongToken, notExcelence }

/// What to tell the user about a connection test.
String connectionResultMessage(ConnectionTestResult result) {
  switch (result) {
    case ConnectionTestResult.ok:
      return 'Connected to the Excelence server.';
    case ConnectionTestResult.unreachable:
      return 'Cannot reach the server. Check that it is running, that this device is on the same network, and that the address is right.';
    case ConnectionTestResult.timedOut:
      return 'The server did not answer in time. Check the address and the network, then try again.';
    case ConnectionTestResult.wrongToken:
      return 'The server refused the access token. Check the token and try again.';
    case ConnectionTestResult.notExcelence:
      return 'Something answered, but it is not an Excelence server. Check the address and the port.';
  }
}

/// Asks the server at [address] its health question, with [token].
Future<ConnectionTestResult> testServerConnection({
  required String address,
  String token = '',
  http.Client? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final session = client ?? http.Client();

  try {
    final response = await session
        .get(
          Uri.parse('$address/'),
          headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
        )
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      return ConnectionTestResult.wrongToken;
    }

    if (response.statusCode == 200 && response.body.contains('Excelence')) {
      return ConnectionTestResult.ok;
    }

    return ConnectionTestResult.notExcelence;
  } on TimeoutException {
    return ConnectionTestResult.timedOut;
  } catch (error) {
    debugPrint('[Connection] test failed: $error');

    return ConnectionTestResult.unreachable;
  } finally {
    if (client == null) {
      session.close();
    }
  }
}
