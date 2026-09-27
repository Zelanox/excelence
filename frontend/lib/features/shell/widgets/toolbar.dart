import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import 'settings_dialog.dart';

/// The top toolbar: currently just Settings.
///
/// File open/save/undo/redo icons used to sit here but were removed -
/// they were bare Icon widgets with no onTap/IconButton wrapping them at
/// all, not wired to anything. Row/column insert and delete are handled
/// directly on the grid itself (the hover "+" handles past the last
/// row/column in SpreadsheetGrid for insert, a right-click context menu
/// on GridColumnHeader/GridRowHeader for delete/rename), so those were
/// never toolbar candidates to begin with. spreadsheetController and
/// viewportController are both still accepted here even though only the
/// former is currently used (by the settings gear, to open
/// SettingsDialog) - kept rather than dropped from the constructor,
/// since real toolbar actions (a working Save button, Undo/Redo) are
/// the natural next thing to add here and viewportController will be
/// needed for at least some of those.
class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => SettingsDialog.show(
              context,
              spreadsheetController: spreadsheetController,
            ),
          ),
        ],
      ),
    );
  }
}
