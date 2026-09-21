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
import '../widgets/sheet_tabs.dart';

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

    // Keep the viewport's valid row/column range in sync with whatever
    // sheet is currently active - this covers every path that can change
    // the grid's dimensions (row/column insert/delete, search, sheet
    // switch/add/delete) in one place, rather than duplicating a bounds
    // refresh into each feature that can trigger one. Individual features
    // (Toolbar, SpreadsheetGrid, the search bar) also call
    // setSheetBounds directly after their own mutations for immediate
    // feedback - setSheetBounds is a pure recompute, so the occasional
    // redundant call here is harmless.
    spreadsheetController.addListener(_syncViewportBounds);

    spreadsheetController.loadDocument('test.xlsx').then((_) {
      _syncViewportBounds();
    });
  }

  void _syncViewportBounds() {
    final spreadsheet = spreadsheetController.spreadsheet;
    if (spreadsheet == null) {
      return;
    }
    viewportController.setSheetBounds(
      rowCount: spreadsheet.activeSheet.rows.length,
      columnCount: spreadsheet.activeSheet.headers.length,
    );
  }

  @override
  void dispose() {
    spreadsheetController.removeListener(_syncViewportBounds);
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
            AppMenuBar(spreadsheetController: spreadsheetController),
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
            SheetTabs(spreadsheetController: spreadsheetController),
            const StatusBar(),
          ],
        ),
      ),
    );
  }
}