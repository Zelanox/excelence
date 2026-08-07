import 'package:flutter/material.dart';
import 'package:frontend/features/spreadsheet/presentation/widgets/viewport/spreadsheet_viewport.dart';

import 'widgets/sheet_tabs.dart';
import '../controllers/spreadsheet_controller.dart';
import '../controllers/viewport_controller.dart';

class SpreadsheetView extends StatelessWidget {
  const SpreadsheetView({
    super.key,
    required this.controller,
    required this.viewportController,
    });

  final SpreadsheetController controller;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SpreadsheetViewport(
            viewportController: viewportController,
          ),
        ),

        SheetTabs(),
      ],
    );
  }
}