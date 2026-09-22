import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../controllers/spreadsheet_controller.dart';
import '../../controllers/viewport_controller.dart';
import '../../models/cell_position.dart';
import '../column_naming.dart';
import 'grid_cell.dart';
import 'grid_column_header.dart';
import 'grid_row_header.dart';

/// The scrollable grid of column headers, row headers, and cells.
///
/// Built on [TableView.builder] (from the two_dimensional_scrollables
/// package), which builds and lays out only the cells actually visible
/// in the viewport - a real spreadsheet can have thousands of rows, and
/// the previous plain-[Table] implementation built every single cell
/// widget on every rebuild regardless of what was on screen, which is
/// what actually caused the lag on larger sheets (a full-table rebuild
/// on every keystroke while searching, for instance). pinnedRowCount/
/// pinnedColumnCount keep the header row and row-number column fixed in
/// place while the body scrolls underneath, matching the old dual-
/// [SingleChildScrollView] behavior but without hand-syncing two scroll
/// positions.
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

  // TableView's own scroll controllers - kept here (rather than inside
  // ViewportController, which has no Flutter widget lifecycle of its
  // own) so they can be properly disposed. Their listeners mirror
  // real scroll position INTO viewportController.viewport.scrollX/Y,
  // which is what getVisibleRange/ensureVisible read - keeping
  // TableView as the single source of truth for "what's actually
  // scrolled to" rather than letting two representations drift apart.
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  // Whether a column header is currently mid-rename (its own inline
  // TextField is showing and owns keyboard input). Column-header renaming
  // is tracked entirely inside GridColumnHeader's State, not in
  // viewportController.isEditing (that flag is cell-editing only), so the
  // grid needs its own signal here to avoid stealing focus back from the
  // header's TextField - which previously caused renames to fail and
  // keystrokes to fall through to whatever cell was selected instead.
  bool _isRenamingHeader = false;

  void _setRenamingHeader(bool value) {
    if (_isRenamingHeader != value) {
      setState(() {
        _isRenamingHeader = value;
      });
    }
  }

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

  // True while a REFERENCE-RANGE drag is in progress (dragging across
  // cells during formula editing to build e.g. "B1:B3", as opposed to
  // _isDragging which is for normal cell-range selection). These are
  // deliberately separate flags/handlers rather than reusing the normal
  // drag-selection path, since the two have completely different
  // endpoints: normal dragging writes to viewportController.selection
  // live; a reference-range drag only produces a reference STRING, and
  // only inserts it into the editing cell's text once the drag ends.
  bool _isDraggingReferenceRange = false;

  // The start/end cells of an in-progress reference-range drag, exposed
  // as a single ValueNotifier so GridCell can show a live highlight over
  // the spanned cells without the grid needing setState() on every
  // pointer-move (which would rebuild the whole Table unnecessarily).
  final ValueNotifier<({CellPosition? start, CellPosition? end})>
      _referenceRangeDrag = ValueNotifier((start: null, end: null));

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _gridFocusNode.dispose();
    _formulaReferenceToInsert.dispose();
    _referenceRangeDrag.dispose();
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

  String _rangeReferenceFor(CellPosition start, CellPosition end) {
    final startRef = _referenceFor(start.row, start.column);
    if (start.row == end.row && start.column == end.column) {
      // A "drag" that never actually left the starting cell is just a
      // single-cell reference, not a degenerate "B1:B1" range.
      return startRef;
    }
    final endRef = _referenceFor(end.row, end.column);
    return '$startRef:$endRef';
  }

  void _handleReferenceRangeDragStart(int row, int column) {
    _isDraggingReferenceRange = true;
    final position = CellPosition(row: row, column: column);
    _referenceRangeDrag.value = (start: position, end: position);
  }

  void _handleReferenceRangeDragEnter(int row, int column) {
    if (!_isDraggingReferenceRange) {
      return;
    }
    final start = _referenceRangeDrag.value.start;
    if (start == null) {
      return;
    }
    _referenceRangeDrag.value = (
      start: start,
      end: CellPosition(row: row, column: column),
    );
  }

  void _handleReferenceRangeDragEnd() {
    if (!_isDraggingReferenceRange) {
      return;
    }
    _isDraggingReferenceRange = false;

    final start = _referenceRangeDrag.value.start;
    final end = _referenceRangeDrag.value.end;
    _referenceRangeDrag.value = (start: null, end: null);

    if (start == null || end == null) {
      return;
    }
    _formulaReferenceToInsert.value = _rangeReferenceFor(start, end);
  }

  void _handleCellTapDuringFormulaEdit(int row, int column) {
    _formulaReferenceToInsert.value = _referenceFor(row, column);
  }

  /// Generates a column name that doesn't collide with any header already
  /// present on the active sheet - "Column A", "Column B", etc. Mirrors
  /// the same collision-avoidance approach used elsewhere for
  /// auto-generated column names.
  String _nextColumnName() {
    final headers =
        widget.spreadsheetController.spreadsheet?.activeSheet.headers ??
            const <String>[];
    final existing = headers.toSet();

    var index = headers.length;
    String candidate;
    do {
      candidate = 'Column ${columnLetterName(index)}';
      index++;
    } while (existing.contains(candidate));

    return candidate;
  }

  Future<void> _appendColumn() async {
    final name = _nextColumnName();
    try {
      await widget.spreadsheetController.insertColumn(
        name: name,
        index: _currentColumnCount(),
      );
      _refreshSheetBounds();
    } catch (error) {
      _showError('Failed to insert column: $error');
    }
  }

  Future<void> _appendRow() async {
    try {
      await widget.spreadsheetController.insertRow(
        index: _currentRowCount(),
      );
      _refreshSheetBounds();
    } catch (error) {
      _showError('Failed to insert row: $error');
    }
  }

  int _currentRowCount() {
    return widget.spreadsheetController.spreadsheet?.activeSheet.rows.length ??
        0;
  }

  int _currentColumnCount() {
    final sheet = widget.spreadsheetController.spreadsheet?.activeSheet;
    if (sheet == null || sheet.rows.isEmpty) {
      return 0;
    }
    return sheet.rows
        .map((row) => row.cells.length)
        .fold<int>(0, (max, length) => length > max ? length : max);
  }

  void _refreshSheetBounds() {
    final sheet = widget.spreadsheetController.spreadsheet?.activeSheet;
    if (sheet == null) {
      return;
    }
    widget.viewportController.setSheetBounds(
      rowCount: sheet.rows.length,
      columnCount:
          sheet.rows.isEmpty ? 0 : sheet.rows.first.cells.length,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

  /// After keyboard navigation moves the selection, scrolls TableView
  /// (if needed) so the newly-selected cell is fully visible. With the
  /// old non-virtualized Table this was unnecessary - every cell always
  /// existed on screen somewhere. With TableView.builder, a cell outside
  /// the current viewport isn't built at all, so navigating to it
  /// without this would move the selection "off-screen" invisibly.
  void _ensureSelectionVisible() {
    if (!_verticalController.hasClients ||
        !_horizontalController.hasClients) {
      return;
    }

    final selection = widget.viewportController.selection;

    // Sync the controller's notion of current scroll position from the
    // real ScrollControllers right before computing anything - this is
    // the one place that needs it, rather than keeping it continuously
    // live via a scroll listener (which would notifyListeners() on
    // every scroll frame and rebuild every visible GridCell for no
    // reason, since nothing else reads scrollX/scrollY continuously).
    widget.viewportController.setScroll(
      x: _horizontalController.offset,
      y: _verticalController.offset,
    );

    final viewportSize = (context.findRenderObject() as RenderBox?)?.size;
    if (viewportSize == null) return;

    // Subtract the pinned header row/row-number column from the
    // available body size, since ensureVisible's math is in terms of
    // the scrollable body area only (row 0 / column 0 are always
    // visible regardless of scroll position).
    final bodySize = Size(
      (viewportSize.width - SpreadsheetGrid.headerSize)
          .clamp(0, viewportSize.width),
      (viewportSize.height - SpreadsheetGrid.headerSize)
          .clamp(0, viewportSize.height),
    );

    widget.viewportController.ensureVisible(
      row: selection.endRow,
      column: selection.endColumn,
      viewportSize: bodySize,
      cellWidth: SpreadsheetGrid.columnWidth,
      cellHeight: SpreadsheetGrid.rowHeight,
    );

    final target = widget.viewportController.viewport;

    if (target.scrollX != _horizontalController.offset) {
      _horizontalController.jumpTo(
        target.scrollX.clamp(
          0,
          _horizontalController.position.maxScrollExtent,
        ),
      );
    }

    if (target.scrollY != _verticalController.offset) {
      _verticalController.jumpTo(
        target.scrollY.clamp(
          0,
          _verticalController.position.maxScrollExtent,
        ),
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // While a cell is being edited, its own TextField owns the keyboard
    // (for normal text-cursor movement) - don't intercept arrow keys here.
    // Same for a column header mid-rename - its TextField should get the
    // keystrokes, not trigger cell navigation/edit-start.
    if (widget.viewportController.isEditing || _isRenamingHeader) {
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
        _ensureSelectionVisible();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        widget.viewportController.moveRight();
        _ensureSelectionVisible();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.viewportController.moveUp();
        _ensureSelectionVisible();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.viewportController.moveDown();
        _ensureSelectionVisible();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        widget.viewportController.moveNext();
        _ensureSelectionVisible();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        widget.viewportController.moveDown();
        _ensureSelectionVisible();
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
          if (!widget.viewportController.isEditing && !_isRenamingHeader) {
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

            // Table-index layout: row/column 0 is the pinned header
            // (column headers / row numbers); rows 1..rowCount and
            // columns 1..columnCount are real data, offset by one from
            // their sheet indices; the final row/column hosts the hover
            // "+" append affordance. pinnedRowCount/pinnedColumnCount
            // keep row 0 and column 0 fixed in place while the body
            // scrolls beneath them - TableView's built-in equivalent of
            // the old dual-SingleChildScrollView sync.
            const addHandleSize = 20.0;

            return TableView.builder(
              pinnedRowCount: 1,
              pinnedColumnCount: 1,
              verticalDetails: ScrollableDetails.vertical(
                controller: _verticalController,
              ),
              horizontalDetails: ScrollableDetails.horizontal(
                controller: _horizontalController,
              ),
              rowCount: rowCount + 2,
              columnCount: columnCount + 2,
              rowBuilder: (int index) {
                final extent = index == 0
                    ? SpreadsheetGrid.headerSize
                    : index == rowCount + 1
                        ? addHandleSize
                        : SpreadsheetGrid.rowHeight;
                return TableSpan(extent: FixedTableSpanExtent(extent));
              },
              columnBuilder: (int index) {
                final extent = index == 0
                    ? SpreadsheetGrid.headerSize
                    : index == columnCount + 1
                        ? addHandleSize
                        : SpreadsheetGrid.columnWidth;
                return TableSpan(extent: FixedTableSpanExtent(extent));
              },
              cellBuilder: (context, vicinity) {
                final isHeaderRow = vicinity.row == 0;
                final isHeaderColumn = vicinity.column == 0;
                final isAppendRow = vicinity.row == rowCount + 1;
                final isAppendColumn = vicinity.column == columnCount + 1;

                // Corner cell: blank above the row-number column.
                if (isHeaderRow && isHeaderColumn) {
                  return const TableViewCell(child: SizedBox.shrink());
                }

                // Top-right corner: "+" to append a column.
                if (isHeaderRow && isAppendColumn) {
                  return TableViewCell(
                    child: _HoverAddHandle(
                      axis: Axis.horizontal,
                      tooltip: 'Add column to the right',
                      onTap: _appendColumn,
                    ),
                  );
                }

                // Column header row.
                if (isHeaderRow) {
                  final column = vicinity.column - 1;
                  return TableViewCell(
                    child: GridColumnHeader(
                      columnIndex: column,
                      spreadsheetController: widget.spreadsheetController,
                      onRenamingChanged: _setRenamingHeader,
                    ),
                  );
                }

                // Bottom-left corner (below row numbers): blank filler.
                if (isAppendRow && isHeaderColumn) {
                  return const TableViewCell(child: SizedBox.shrink());
                }

                // Bottom-right corner: blank filler.
                if (isAppendRow && isAppendColumn) {
                  return const TableViewCell(child: SizedBox.shrink());
                }

                // Append-row bar: only the first data column actually
                // renders the (visually full-width, via OverflowBox)
                // handle - matches the old Table's approach exactly.
                if (isAppendRow) {
                  final column = vicinity.column - 1;
                  return TableViewCell(
                    child: column == 0
                        ? _HoverAddHandle(
                            axis: Axis.vertical,
                            tooltip: 'Add row below',
                            onTap: _appendRow,
                            spanWidth:
                                SpreadsheetGrid.columnWidth * columnCount,
                          )
                        : const SizedBox.shrink(),
                  );
                }

                // Row-number header column.
                if (isHeaderColumn) {
                  final row = vicinity.row - 1;
                  return TableViewCell(
                    child: GridRowHeader(
                      rowIndex: row,
                      spreadsheetController: widget.spreadsheetController,
                    ),
                  );
                }

                // Append-column bar (to the right of real data, any
                // row): blank filler, matching the old trailing column.
                if (isAppendColumn) {
                  return const TableViewCell(child: SizedBox.shrink());
                }

                // A real data cell.
                final row = vicinity.row - 1;
                final column = vicinity.column - 1;
                return TableViewCell(
                  child: GridCell(
                    row: row,
                    column: column,
                    spreadsheetController: widget.spreadsheetController,
                    viewportController: widget.viewportController,
                    gridFocusNode: _gridFocusNode,
                    onDragStart: _handleDragStart,
                    onDragEnter: _handleDragEnter,
                    onDragEnd: _handleDragEnd,
                    isFormulaReferencePickingActive: _isEditingFormula,
                    onCellTapDuringFormulaEdit:
                        _handleCellTapDuringFormulaEdit,
                    onFormulaEditingChanged: _handleFormulaEditingChanged,
                    formulaReferenceToInsert: _formulaReferenceToInsert,
                    onReferenceRangeDragStart:
                        _handleReferenceRangeDragStart,
                    onReferenceRangeDragEnter:
                        _handleReferenceRangeDragEnter,
                    onReferenceRangeDragEnd: _handleReferenceRangeDragEnd,
                    referenceRangeDrag: _referenceRangeDrag,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// A slim "+" handle shown past the last column (or below the last row)
/// that appends a new column/row on tap - the Obsidian/Word-table style
/// insert affordance. Mostly invisible until hovered, at which point it
/// highlights and shows a tooltip explaining what it does.
///
/// For the row-append handle, [spanWidth] stretches the hoverable/visible
/// area across the full width of the data columns (matching the
/// reference screenshot, where the "+" row runs the width of the table)
/// even though the handle itself renders as a single Table cell - the
/// visible bar is drawn wider than its cell via a Stack + OverflowBox so
/// hovering anywhere along the bottom edge triggers it, not just the
/// leftmost cell.
class _HoverAddHandle extends StatefulWidget {
  const _HoverAddHandle({
    required this.axis,
    required this.tooltip,
    required this.onTap,
    this.spanWidth,
  });

  final Axis axis;
  final String tooltip;
  final VoidCallback onTap;

  /// For a horizontal (row-append) bar, the full width to visually span.
  /// Null for the vertical (column-append) handle, which only ever needs
  /// its own single cell's height.
  final double? spanWidth;

  @override
  State<_HoverAddHandle> createState() => _HoverAddHandleState();
}

class _HoverAddHandleState extends State<_HoverAddHandle> {
  bool _isHovered = false;

  void _setHovered(bool value) {
    if (_isHovered != value) {
      setState(() {
        _isHovered = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlightColor = Theme.of(context).colorScheme.primary;

    final bar = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      color: _isHovered
          ? highlightColor.withValues(alpha: 0.12)
          : Colors.transparent,
      alignment: Alignment.center,
      child: _isHovered
          ? Icon(Icons.add, size: 14, color: highlightColor)
          : null,
    );

    final handle = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: const Duration(milliseconds: 300),
          child: bar,
        ),
      ),
    );

    if (widget.spanWidth == null) {
      return handle;
    }

    // Row-append handle: visually and interactively span the full table
    // width, not just this one Table cell, using an OverflowBox so the
    // hover/tap target matches the reference screenshot's full-width bar.
    return OverflowBox(
      minWidth: widget.spanWidth,
      maxWidth: widget.spanWidth,
      alignment: Alignment.centerLeft,
      child: handle,
    );
  }
}