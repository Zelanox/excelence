import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../controllers/spreadsheet_controller.dart';
import '../controllers/viewport_controller.dart';
import '../services/spreadsheet_service.dart';
import 'widgets/spreadsheet_grid.dart';

/// Entry point for the new (v2) spreadsheet UI.
///
/// This wires up its OWN controllers, exactly the same way
/// SpreadsheetFeature (the current/v1 screen) does - same ApiClient, same
/// SpreadsheetService, same loadDocument('test.xlsx') call. This is
/// intentional: v2 is not sharing a live controller instance with v1, so
/// navigating between the two screens is a clean mount/unmount each time,
/// with no risk of one screen's listeners interfering with the other's.
///
/// This screen (and everything under presentation_v2/) is not referenced
/// by app.dart or the shell yet - it is only reachable via the "Try new
/// UI" test route added to ShellPage, so the current app is completely
/// unaffected until this is deliberately swapped in.
class SpreadsheetScreenV2 extends StatefulWidget {
  const SpreadsheetScreenV2({super.key});

  @override
  State<SpreadsheetScreenV2> createState() => _SpreadsheetScreenV2State();
}

class _SpreadsheetScreenV2State extends State<SpreadsheetScreenV2> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excelence (New UI - work in progress)'),
      ),
      body: SpreadsheetGrid(
        spreadsheetController: spreadsheetController,
        viewportController: viewportController,
      ),
    );
  }
}
