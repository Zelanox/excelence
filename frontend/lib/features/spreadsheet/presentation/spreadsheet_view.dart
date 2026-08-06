import 'package:flutter/material.dart';

import 'widgets/spreadsheet_grid.dart';
import 'widgets/sheet_tabs.dart';
import '../controllers/spreadsheet_controller.dart';

class SpreadsheetView extends StatelessWidget {
  const SpreadsheetView({super.key, required this.controller,});

  final SpreadsheetController controller;

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