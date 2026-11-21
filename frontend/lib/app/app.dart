import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'branded_loading_screen.dart';
import '../core/connection/connection_scope.dart';
import '../core/connection/server_connection.dart';
import '../core/preferences/app_preferences.dart';
import '../features/shell/presentation/shell_page.dart';
import '../features/shell/widgets/connection_form.dart';
import 'theme.dart';

class ExcelenceApp extends StatefulWidget {
  const ExcelenceApp({super.key});

  @override
  State<ExcelenceApp> createState() => _ExcelenceAppState();
}

class _ExcelenceAppState extends State<ExcelenceApp> {
  Locale _locale = const Locale('en');

  /// The server this device talks to; null until the user enters one.
  ServerConnection? _connection;
  bool _connectionLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadConnection();
  }

  Future<void> _loadConnection() async {
    final connection = await const ServerConnectionStore().load();

    if (!mounted) {
      return;
    }

    setState(() {
      _connection = connection;
      _connectionLoaded = true;
    });
  }

  /// Starts using a new server address. The whole shell is rebuilt (it is
  /// keyed by the connection), so nothing keeps talking to the old server.
  Future<void> _changeConnection(ServerConnection connection) async {
    final saved = await const ServerConnectionStore().save(connection);

    if (!saved) {
      debugPrint(
        '[Connection] not stored; it will have to be entered again next time',
      );
    }

    if (mounted) {
      setState(() => _connection = connection);
    }
  }

  Future<void> _setLocale(Locale locale) async {
    setState(() => _locale = locale);
    await const AppPreferences().setInterfaceLanguage(locale.languageCode);
  }

  Widget _home() {
    if (!_connectionLoaded) {
      return const BrandedLoadingScreen();
    }

    final connection = _connection;

    if (connection == null) {
      return const ConnectScreen();
    }

    return ShellPage(
      key: ValueKey('${connection.address}|${connection.token}'),
      connection: connection,
      onLocaleChanged: _setLocale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConnectionScope(
      connection: _connection,
      change: _changeConnection,
      child: MaterialApp(
        title: 'Excelence',
        debugShowCheckedModeBanner: false,
        theme: excelenceTheme,
        locale: _locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: _home(),
      ),
    );
  }
}
