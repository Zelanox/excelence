import 'package:flutter/material.dart';
import 'package:frontend/features/spreadsheet/presentation/widgets/viewport/spreadsheet_viewport.dart';

import 'widgets/sheet_tabs.dart';
import '../controllers/spreadsheet_controller.dart';

class SpreadsheetView extends StatelessWidget {
  const SpreadsheetView({super.key, required this.controller,});

  final SpreadsheetController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SpreadsheetViewport(),
        ),

        SheetTabs(),
      ],
    );
  }
}