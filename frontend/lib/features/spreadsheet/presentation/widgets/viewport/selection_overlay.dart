import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/spreadsheet_model.dart';
import '../../../models/cell_position.dart';
import '../../../controllers/spreadsheet_controller.dart';
import 'cell_editor.dart';

class SpreadsheetSelectionOverlay extends StatefulWidget {
  const SpreadsheetSelectionOverlay({
    super.key,
    required this.viewportController,
    required this.spreadsheet,
    required this.spreadsheetController,
    required this.focusNode,
    this.referenceInsertion,
    this.formulaReferenceStart,
    this.formulaReferenceEnd,
  });

  final ViewportController viewportController;
  final SpreadsheetModel spreadsheet;
  final SpreadsheetController spreadsheetController;
  final FocusNode focusNode;
  final ValueNotifier<String?>? referenceInsertion;
  final CellPosition? formulaReferenceStart;
  final CellPosition? formulaReferenceEnd;

  @override
  State<SpreadsheetSelectionOverlay> createState() =>
      _SpreadsheetSelectionOverlayState();
}

class _SpreadsheetSelectionOverlayState
    extends State<SpreadsheetSelectionOverlay> {
  // ============================================================
  // EDITING
  // ============================================================

  void _finishEditing() {
    widget.viewportController.stopEditing();

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

        final sheet =
            widget.spreadsheet.activeSheet;

        // ========================================================
        // ACTIVE CELL
        //
        // The start position remains the active cell.
        // This is important for editing.
        // ========================================================

        if (selection.startRow < 0 ||
            selection.startRow >= sheet.rows.length) {
          return const SizedBox.expand();
        }

        final activeRow =
            sheet.rows[selection.startRow];

        if (selection.startColumn < 0 ||
            selection.startColumn >= activeRow.cells.length) {
          return const SizedBox.expand();
        }

        final activeCell =
            activeRow.cells[selection.startColumn];

        // ========================================================
        // SELECTION RANGE
        // ========================================================

        final firstRow =
            selection.startRow <= selection.endRow
                ? selection.startRow
                : selection.endRow;

        final lastRow =
            selection.startRow >= selection.endRow
                ? selection.startRow
                : selection.endRow;

        final firstColumn =
            selection.startColumn <= selection.endColumn
                ? selection.startColumn
                : selection.endColumn;

        final lastColumn =
            selection.startColumn >= selection.endColumn
                ? selection.startColumn
                : selection.endColumn;

        // ========================================================
        // SELECTION RECTANGLE
        // ========================================================

        final selectionLeft =
            firstColumn * cellWidth -
            viewport.scrollX;

        final selectionTop =
            firstRow * cellHeight -
            viewport.scrollY;

        final selectionWidth =
            (lastColumn - firstColumn + 1) *
            cellWidth;

        final selectionHeight =
            (lastRow - firstRow + 1) *
            cellHeight;

        // ========================================================
        // EDITOR POSITION
        //
        // The editor always belongs to the active/start cell,
        // NOT the entire selected range.
        // ========================================================

        final editorLeft =
            selection.startColumn * cellWidth -
            viewport.scrollX;

        final editorTop =
            selection.startRow * cellHeight -
            viewport.scrollY;

        return Stack(
          children: [
            // ====================================================
            // SELECTION
            //
            // NOTE: every entry in this list is now ALWAYS present
            // (never conditionally omitted). Previously these were
            // `if (...) Positioned(...)` entries, which meant the
            // list's length/order shifted depending on isEditing
            // and the formula-reference drag state. That shifting
            // defeated Flutter's key-based diffing for CellEditor
            // below (its position in the children list kept
            // changing), causing it to be destroyed and recreated
            // on every pointer event instead of preserved - which
            // wiped out in-progress formula text on every click.
            // Using SizedBox.shrink() as an always-present "empty"
            // placeholder keeps every child's list position and
            // key stable across rebuilds.
            // ====================================================

            KeyedSubtree(
              key: const ValueKey('selection_highlight'),
              child: widget.viewportController.isEditing
                  ? const SizedBox.shrink()
                  : Positioned(
                      left: selectionLeft,
                      top: selectionTop,
                      width: selectionWidth,
                      height: selectionHeight,
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
            ),

            KeyedSubtree(
              key: const ValueKey('formula_reference_highlight'),
              child: (widget.viewportController.isEditing &&
                      widget.formulaReferenceStart != null &&
                      widget.formulaReferenceEnd != null)
                  ? Positioned(
                      left: (widget.formulaReferenceStart!.column <
                                  widget.formulaReferenceEnd!.column
                              ? widget.formulaReferenceStart!.column
                              : widget.formulaReferenceEnd!.column) *
                          cellWidth -
                          viewport.scrollX,
                      top: (widget.formulaReferenceStart!.row <
                                  widget.formulaReferenceEnd!.row
                              ? widget.formulaReferenceStart!.row
                              : widget.formulaReferenceEnd!.row) *
                          cellHeight -
                          viewport.scrollY,
                      width: ((widget.formulaReferenceStart!.column >
                                      widget.formulaReferenceEnd!.column
                                  ? widget.formulaReferenceStart!.column
                                  : widget.formulaReferenceEnd!.column) -
                              (widget.formulaReferenceStart!.column <
                                      widget.formulaReferenceEnd!.column
                                  ? widget.formulaReferenceStart!.column
                                  : widget.formulaReferenceEnd!.column) +
                              1) *
                          cellWidth,
                      height: ((widget.formulaReferenceStart!.row >
                                      widget.formulaReferenceEnd!.row
                                  ? widget.formulaReferenceStart!.row
                                  : widget.formulaReferenceEnd!.row) -
                              (widget.formulaReferenceStart!.row <
                                      widget.formulaReferenceEnd!.row
                                  ? widget.formulaReferenceStart!.row
                                  : widget.formulaReferenceEnd!.row) +
                              1) *
                          cellHeight,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // ====================================================
            // CELL EDITOR
            // ====================================================

            KeyedSubtree(
              key: const ValueKey('cell_editor_slot'),
              child: widget.viewportController.isEditing
                  ? Positioned(
                      left: editorLeft,
                      top: editorTop,
                      width: cellWidth,
                      height: cellHeight,
                      child: CellEditor(
                        key: ValueKey(
                          'editor_${selection.startRow}_${selection.startColumn}',
                        ),

                        initialValue:
                            widget.viewportController.initialEditValue ??
                            activeCell.value,
                        referenceInsertion: widget.referenceInsertion,

                        onCommit: (value) {
                          debugPrint(
                            '[SelectionOverlay.commit] '
                            'targetRow=${selection.startRow} '
                            'targetColumn=${selection.startColumn} '
                            'text="$value"',
                          );
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
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}