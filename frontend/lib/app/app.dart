import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/preferences/app_preferences.dart';
import '../features/shell/presentation/shell_page.dart';
import 'theme.dart';

class ExcelenceApp extends StatefulWidget {
  const ExcelenceApp({super.key});

  @override
  State<ExcelenceApp> createState() => _ExcelenceAppState();
}

class _ExcelenceAppState extends State<ExcelenceApp> {
  Locale _locale = const Locale('en');

  Future<void> _setLocale(Locale locale) async {
    setState(() => _locale = locale);
    await const AppPreferences().setInterfaceLanguage(locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Excelence',
      debugShowCheckedModeBanner: false,
      theme: excelenceTheme,
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ShellPage(onLocaleChanged: _setLocale),
    );
  }
}
