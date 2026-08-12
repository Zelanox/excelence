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

    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // Start editing
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.viewportController.startEditing();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });

      return KeyEventResult.handled;
    }

    // Cancel editing
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.viewportController.stopEditing();
      return KeyEventResult.handled;
    }

    // Move selection left
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.viewportController.moveLeft();
      return KeyEventResult.handled;
    }

    // Move selection right
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.viewportController.moveRight();
      return KeyEventResult.handled;
    }

    // Move selection up
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.viewportController.moveUp();
      return KeyEventResult.handled;
    }

    // Move selection down
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.viewportController.moveDown();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardHandler(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Column(
        children: [
          // ==========================================================
          // Column header
          // ==========================================================

          SizedBox(
            height: SpreadsheetViewport.columnHeaderHeight,
            child: Row(
              children: [
                const SizedBox(
                  width: SpreadsheetViewport.rowHeaderWidth,
                  child: CornerCell(),
                ),

                Expanded(
                  child: ColumnHeader(
                    controller: _scroll.horizontal,
                  ),
                ),
              ],
            ),
          ),

          // ==========================================================
          // Spreadsheet body
          // ==========================================================

          Expanded(
            child: Row(
              children: [
                // Row header
                SizedBox(
                  width: SpreadsheetViewport.rowHeaderWidth,
                  child: RowHeader(
                    controller: _scroll.vertical,
                  ),
                ),

                // Spreadsheet
                Expanded(
                  child: Stack(
                    children: [
                      // ------------------------------------------------
                      // Cells + grid
                      // ------------------------------------------------

                      CellCanvas(
                        horizontalController: _scroll.horizontal,
                        verticalController: _scroll.vertical,
                        viewportController:
                            widget.viewportController,
                        spreadsheet: widget.spreadsheet,
                      ),

                      // ------------------------------------------------
                      // Selection + cell editor
                      // ------------------------------------------------

                      SpreadsheetSelectionOverlay(
                        viewportController:
                            widget.viewportController,
                        spreadsheet: widget.spreadsheet,
                        spreadsheetController: widget.spreadsheetController,
                        focusNode: _focusNode,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _restoreFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

}