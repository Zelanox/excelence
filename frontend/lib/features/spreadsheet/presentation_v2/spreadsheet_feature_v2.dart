import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../controllers/spreadsheet_controller.dart';
import '../controllers/viewport_controller.dart';
import '../services/spreadsheet_service.dart';
import 'widgets/spreadsheet_grid.dart';

/// The new (v2) spreadsheet feature, embedded directly inside the app's
/// existing shell (menu bar / toolbar / status bar) - this is the v2
/// counterpart to SpreadsheetFeature (v1), and is what Workspace embeds
/// now that v2 is the active UI.
///
/// Unlike SpreadsheetScreenV2 (which wraps itself in its own Scaffold +
/// AppBar for standalone route-based testing), this widget assumes it is
/// already inside a Scaffold provided by ShellPage, and renders only the
/// spreadsheet content itself.
class SpreadsheetFeatureV2 extends StatefulWidget {
  const SpreadsheetFeatureV2({super.key});

  @override
  State<SpreadsheetFeatureV2> createState() => _SpreadsheetFeatureV2State();
}

class _SpreadsheetFeatureV2State extends State<SpreadsheetFeatureV2> {
  late final SpreadsheetController spreadsheetController;
  late final ViewportController viewportController;

  @override
  void initState() {
    super.initState();

    final api = ApiClient(baseUrl: 'http://localhost:8000');
    final service = SpreadsheetService(api);

    spreadsheetController = SpreadsheetController(service);
    viewportController = ViewportController();

    spreadsheetController.loadDocument('test.xlsx').then((_) {
      final spreadsheet = spreadsheetController.spreadsheet;
      if (spreadsheet == null) {
        return;
      }
      viewportController.setSheetBounds(
        rowCount: spreadsheet.activeSheet.rows.length,
        columnCount: spreadsheet.activeSheet.rows.isEmpty
            ? 0
            : spreadsheet.activeSheet.rows.first.cells.length,
      );
    });
  }

  @override
  void dispose() {
    spreadsheetController.dispose();
    viewportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpreadsheetGrid(
      spreadsheetController: spreadsheetController,
      viewportController: viewportController,
    );
  }
}
