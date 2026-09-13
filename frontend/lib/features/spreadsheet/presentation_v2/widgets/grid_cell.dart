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
  });

  final int row;
  final int column;
  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

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
  }

  void _handleFocusChange() {
    // Losing focus while this cell is the one being edited means the user
    // clicked elsewhere (another cell, outside the grid, etc.) without
    // pressing Enter/Tab first. Standard spreadsheet behavior is to
    // commit in that case, not silently discard the edit.
    if (!_focusNode.hasFocus && _isThisCellActive &&
        widget.viewportController.isEditing) {
      _commit();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isThisCellActive =>
      widget.viewportController.selection.startRow == widget.row &&
      widget.viewportController.selection.startColumn == widget.column;

  void _commit() {
    widget.spreadsheetController.editCell(
      row: widget.row,
      column: widget.column,
      value: _textController.text,
    );
    widget.viewportController.stopEditing();
  }

  void _cancel() {
    widget.viewportController.stopEditing();
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

        // Detect the transition into edit mode for THIS cell and seed the
        // local text buffer accordingly. This only runs once per edit
        // session (guarded by _wasEditing), not on every rebuild, so we
        // never stomp on what the user is actively typing.
        if (isEditingThisCell && !_wasEditing) {
          final replaceValue = widget.viewportController.replaceInitialValue;
          final initialValue = widget.viewportController.initialEditValue;
          _textController.text = replaceValue
              ? (initialValue ?? '')
              : (cell.formula ?? cell.value);
          _textController.selection = TextSelection.collapsed(
            offset: _textController.text.length,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _focusNode.requestFocus();
            }
          });
        }
        _wasEditing = isEditingThisCell;

        if (isEditingThisCell) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.blue, width: 2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (event) {
                if (event is! KeyDownEvent) {
                  return;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _cancel();
                } else if (event.logicalKey ==
                        LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  // TextField's onSubmitted handles Enter already; Tab
                  // is handled here since TextField doesn't fire
                  // onSubmitted for it.
                  if (event.logicalKey == LogicalKeyboardKey.tab) {
                    _commit();
                  }
                }
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
                onSubmitted: (_) => _commit(),
              ),
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.viewportController.selectCell(widget.row, widget.column);
          },
          onDoubleTap: () {
            widget.viewportController
                .selectCell(widget.row, widget.column);
            widget.viewportController.startEditing();
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