import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cell_canvas.dart';
import 'column_header.dart';
import 'corner_cell.dart';
import 'row_header.dart';
import 'scroll_coordinator.dart';
import 'keyboard_handler.dart';
import 'selection_overlay.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/spreadsheet_model.dart';
import '../../../controllers/spreadsheet_controller.dart';

class SpreadsheetViewport extends StatefulWidget {
  const SpreadsheetViewport({
    super.key,
    required this.viewportController,
    required this.spreadsheetController,
    required this.spreadsheet,
  });

  final ViewportController viewportController;
  final SpreadsheetController spreadsheetController;
  final SpreadsheetModel spreadsheet;

  static const double rowHeaderWidth = 48;
  static const double columnHeaderHeight = 32;

  @override
  State<SpreadsheetViewport> createState() =>
      _SpreadsheetViewportState();
}

class _SpreadsheetViewportState
    extends State<SpreadsheetViewport> {
  late final ScrollCoordinator _scroll;
  late final FocusNode _focusNode;

  int? _lastSelectedRow;
  int? _lastSelectedColumn;

  Size? _cellViewportSize;

  @override
  void initState() {
    super.initState();

    _scroll = ScrollCoordinator(
      viewportController: widget.viewportController,
    );

    _focusNode = FocusNode(
      debugLabel: 'SpreadsheetViewportFocus',
    );

    widget.viewportController.addListener(
      _onViewportControllerChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestSpreadsheetFocus();
      }
    });
  }

  @override
  void dispose() {
    widget.viewportController.removeListener(
      _onViewportControllerChanged,
    );

    _scroll.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  // ============================================================
  // SELECTION / VIEWPORT
  // ============================================================

  void _onViewportControllerChanged() {
    if (!mounted) {
      return;
    }

    final selection = widget.viewportController.selection;

    final row = selection.startRow;
    final column = selection.startColumn;

    // Ignore notifications caused only by scrolling.
    if (_lastSelectedRow == row &&
        _lastSelectedColumn == column) {
      return;
    }

    _lastSelectedRow = row;
    _lastSelectedColumn = column;

    final viewportSize = _cellViewportSize;

    if (viewportSize == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final currentSize = _cellViewportSize;

      if (currentSize == null) {
        return;
      }

      widget.viewportController.ensureVisible(
        row: row,
        column: column,
        viewportSize: currentSize,
      );
    });
  }

  // ============================================================
  // FOCUS
  // ============================================================

  void _requestSpreadsheetFocus() {
    if (!mounted) {
      return;
    }

    _focusNode.requestFocus();
  }

  void _restoreSpreadsheetFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _requestSpreadsheetFocus();
    });
  }

  // ============================================================
  // KEYBOARD
  // ============================================================

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final viewportController =
        widget.viewportController;

    // ==========================================================
    // NEVER HANDLE SPREADSHEET KEYS WHILE CELL EDITOR IS ACTIVE
    // ==========================================================

    if (viewportController.isEditing) {
      return KeyEventResult.ignored;
    }

    // ==========================================================
    // ENTER → EDIT CURRENT CELL
    // ==========================================================

    if (event.logicalKey ==
        LogicalKeyboardKey.enter) {
      viewportController.startEditing();

      return KeyEventResult.handled;
    }

    // ==========================================================
    // ESCAPE
    // ==========================================================

    if (event.logicalKey ==
        LogicalKeyboardKey.escape) {
      viewportController.stopEditing();

      _restoreSpreadsheetFocus();

      return KeyEventResult.handled;
    }

    // ==========================================================
    // TAB NAVIGATION
    // ==========================================================

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        viewportController.movePrevious();
      } else {
        viewportController.moveNext();
      }

      return KeyEventResult.handled;
    }

    // ==========================================================
    // ARROW KEYS
    // ==========================================================

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowLeft) {
      viewportController.moveLeft();
      return KeyEventResult.handled;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowRight) {
      viewportController.moveRight();
      return KeyEventResult.handled;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowUp) {
      viewportController.moveUp();
      return KeyEventResult.handled;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowDown) {
      viewportController.moveDown();
      return KeyEventResult.handled;
    }

    // ==========================================================
    // DIRECT TYPING
    // ==========================================================

    final character = event.character;

    if (character != null &&
        character.isNotEmpty &&
        !_isControlCharacter(character)) {
      viewportController.startEditing(
        replaceInitialValue: true,
        initialValue: character,
      );

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isControlCharacter(String character) {
    if (character.isEmpty) {
      return true;
    }

    return character.codeUnitAt(0) < 32;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return KeyboardHandler(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _requestSpreadsheetFocus();
        },
        child: Column(
          children: [
            // ====================================================
            // COLUMN HEADER
            // ====================================================

            SizedBox(
              height:
                  SpreadsheetViewport.columnHeaderHeight,
              child: Row(
                children: [
                  const SizedBox(
                    width:
                        SpreadsheetViewport.rowHeaderWidth,
                    child: CornerCell(),
                  ),

                  Expanded(
                    child: ColumnHeader(
                      controller:
                          _scroll.horizontal,
                    ),
                  ),
                ],
              ),
            ),

            // ====================================================
            // SPREADSHEET BODY
            // ====================================================

            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width:
                        SpreadsheetViewport.rowHeaderWidth,
                    child: RowHeader(
                      controller:
                          _scroll.vertical,
                    ),
                  ),

                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _cellViewportSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );

                        return Stack(
                          children: [
                            // ----------------------------------------
                            // CELLS
                            // ----------------------------------------

                            CellCanvas(
                              horizontalController:
                                  _scroll.horizontal,
                              verticalController:
                                  _scroll.vertical,
                              viewportController:
                                  widget.viewportController,
                              spreadsheet:
                                  widget.spreadsheet,
                            ),

                            // ----------------------------------------
                            // SELECTION + EDITOR
                            // ----------------------------------------

                            SpreadsheetSelectionOverlay(
                              viewportController:
                                  widget.viewportController,
                              spreadsheet:
                                  widget.spreadsheet,
                              spreadsheetController:
                                  widget.spreadsheetController,
                              focusNode:
                                  _focusNode,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}