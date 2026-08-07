import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cell_canvas.dart';
import 'column_header.dart';
import 'corner_cell.dart';
import 'row_header.dart';
import 'scroll_coordinator.dart';
import 'keyboard_handler.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/spreadsheet_model.dart';

class SpreadsheetViewport extends StatefulWidget {
  const SpreadsheetViewport({
    super.key,
    required this.viewportController,
    required this.spreadsheet,
  });

  final ViewportController viewportController;
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

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.viewportController.moveLeft();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.viewportController.moveRight();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.viewportController.moveUp();
      return KeyEventResult.handled;
    }

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

          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: SpreadsheetViewport.rowHeaderWidth,
                  child: RowHeader(
                    controller: _scroll.vertical,
                  ),
                ),

                Expanded(
                  child: Stack(
                    children: [

                      CellCanvas(
                        horizontalController: _scroll.horizontal,
                        verticalController: _scroll.vertical,
                        viewportController:
                            widget.viewportController,
                        spreadsheet: widget.spreadsheet,
                      ),

                      AnimatedBuilder(
                        animation: widget.viewportController,
                        builder: (context, _) {
                          final selection =
                              widget.viewportController.selection;

                          const cellWidth = 80.0;
                          const cellHeight = 28.0;

                          final left =
                              selection.startColumn * cellWidth -
                              widget.viewportController.viewport.scrollX;

                          final top =
                              selection.startRow * cellHeight -
                              widget.viewportController.viewport.scrollY;

                          return IgnorePointer(
                            child: Stack(
                              children: [
                                Positioned(
                                  left: left,
                                  top: top,
                                  width: cellWidth,
                                  height: cellHeight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.blue,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
}