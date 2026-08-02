import 'package:flutter/material.dart';

import '../features/home/presentation/home_page.dart';
import 'theme.dart';

class ExcelenceApp extends StatelessWidget {
  const ExcelenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Excelence',

      debugShowCheckedModeBanner: false,

      theme: excelenceTheme,

      home: const HomePage(),
    );
  }
}