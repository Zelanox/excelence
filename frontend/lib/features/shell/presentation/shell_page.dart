import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../../spreadsheet/services/spreadsheet_service.dart';
import '../widgets/app_menu_bar.dart';
import '../widgets/workspace.dart';
import '../widgets/status_bar.dart';
import '../widgets/toolbar.dart';
import '../widgets/search_bar.dart';

/// Owns the SpreadsheetController and ViewportController for the whole
/// shell. These used to be created privately inside SpreadsheetFeatureV2,
/// but Toolbar (a sibling of Workspace here, not a descendant of it) also
/// needs access to the same controller instances - it reads the current
/// selection and triggers insert/delete row/column operations. Lifting
/// ownership up here lets both widgets share the same controllers rather
/// than each having their own disconnected copy.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
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
      body: SafeArea(
        child: Column(
          children: [
            const AppMenuBar(),
            Toolbar(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
            ),
            SpreadsheetSearchBar(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
            ),
            Workspace(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
            ),
            const StatusBar(),
          ],
        ),
      ),
    );
  }
}
