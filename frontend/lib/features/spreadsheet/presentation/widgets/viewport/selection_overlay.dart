import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/spreadsheet_model.dart';
import '../../../controllers/spreadsheet_controller.dart';
import 'cell_editor.dart';

class SpreadsheetSelectionOverlay extends StatefulWidget {
  const SpreadsheetSelectionOverlay({
    super.key,
    required this.viewportController,
    required this.spreadsheet,
    required this.spreadsheetController,
    required this.focusNode,
  });

  final ViewportController viewportController;
  final SpreadsheetModel spreadsheet;
  final SpreadsheetController spreadsheetController;
  final FocusNode focusNode;

  @override
  State<SpreadsheetSelectionOverlay> createState() =>
      _SpreadsheetSelectionOverlayState();
}

class _SpreadsheetSelectionOverlayState
    extends State<SpreadsheetSelectionOverlay> {
  void _finishEditing() {
    widget.viewportController.stopEditing();

    // Wait until the editor has actually disappeared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      widget.focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewportController,
      builder: (context, _) {
        final selection =
            widget.viewportController.selection;

        final viewport =
            widget.viewportController.viewport;

        const cellWidth = 80.0;
        const cellHeight = 28.0;

        final selectionStartRow =
            selection.startRow < selection.endRow
                ? selection.startRow
                : selection.endRow;

        final selectionEndRow =
            selection.startRow > selection.endRow
                ? selection.startRow
                : selection.endRow;

        final selectionStartColumn =
            selection.startColumn < selection.endColumn
                ? selection.startColumn
                : selection.endColumn;

        final selectionEndColumn =
            selection.startColumn > selection.endColumn
                ? selection.startColumn
                : selection.endColumn;

        final left =
            selectionStartColumn * cellWidth -
            viewport.scrollX;

        final top =
            selectionStartRow * cellHeight -
            viewport.scrollY;

        final width =
            (selectionEndColumn - selectionStartColumn + 1) *
            cellWidth;

        final height =
            (selectionEndRow - selectionStartRow + 1) *
            cellHeight;

        final sheet =
            widget.spreadsheet.activeSheet;

        if (selection.startRow < 0 ||
            selection.startRow >= sheet.rows.length) {
          return const SizedBox.expand();
        }

        final row =
            sheet.rows[selection.startRow];

        if (selection.startColumn < 0 ||
            selection.startColumn >= row.cells.length) {
          return const SizedBox.expand();
        }

        final cell =
            row.cells[selection.startColumn];

        return Stack(
          children: [
            if (widget.viewportController.isEditing)
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: CellEditor(
                  key: ValueKey(
                    'editor_${selection.startRow}_${selection.startColumn}',
                  ),

                  initialValue:
                      widget.viewportController.initialEditValue ??
                      cell.value,

                  onCommit: (value) {
                    widget.spreadsheetController.editCell(
                      row: selection.startRow,
                      column: selection.startColumn,
                      value: value,
                    );

                    _finishEditing();
                  },

                  onCancel: () {
                    _finishEditing();
                  },
                ),
              )
            else
              Positioned(
                left: left,
                top: top,
                width: cellWidth,
                height: cellHeight,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(
                        alpha: 0.08,
                      ),
                      border: Border.all(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}