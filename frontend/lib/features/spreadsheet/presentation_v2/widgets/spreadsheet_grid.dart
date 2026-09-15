import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/spreadsheet_controller.dart';
import '../../controllers/viewport_controller.dart';
import '../column_naming.dart';
import 'grid_cell.dart';
import 'grid_column_header.dart';
import 'grid_row_header.dart';

/// The scrollable grid of column headers, row headers, and cells.
///
/// Built as a single [Table] so that column widths line up between the
/// header row and every data row automatically (a real spreadsheet-like
/// guarantee that's easy to get wrong with independently-positioned
/// widgets). The whole table scrolls both directions together inside a
/// two-axis scroll view - this is the simplest correct approach for a
/// first version; a virtualized/windowed approach can replace this later
/// once real sheets are larger than a screenful.
///
/// This widget holds NO state describing what's selected, being edited,
/// or what any cell contains - all of that lives in the controllers and
/// is read fresh by [GridCell] itself. This widget's only job is layout
/// AND keyboard navigation: arrow keys move viewportController.selection
/// when no cell is being edited. This is the one place that legitimately
/// needs to know about the whole grid (individual GridCells deliberately
/// don't know about their neighbors), so navigation lives here rather
/// than being duplicated per-cell.
///
/// While a cell IS being edited, this widget's key handler steps aside
/// (returns "ignored") so the active GridCell's own TextField keeps
/// normal text-editing keyboard behavior (arrow keys move the text
/// cursor, not the selection).
class SpreadsheetGrid extends StatefulWidget {
  const SpreadsheetGrid({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  static const double columnWidth = 100;
  static const double rowHeight = 28;
  static const double headerSize = 40;

  @override
  State<SpreadsheetGrid> createState() => _SpreadsheetGridState();
}

class _SpreadsheetGridState extends State<SpreadsheetGrid> {
  final FocusNode _gridFocusNode = FocusNode(debugLabel: 'SpreadsheetGrid');

  // True while a drag-range selection gesture is in progress (mouse down
  // and moving across cells). Purely a local interaction flag for THIS
  // gesture - it does not describe spreadsheet state, so it stays local
  // rather than living in a controller. The actual selection range it
  // produces is written to viewportController as the drag happens, which
  // IS the shared state other widgets (GridCell) read from.
  bool _isDragging = false;

  // True while the actively-editing cell's in-progress text is a formula
  // (starts with "="). Reported UP from the editing GridCell (which is
  // the only widget that actually knows its own live, uncommitted text),
  // via onFormulaEditingChanged. While true, a plain click on another
  // cell means "insert a reference to that cell into the formula" rather
  // than the normal "commit and select that cell" - so this flag changes
  // what GridCell.onTap does grid-wide, not just the editing cell.
  bool _isEditingFormula = false;

  // Carries a clicked cell's reference text (e.g. "B3") DOWN to whichever
  // GridCell is actively editing, so it can splice that text into its own
  // TextField at the current cursor position. Owned by the grid (the only
  // widget that knows about every cell), listened to by the editing cell
  // only. Set back to null immediately after being read/consumed.
  final ValueNotifier<String?> _formulaReferenceToInsert =
      ValueNotifier(null);

  @override
  void dispose() {
    _gridFocusNode.dispose();
    _formulaReferenceToInsert.dispose();
    super.dispose();
  }

  void _handleFormulaEditingChanged(bool isFormula) {
    if (_isEditingFormula != isFormula) {
      setState(() {
        _isEditingFormula = isFormula;
      });
    }
  }

  void _handleDragStart(int row, int column) {
    if (widget.viewportController.isEditing) {
      return;
    }
    _isDragging = true;
    widget.viewportController.startSelectionAt(row, column);
    _gridFocusNode.requestFocus();
  }

  void _handleDragEnter(int row, int column) {
    if (!_isDragging) {
      return;
    }
    widget.viewportController.extendSelectionTo(row, column);
  }

  void _handleDragEnd() {
    _isDragging = false;
  }

  String _referenceFor(int row, int column) {
    return '${columnLetterName(column)}${row + 1}';
  }

  void _handleCellTapDuringFormulaEdit(int row, int column) {
    debugPrint(
      '[SpreadsheetGrid._handleCellTapDuringFormulaEdit] '
      'row=$row column=$column '
      'primaryFocusBefore=${FocusManager.instance.primaryFocus}',
    );
    _formulaReferenceToInsert.value = _referenceFor(row, column);
  }

  Future<void> _handleCopy({required bool andClear}) async {
    await widget.spreadsheetController
        .copySelection(widget.viewportController.selection);
    if (andClear) {
      widget.spreadsheetController
          .clearSelection(widget.viewportController.selection);
    }
  }

  Future<void> _handlePaste() async {
    final clipboardData =
        await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text;
    if (text == null) {
      return;
    }
    final selection = widget.viewportController.selection;
    final targetRow =
        selection.startRow <= selection.endRow
            ? selection.startRow
            : selection.endRow;
    final targetColumn =
        selection.startColumn <= selection.endColumn
            ? selection.startColumn
            : selection.endColumn;

    await widget.spreadsheetController.pasteClipboard(
      row: targetRow,
      column: targetColumn,
      clipboardText: text,
    );
  }

  void _startEditingWithCharacter(String character) {
    widget.viewportController.startEditing(
      replaceInitialValue: true,
      initialValue: character,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // While a cell is being edited, its own TextField owns the keyboard
    // (for normal text-cursor movement) - don't intercept arrow keys here.
    if (widget.viewportController.isEditing) {
      return KeyEventResult.ignored;
    }

    final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlOrCmd) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyC:
          _handleCopy(andClear: false);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyX:
          _handleCopy(andClear: true);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          _handlePaste();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyZ:
          if (isShift) {
            widget.spreadsheetController.redo();
          } else {
            widget.spreadsheetController.undo();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY:
          widget.spreadsheetController.redo();
          return KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        widget.viewportController.moveLeft();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        widget.viewportController.moveRight();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.viewportController.moveUp();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.viewportController.moveDown();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        widget.viewportController.moveNext();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        widget.viewportController.moveDown();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        widget.spreadsheetController
            .clearSelection(widget.viewportController.selection);
        return KeyEventResult.handled;
      default:
        // Typing a plain printable character while a cell is selected
        // (but not yet editing) starts editing that cell, REPLACING its
        // existing content with what was typed - matching standard
        // spreadsheet behavior (Excel/Sheets). event.character is null
        // for non-printable/modifier keys, so those fall through here
        // harmlessly as ignored.
        final character = event.character;
        if (character != null &&
            character.isNotEmpty &&
            !HardwareKeyboard.instance.isAltPressed) {
          _startEditingWithCharacter(character);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _gridFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // Clicking anywhere in the grid area (including on a cell,
          // since GestureDetector allows bubbling for taps that a child
          // doesn't itself claim exclusively) returns keyboard focus to
          // the grid for arrow-key navigation, unless a cell is actively
          // being edited (in which case its own TextField should keep
          // focus - which it already has, since GridCell requests focus
          // itself when entering edit mode).
          if (!widget.viewportController.isEditing) {
            _gridFocusNode.requestFocus();
          }
        },
        child: AnimatedBuilder(
          animation: widget.spreadsheetController,
          builder: (context, _) {
            final sheet =
                widget.spreadsheetController.spreadsheet?.activeSheet;

            if (sheet == null || sheet.rows.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            final rowCount = sheet.rows.length;
            final columnCount = sheet.rows
                .map((row) => row.cells.length)
                .fold<int>(0, (max, length) => length > max ? length : max);

            if (columnCount == 0) {
              return const SizedBox.shrink();
            }

            final columnWidths = <int, TableColumnWidth>{
              0: const FixedColumnWidth(SpreadsheetGrid.headerSize),
              for (var c = 0; c < columnCount; c++)
                c + 1: const FixedColumnWidth(SpreadsheetGrid.columnWidth),
            };

            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  columnWidths: columnWidths,
                  defaultVerticalAlignment:
                      TableCellVerticalAlignment.middle,
                  children: [
                    // ------------------------------------------------
                    // Header row: blank corner + column letters
                    // ------------------------------------------------
                    TableRow(
                      children: [
                        const SizedBox(
                          width: SpreadsheetGrid.headerSize,
                          height: SpreadsheetGrid.headerSize,
                        ),
                        for (var c = 0; c < columnCount; c++)
                          SizedBox(
                            height: SpreadsheetGrid.headerSize,
                            child: GridColumnHeader(columnIndex: c),
                          ),
                      ],
                    ),

                    // ------------------------------------------------
                    // Data rows: row number + cells
                    // ------------------------------------------------
                    for (var r = 0; r < rowCount; r++)
                      TableRow(
                        children: [
                          SizedBox(
                            height: SpreadsheetGrid.rowHeight,
                            child: GridRowHeader(rowIndex: r),
                          ),
                          for (var c = 0; c < columnCount; c++)
                            SizedBox(
                              height: SpreadsheetGrid.rowHeight,
                              child: GridCell(
                                row: r,
                                column: c,
                                spreadsheetController:
                                    widget.spreadsheetController,
                                viewportController:
                                    widget.viewportController,
                                gridFocusNode: _gridFocusNode,
                                onDragStart: _handleDragStart,
                                onDragEnter: _handleDragEnter,
                                onDragEnd: _handleDragEnd,
                                isFormulaReferencePickingActive:
                                    _isEditingFormula,
                                onCellTapDuringFormulaEdit:
                                    _handleCellTapDuringFormulaEdit,
                                onFormulaEditingChanged:
                                    _handleFormulaEditingChanged,
                                formulaReferenceToInsert:
                                    _formulaReferenceToInsert,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}