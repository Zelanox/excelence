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

  @override
  void initState() {
    super.initState();

    _scroll = ScrollCoordinator(
      viewportController: widget.viewportController,
    );

    _focusNode = FocusNode(
      debugLabel: 'SpreadsheetViewportFocus',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestSpreadsheetFocus();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
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
                    child: Stack(
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