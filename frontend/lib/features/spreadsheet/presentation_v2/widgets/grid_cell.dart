import 'package:flutter/material.dart';

import '../../controllers/spreadsheet_controller.dart';
import '../../controllers/viewport_controller.dart';
import '../../models/selection_model.dart';

/// A single spreadsheet cell.
///
/// This widget intentionally holds NO private state of its own. Everything
/// it shows - the text, whether it's selected, whether it's being edited -
/// is read fresh from [spreadsheetController] and [viewportController] on
/// every build. This is deliberate: the long-term goal is real-time
/// multi-user editing, where a cell's appearance must be able to change
/// because of a REMOTE user's action, not just a local one. A widget that
/// only knows about local interactions (e.g. tracking "am I selected" in
/// its own State) could not react correctly to that. By deriving
/// everything from the controllers, a future remote-update mechanism only
/// has to update the controller/model - every cell watching it updates
/// automatically, regardless of who caused the change.
///
/// This widget also does not decide layout/position - the parent grid is
/// responsible for placing it. This widget only decides what to show and
/// how to react to taps on itself.
class GridCell extends StatelessWidget {
  const GridCell({
    super.key,
    required this.row,
    required this.column,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final int row;
  final int column;
  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    // Listen to both controllers. Content can change from an edit
    // (spreadsheetController) and selection/editing-mode can change
    // independently (viewportController) - a cell needs to redraw for
    // either.
    return AnimatedBuilder(
      animation: Listenable.merge([
        spreadsheetController,
        viewportController,
      ]),
      builder: (context, _) {
        final sheet = spreadsheetController.spreadsheet?.activeSheet;
        if (sheet == null ||
            row < 0 ||
            row >= sheet.rows.length) {
          return const SizedBox.shrink();
        }

        final cells = sheet.rows[row].cells;
        if (column < 0 || column >= cells.length) {
          return const SizedBox.shrink();
        }

        final cell = cells[column];

        final selection = viewportController.selection;
        final isSelected = _isWithinSelection(selection, row, column);
        final isActiveCell =
            selection.startRow == row && selection.startColumn == column;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            viewportController.selectCell(row, column);
          },
          onDoubleTap: () {
            viewportController.selectCell(row, column);
            viewportController.startEditing();
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue.withValues(alpha: 0.08)
                  : Colors.white,
              border: Border.all(
                color: isActiveCell
                    ? Colors.blue
                    : Colors.grey.shade300,
                width: isActiveCell ? 2 : 0.5,
              ),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              cell.value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      },
    );
  }

  bool _isWithinSelection(SelectionModel selection, int row, int column) {
    final firstRow = selection.startRow <= selection.endRow
        ? selection.startRow
        : selection.endRow;
    final lastRow = selection.startRow >= selection.endRow
        ? selection.startRow
        : selection.endRow;
    final firstColumn = selection.startColumn <= selection.endColumn
        ? selection.startColumn
        : selection.endColumn;
    final lastColumn = selection.startColumn >= selection.endColumn
        ? selection.startColumn
        : selection.endColumn;

    return row >= firstRow &&
        row <= lastRow &&
        column >= firstColumn &&
        column <= lastColumn;
  }
}
