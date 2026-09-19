import 'package:flutter/material.dart';

import '../controllers/spreadsheet_controller.dart';
import '../controllers/viewport_controller.dart';
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
///
/// SpreadsheetController and ViewportController are no longer owned or
/// created here - ShellPage owns them (Toolbar needs the same instances
/// to read selection and trigger insert/delete row/column), and simply
/// passes them down as constructor params.
class SpreadsheetFeatureV2 extends StatelessWidget {
  const SpreadsheetFeatureV2({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return SpreadsheetGrid(
      spreadsheetController: spreadsheetController,
      viewportController: viewportController,
    );
  }
}
