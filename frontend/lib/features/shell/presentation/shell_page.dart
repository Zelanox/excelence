import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/preferences/app_preferences.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../../spreadsheet/services/spreadsheet_service.dart';
import '../widgets/app_menu_bar.dart';
import '../widgets/workspace.dart';
import '../widgets/status_bar.dart';
import '../widgets/toolbar.dart';
import '../widgets/search_bar.dart';
import '../widgets/sheet_tabs.dart';

/// The document opened automatically on first launch, before any
/// document has ever been successfully opened/created and recorded via
/// AppPreferences.setLastOpenedDocument.
const _defaultDocument = 'test.xlsx';

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

    _loadInitialDocument();
  }

  /// Opens the last document the user had open (recorded whenever
  /// loadDocument succeeds), or falls back to _defaultDocument if none
  /// is recorded yet (first run) or the remembered one can no longer be
  /// opened (e.g. it was deleted/moved since). The fallback itself is
  /// still surfaced to the user via loadDocument's normal error path if
  /// IT also fails - this only guards the one retry, not indefinitely.
  Future<void> _loadInitialDocument() async {
    final lastOpened = await const AppPreferences().getLastOpenedDocument();

    if (!mounted) return;

    final target = lastOpened ?? _defaultDocument;

    try {
      await spreadsheetController.loadDocument(target);
    } catch (_) {
      // The remembered document may no longer exist. Only retry with
      // the default if we weren't already trying it - otherwise this
      // would silently mask a real failure to open the default itself.
      if (target != _defaultDocument) {
        try {
          await spreadsheetController.loadDocument(_defaultDocument);
        } catch (_) {
          // Swallow here too - there's genuinely no document available
          // to show, and loadDocument already logs its own failures.
          // The grid's own "no document loaded" empty state (a loading
          // spinner, per SpreadsheetGrid.build) covers the UI.
        }
      }
    }

    if (mounted) {
      _syncViewportBounds();
    }
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