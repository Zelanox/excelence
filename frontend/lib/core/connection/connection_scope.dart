import 'package:flutter/widgets.dart';

import 'server_connection.dart';

/// Gives every screen the current server connection and a way to change it.
/// Sits above the whole app so dialogs can reach it too.
class ConnectionScope extends InheritedWidget {
  const ConnectionScope({
    super.key,
    required this.connection,
    required this.change,
    required super.child,
    this.savedOnDevice = true,
  });

  /// Null until the user has entered a server address.
  final ServerConnection? connection;

  /// False while the address in use only comes from the build-time pre-fill
  /// and has not been saved on this device.
  final bool savedOnDevice;

  /// Saves and starts using [connection]; the open document screen is rebuilt
  /// against the new server. May throw [ConnectionChangeBlocked].
  final Future<void> Function(ServerConnection connection) change;

  static ConnectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectionScope>();

  @override
  bool updateShouldNotify(ConnectionScope oldWidget) =>
      connection != oldWidget.connection ||
      savedOnDevice != oldWidget.savedOnDevice;
}
