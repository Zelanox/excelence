import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/spreadsheet_controller.dart';
import '../../controllers/viewport_controller.dart';
import '../../models/selection_model.dart';

/// A single spreadsheet cell.
///
/// This widget derives everything it SHOWS from [spreadsheetController]
/// and [viewportController] - the committed cell value, whether it's
/// selected, whether it's the active editing target. This is deliberate:
/// the long-term goal is real-time multi-user editing, where a cell's
/// appearance must be able to change because of a REMOTE user's action,
/// not just a local one. By deriving committed content from the
/// controllers, a future remote-update mechanism only has to update the
/// controller/model - every cell watching it updates automatically.
///
/// The one exception is the in-progress text of an active edit. While
/// typing, keystrokes are NOT sent to SpreadsheetController on every
/// character - only on commit (Enter/Tab/click-away) or discarded on
/// cancel (Escape). That in-progress buffer is genuinely local/transient
/// input state (comparable to an unsent chat message draft) and lives in
/// this widget's State via a TextEditingController. No other cell, and no
/// other user, needs to see it - only the committed value matters once
/// this cell stops being the one actively edited.
class GridCell extends StatefulWidget {
  const GridCell({
    super.key,
    required this.row,
    required this.column,
    required this.spreadsheetController,
    required this.viewportController,
    required this.gridFocusNode,
    this.onDragStart,
    this.onDragEnter,
    this.onDragEnd,
    this.isFormulaReferencePickingActive = false,
    this.onCellTapDuringFormulaEdit,
    this.onFormulaEditingChanged,
    this.formulaReferenceToInsert,
  });

  final int row;
  final int column;
  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  /// The parent SpreadsheetGrid's FocusNode. Reclaimed by this cell after
  /// committing an edit (Enter/Tab), since committing moves selection and
  /// swaps this cell back to its non-editing (GestureDetector) form -
  /// without explicitly requesting it, keyboard focus would otherwise be
  /// left on the just-disposed TextField's focus node, leaving arrow-key
  /// navigation unresponsive until the user clicks or tabs manually.
  final FocusNode gridFocusNode;

  /// Called when a drag gesture begins on this cell (mouse-down + move).
  /// The grid uses this to start a range selection anchored here.
  final void Function(int row, int column)? onDragStart;

  /// Called when the pointer enters this cell's bounds while a drag is in
  /// progress (regardless of which cell the drag started on). The grid
  /// uses this to extend the in-progress range selection to include this
  /// cell.
  final void Function(int row, int column)? onDragEnter;

  /// Called when the drag gesture ends (mouse-up) on this cell.
  final VoidCallback? onDragEnd;

  /// True when SOME cell elsewhere in the grid is actively being edited
  /// with formula text (starting with "="). While true, a plain tap on
  /// THIS cell (when this cell is not itself the one being edited) means
  /// "insert my reference into that formula" rather than the normal
  /// "commit the other edit and select me".
  final bool isFormulaReferencePickingActive;

  /// Called when this cell is tapped while
  /// [isFormulaReferencePickingActive] is true and this cell is not
  /// itself being edited. The grid uses this to compute this cell's
  /// address (e.g. "B3") and route it to the editing cell.
  final void Function(int row, int column)? onCellTapDuringFormulaEdit;

  /// Called by the actively-editing cell whenever its own in-progress
  /// text transitions into or out of being a formula (starts with "=").
  /// The grid uses this to decide whether OTHER cells' taps should be
  /// treated as reference-picking.
  final void Function(bool isFormula)? onFormulaEditingChanged;

  /// Carries a clicked cell's reference text (e.g. "B3") down to whichever
  /// cell is actively editing, so it can splice that text into its own
  /// TextField. Only meaningful to the currently-editing cell - every
  /// other cell ignores it.
  final ValueNotifier<String?>? formulaReferenceToInsert;

  @override
  State<GridCell> createState() => _GridCellState();
}

class _GridCellState extends State<GridCell> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _wasEditing = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _textController.addListener(_handleTextChanged);
  }

  void _handleFocusChange() {
    debugPrint(
      '[GridCell._handleFocusChange] row=${widget.row} '
      'column=${widget.column} hasFocus=${_focusNode.hasFocus} '
      'isThisCellActive=$_isThisCellActive '
      'viewportIsEditing=${widget.viewportController.isEditing} '
      'isFormula=$_isFormula',
    );
    // Losing focus while this cell is the one being edited means the user
    // clicked elsewhere (another cell, outside the grid, etc.) without
    // pressing Enter/Tab first. Standard spreadsheet behavior is to
    // commit in that case, not silently discard the edit.
    //
    // EXCEPTION: while formula-reference-picking is active, clicking
    // another cell is meant to insert a reference, not commit/leave this
    // cell - so focus loss during that specific interaction must NOT
    // trigger a commit. _isPickingReferences (tracked via the last
    // reported isFormula state) tells us that.
    if (!_focusNode.hasFocus &&
        _isThisCellActive &&
        widget.viewportController.isEditing &&
        !_isFormula) {
      debugPrint('[GridCell._handleFocusChange] COMMITTING due to focus loss');
      _commit();
    }
  }

  bool _isFormula = false;
  bool _isListeningForReferences = false;

  void _handleTextChanged() {
    final isFormulaNow = _textController.text.startsWith('=');
    if (isFormulaNow != _isFormula) {
      _isFormula = isFormulaNow;
      widget.onFormulaEditingChanged?.call(isFormulaNow);
    }
  }

  void _handleReferenceToInsert() {
    final reference = widget.formulaReferenceToInsert?.value;
    if (reference == null || reference.isEmpty) {
      return;
    }
    debugPrint(
      '[GridCell._handleReferenceToInsert] row=${widget.row} '
      'column=${widget.column} reference="$reference" '
      'focusHasFocus=${_focusNode.hasFocus} '
      'primaryFocus=${FocusManager.instance.primaryFocus}',
    );
    // Consume it immediately so it isn't re-applied on a future rebuild.
    widget.formulaReferenceToInsert!.value = null;

    final selection = _textController.selection;
    final text = _textController.text;
    final insertAt = selection.isValid ? selection.start : text.length;
    final newText =
        text.replaceRange(insertAt, selection.isValid ? selection.end : insertAt, reference);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + reference.length),
    );
    debugPrint(
      '[GridCell._handleReferenceToInsert] after insert, '
      'focusHasFocus=${_focusNode.hasFocus} '
      'primaryFocus=${FocusManager.instance.primaryFocus}',
    );
  }

  void _syncReferenceListener() {
    final shouldListen = _isThisCellActive &&
        widget.viewportController.isEditing &&
        widget.formulaReferenceToInsert != null;

    if (shouldListen && !_isListeningForReferences) {
      widget.formulaReferenceToInsert!.addListener(_handleReferenceToInsert);
      _isListeningForReferences = true;
    } else if (!shouldListen && _isListeningForReferences) {
      widget.formulaReferenceToInsert!
          .removeListener(_handleReferenceToInsert);
      _isListeningForReferences = false;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _textController.removeListener(_handleTextChanged);
    if (_isListeningForReferences) {
      widget.formulaReferenceToInsert?.removeListener(
        _handleReferenceToInsert,
      );
    }
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isThisCellActive =>
      widget.viewportController.selection.startRow == widget.row &&
      widget.viewportController.selection.startColumn == widget.column;

  /// Builds the cell's border. A plain unselected cell gets a uniform
  /// light gridline. Any cell within the current selection - including
  /// the active cell (the drag anchor / single selected cell) - only
  /// draws a blue line on the sides given by [edges] that sit on the
  /// outer boundary of the range; interior sides between two selected
  /// neighbors get the plain gridline instead. This applies equally to
  /// the active cell: being the drag anchor does not mean it sits on the
  /// range's boundary (e.g. it can be the top-left corner of a range
  /// dragged down-and-right, in which case only its top and left sides
  /// are actually on the boundary).
  Border _cellBorder({
    required _SelectionEdges? edges,
  }) {
    final gridline = BorderSide(color: Colors.grey.shade300, width: 0.5);
    final rangeLine = BorderSide(color: Colors.blue, width: 2);

    if (edges == null) {
      return Border.fromBorderSide(gridline);
    }

    return Border(
      top: edges.top ? rangeLine : gridline,
      bottom: edges.bottom ? rangeLine : gridline,
      left: edges.left ? rangeLine : gridline,
      right: edges.right ? rangeLine : gridline,
    );
  }

  void _commit() {
    widget.spreadsheetController.editCell(
      row: widget.row,
      column: widget.column,
      value: _textController.text,
    );
    widget.viewportController.stopEditing();
    _resetFormulaEditingState();

    // Return keyboard focus to the grid so arrow-key navigation works
    // immediately after committing, without requiring an extra click or
    // Tab press. Deferred to the next frame since this cell is mid-swap
    // from its editing (TextField) form back to its plain form.
    //
    // Guarded against widget.viewportController.isEditing: if committing
    // this cell was triggered by a double-click landing on a DIFFERENT
    // cell (which starts editing that cell in the same gesture), we must
    // not steal focus back from that new cell's TextField.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.viewportController.isEditing) {
        widget.gridFocusNode.requestFocus();
      }
    });
  }

  void _commitAndMoveDown() {
    _commit();
    widget.viewportController.moveDown();
  }

  void _commitAndMoveRight() {
    _commit();
    widget.viewportController.moveRight();
  }

  void _cancel() {
    widget.viewportController.stopEditing();
    _resetFormulaEditingState();
  }

  void _resetFormulaEditingState() {
    if (_isFormula) {
      _isFormula = false;
      widget.onFormulaEditingChanged?.call(false);
    }
    _syncReferenceListener();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to both controllers. Content can change from an edit
    // (spreadsheetController) and selection/editing-mode can change
    // independently (viewportController) - a cell needs to redraw for
    // either.
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.spreadsheetController,
        widget.viewportController,
      ]),
      builder: (context, _) {
        final sheet =
            widget.spreadsheetController.spreadsheet?.activeSheet;
        if (sheet == null ||
            widget.row < 0 ||
            widget.row >= sheet.rows.length) {
          return const SizedBox.shrink();
        }

        final cells = sheet.rows[widget.row].cells;
        if (widget.column < 0 || widget.column >= cells.length) {
          return const SizedBox.shrink();
        }

        final cell = cells[widget.column];

        final selection = widget.viewportController.selection;
        final isSelected =
            _isWithinSelection(selection, widget.row, widget.column);
        final isActiveCell = _isThisCellActive;
        final isEditingThisCell =
            isActiveCell && widget.viewportController.isEditing;

        // Which edges of THIS cell sit on the outer boundary of the
        // current selection range, so only those edges get a "range
        // border" drawn - giving one unified outline around the whole
        // selection instead of every selected cell drawing its own full
        // border.
        final selectionEdges = isSelected
            ? _selectionEdges(selection, widget.row, widget.column)
            : null;

        // Detect the transition into edit mode for THIS cell and seed the
        // local text buffer accordingly. This only runs once per edit
        // session (guarded by _wasEditing), not on every rebuild, so we
        // never stomp on what the user is actively typing.
        if (isEditingThisCell && !_wasEditing) {
          final replaceValue = widget.viewportController.replaceInitialValue;
          final initialValue = widget.viewportController.initialEditValue;

          // Seeding _textController.text below fires our OWN listener
          // (_handleTextChanged, attached in initState) synchronously,
          // as part of this same build - and if the seeded text is a
          // formula, that listener calls
          // widget.onFormulaEditingChanged -> SpreadsheetGrid.setState()
          // while SpreadsheetGrid (our ancestor) is still mid-build,
          // which Flutter forbids and throws for. Removing the listener
          // for just this programmatic assignment avoids that; we run
          // the equivalent check manually afterward, deferred to after
          // this frame completes.
          _textController.removeListener(_handleTextChanged);
          _textController.text = replaceValue
              ? (initialValue ?? '')
              : (cell.formula ?? cell.value);
          _textController.selection = TextSelection.collapsed(
            offset: _textController.text.length,
          );
          _textController.addListener(_handleTextChanged);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _handleTextChanged();
              _focusNode.requestFocus();
              debugPrint(
                '[GridCell] requested focus for row=${widget.row} '
                'column=${widget.column}, hasFocus after request='
                '${_focusNode.hasFocus}, '
                'primaryFocus=${FocusManager.instance.primaryFocus}',
              );
            }
          });
        }
        _wasEditing = isEditingThisCell;
        _syncReferenceListener();

        if (isEditingThisCell) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.blue, width: 2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Focus(
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _cancel();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.tab) {
                  // TextField/EditableText has its own built-in Tab
                  // handling (focus traversal to the next widget) which
                  // would otherwise ALSO fire alongside our own
                  // commit-and-move, causing a double move. Returning
                  // "handled" here stops that built-in behavior from
                  // running at all - we fully own Tab's meaning inside
                  // an editing cell.
                  _commitAndMoveRight();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                autofocus: true,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (_) => _commitAndMoveDown(),
              ),
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) {
            widget.onDragEnter?.call(widget.row, widget.column);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (widget.isFormulaReferencePickingActive) {
                widget.onCellTapDuringFormulaEdit
                    ?.call(widget.row, widget.column);
                return;
              }
              widget.viewportController
                  .selectCell(widget.row, widget.column);
            },
            onDoubleTap: () {
              if (widget.isFormulaReferencePickingActive) {
                // Double-clicking a cell while picking a formula
                // reference still just means "insert this reference" -
                // it should not also start editing THIS cell.
                widget.onCellTapDuringFormulaEdit
                    ?.call(widget.row, widget.column);
                return;
              }
              widget.viewportController
                  .selectCell(widget.row, widget.column);
              widget.viewportController.startEditing();
            },
            onPanStart: widget.isFormulaReferencePickingActive
                ? null
                : (_) {
                    widget.onDragStart?.call(widget.row, widget.column);
                  },
            onPanEnd: widget.isFormulaReferencePickingActive
                ? null
                : (_) {
                    widget.onDragEnd?.call();
                  },
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withValues(alpha: 0.08)
                    : Colors.white,
                border: _cellBorder(
                  edges: selectionEdges,
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

  /// Returns which sides of the cell at (row, column) sit on the outer
  /// boundary of the current selection range - e.g. the top-left cell of
  /// a multi-cell range has its top and left edges on the boundary, but
  /// not its bottom/right (since a selected neighbor continues there).
  /// Only called when the cell is already known to be within the
  /// selection.
  _SelectionEdges _selectionEdges(
    SelectionModel selection,
    int row,
    int column,
  ) {
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

    return _SelectionEdges(
      top: row == firstRow,
      bottom: row == lastRow,
      left: column == firstColumn,
      right: column == lastColumn,
    );
  }
}

/// Which sides of a single cell sit on the outer boundary of the current
/// selection range.
class _SelectionEdges {
  const _SelectionEdges({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  final bool top;
  final bool bottom;
  final bool left;
  final bool right;
}