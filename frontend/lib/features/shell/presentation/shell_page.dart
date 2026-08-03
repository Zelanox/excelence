import 'package:flutter/material.dart';

import '../widgets/app_menu_bar.dart';
import '../widgets/formula_bar.dart';
import '../widgets/workspace.dart';
import '../widgets/status_bar.dart';
import '../widgets/toolbar.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppMenuBar(),
            Toolbar(),
            FormulaBar(),
            SpreadsheetPlaceholder(),
            StatusBar(),
          ],
        ),
      ),
    );
  }
}