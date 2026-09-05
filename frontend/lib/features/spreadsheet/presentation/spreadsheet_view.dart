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
    required this.focusNode,
  });

  final SpreadsheetController controller;
  final ViewportController viewportController;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final spreadsheet = controller.spreadsheet;

        // The controller hasn't loaded a spreadsheet yet.
        if (spreadsheet == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        return Column(
          children: [
            Expanded(
              child: SpreadsheetViewport(
                viewportController: viewportController,
                focusNode: focusNode,
                spreadsheetController: controller,
                spreadsheet: spreadsheet,
              ),
            ),

            const SheetTabs(),
          ],
        );
      },
    );
  }
}