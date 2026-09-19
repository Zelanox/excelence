import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';

/// The top toolbar: File/Save/Undo/Redo.
///
/// Row/column insert and delete used to live here as dedicated buttons,
/// but that's now handled directly on the grid itself - the hover "+"
/// handles past the last row/column (SpreadsheetGrid) for insert, and a
/// right-click context menu on GridColumnHeader/GridRowHeader for
/// delete/rename - which better matches where a user's attention already
/// is when they want to add or remove a row/column. spreadsheetController
/// and viewportController are still accepted here (rather than dropped
/// from the constructor) since Undo/Redo will wire up to
/// spreadsheetController next.
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
          const Icon(Icons.folder_open),
          const SizedBox(width: 10),
          const Icon(Icons.save),
          const SizedBox(width: 10),
          const Icon(Icons.undo),
          const SizedBox(width: 10),
          const Icon(Icons.redo),
        ],
      ),
    );
  }
}
