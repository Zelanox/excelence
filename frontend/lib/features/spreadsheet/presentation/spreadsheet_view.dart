import 'package:flutter/material.dart';

import 'widgets/spreadsheet_grid.dart';
import 'widgets/sheet_tabs.dart';

class SpreadsheetView extends StatelessWidget {
  const SpreadsheetView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(
          child: SpreadsheetGrid(),
        ),

        SheetTabs(),
      ],
    );
  }
}