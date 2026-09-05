import 'dart:async';

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
import '../../../models/selection_model.dart';
import '../../../models/cell_position.dart';
import '../../../controllers/spreadsheet_controller.dart';
import '../../../services/formula_dependency_graph.dart';

class SpreadsheetViewport extends StatefulWidget {
  const SpreadsheetViewport({
    super.key,
    required this.viewportController,
    required this.spreadsheetController,
    required this.spreadsheet,
    required this.focusNode,
  });

  final ViewportController viewportController;
  final SpreadsheetController spreadsheetController;
  final SpreadsheetModel spreadsheet;
  final FocusNode focusNode;

  static const double rowHeaderWidth = 48;
  static const double columnHeaderHeight = 32;

  @override
  State<SpreadsheetViewport> createState() =>
      _SpreadsheetViewportState();
}

class _SpreadsheetViewportState
    extends State<SpreadsheetViewport> {
  late final ScrollCoordinator _scroll;

  int? _lastSelectedRow;
  int? _lastSelectedColumn;

  Size? _cellViewportSize;
  final ValueNotifier<String?> _formulaReferenceInsertion =
      ValueNotifier(null);
  CellPosition? _formulaReferenceStart;
  CellPosition? _formulaReferenceEnd;

  @override
  void initState() {
    super.initState();

    _scroll = ScrollCoordinator(
      viewportController: widget.viewportController,
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
    _formulaReferenceInsertion.dispose();

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

    widget.focusNode.requestFocus();
  }

  void _restoreSpreadsheetFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _requestSpreadsheetFocus();
    });
  }

  void _startFormulaReferenceSelection(Offset offset) {
    final position = widget.viewportController.positionFromPixel(
      x: offset.dx,
      y: offset.dy,
    );
    final viewport = widget.viewportController.viewport;
    final address = FormulaDependencyGraph.addressFor(
      row: position.row,
      column: position.column,
    );
    debugPrint(
      '[FormulaReference.position] pixel=(${offset.dx},${offset.dy}) '
      'scroll=(${viewport.scrollX},${viewport.scrollY}) zoom=${viewport.zoom} '
      'resolvedRow=${position.row} resolvedColumn=${position.column} '
      'address=$address',
    );
    debugPrint(
      '[FormulaReference.pointer] pixel=(${offset.dx},${offset.dy}) '
      'scroll=(${widget.viewportController.viewport.scrollX},'
      '${widget.viewportController.viewport.scrollY}) '
      'resolved=(${position.row},${position.column})',
    );

    setState(() {
      _formulaReferenceStart = position;
      _formulaReferenceEnd = position;
    });
  }

  void _updateFormulaReferenceSelection(Offset offset) {
    if (_formulaReferenceStart == null) {
      return;
    }

    final position = widget.viewportController.positionFromPixel(
      x: offset.dx,
      y: offset.dy,
    );
    debugPrint(
      '[FormulaReference.pointer] pixel=(${offset.dx},${offset.dy}) '
      'scroll=(${widget.viewportController.viewport.scrollX},'
      '${widget.viewportController.viewport.scrollY}) '
      'resolved=(${position.row},${position.column})',
    );

    setState(() {
      _formulaReferenceEnd = position;
    });
  }

  void _finishFormulaReferenceSelection(Offset offset) {
    final start = _formulaReferenceStart;
    if (start == null) {
      return;
    }

    final end = widget.viewportController.positionFromPixel(
      x: offset.dx,
      y: offset.dy,
    );
    debugPrint(
      '[FormulaReference.pointer] pixel=(${offset.dx},${offset.dy}) '
      'scroll=(${widget.viewportController.viewport.scrollX},'
      '${widget.viewportController.viewport.scrollY}) '
      'resolved=(${end.row},${end.column})',
    );
    final firstRow = start.row < end.row ? start.row : end.row;
    final lastRow = start.row > end.row ? start.row : end.row;
    final firstColumn = start.column < end.column
        ? start.column
        : end.column;
    final lastColumn = start.column > end.column
        ? start.column
        : end.column;
    final firstReference = FormulaDependencyGraph.addressFor(
      row: firstRow,
      column: firstColumn,
    );
    final lastReference = FormulaDependencyGraph.addressFor(
      row: lastRow,
      column: lastColumn,
    );
    final reference = firstRow == lastRow && firstColumn == lastColumn
        ? firstReference
        : '$firstReference:$lastReference';
    debugPrint(
      '[FormulaReference.range] start=(${start.row},${start.column}) '
      'end=(${end.row},${end.column}) address=$reference',
    );

    _formulaReferenceInsertion.value = reference;

    setState(() {
      _formulaReferenceStart = null;
      _formulaReferenceEnd = null;
    });
  }

  void _handleViewportPointerDown() {
    if (!widget.viewportController.isEditing) {
      _requestSpreadsheetFocus();
    }
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
    // CTRL/CMD + C → COPY SELECTION
    // ==========================================================

    final copyModifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (copyModifier &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      widget.spreadsheetController.copySelection(
        viewportController.selection,
      );

      return KeyEventResult.handled;
    }

    // ==========================================================
    // CTRL/CMD + X → CUT SELECTION
    // ==========================================================

    if (copyModifier &&
        event.logicalKey == LogicalKeyboardKey.keyX) {
      final selection = viewportController.selection;

      unawaited(_cutSelection(selection));

      return KeyEventResult.handled;
    }

    // ==========================================================
    // CTRL/CMD + V → PASTE CLIPBOARD
    // ==========================================================

    if (copyModifier &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteClipboard(viewportController);

      return KeyEventResult.handled;
    }

    // ==========================================================
    // CTRL/CMD + Z → UNDO
    // ==========================================================

    if (copyModifier &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.spreadsheetController.undo();

      return KeyEventResult.handled;
    }

    // ==========================================================
    // CTRL/CMD + Y or CTRL/CMD + SHIFT + Z → REDO
    // ==========================================================

    if (copyModifier &&
        (event.logicalKey == LogicalKeyboardKey.keyY ||
            (event.logicalKey == LogicalKeyboardKey.keyZ &&
                HardwareKeyboard.instance.isShiftPressed))) {
      widget.spreadsheetController.redo();

      return KeyEventResult.handled;
    }

    // ==========================================================
    // ENTER → EDIT CURRENT CELL
    // ==========================================================

    if (event.logicalKey ==
        LogicalKeyboardKey.enter) {
      debugPrint(
        '[SpreadsheetViewport] editing begins at '
        '(${viewportController.selection.startRow}, '
        '${viewportController.selection.startColumn})',
      );
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

    final shiftPressed =
        HardwareKeyboard.instance.isShiftPressed;

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowLeft) {
      if (shiftPressed) {
        viewportController.extendSelectionLeft();
      } else {
        viewportController.moveLeft();
      }

      return KeyEventResult.handled;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowRight) {
      if (shiftPressed) {
        viewportController.extendSelectionRight();
      } else {
        viewportController.moveRight();
      }

      return KeyEventResult.handled;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowUp) {
      if (shiftPressed) {
        viewportController.extendSelectionUp();
      } else {
        viewportController.moveUp();
      }

      return KeyEventResult.handled;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowDown) {
      if (shiftPressed) {
        viewportController.extendSelectionDown();
      } else {
        viewportController.moveDown();
      }

      return KeyEventResult.handled;
    }

    // ==========================================================
    // DELETE / BACKSPACE → CLEAR SELECTION
    // ==========================================================

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.spreadsheetController.clearSelection(
        viewportController.selection,
      );

      return KeyEventResult.handled;
    }

    // ==========================================================
    // DIRECT TYPING
    // ==========================================================

    final character = event.character;

    if (character != null &&
        character.isNotEmpty &&
        !_isControlCharacter(character)) {
      debugPrint(
        '[SpreadsheetViewport] editing begins at '
        '(${viewportController.selection.startRow}, '
        '${viewportController.selection.startColumn}) '
        'with initial text "$character"',
      );
      viewportController.startEditing(
        replaceInitialValue: true,
        initialValue: character,
      );

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ============================================================
  // CLIPBOARD OPERATIONS
  // ============================================================

  Future<void> _cutSelection(SelectionModel selection) async {
    // Copy to clipboard first
    await widget.spreadsheetController.copySelection(selection);
    
    // Then clear the source cells
    widget.spreadsheetController.clearSelection(selection);
  }

  Future<void> _pasteClipboard(
    ViewportController viewportController,
  ) async {
    final clipboardData =
        await Clipboard.getData(Clipboard.kTextPlain);

    final clipboardText = clipboardData?.text;

    if (clipboardText == null || clipboardText.isEmpty) {
      return;
    }

    await widget.spreadsheetController.pasteClipboard(
      row: viewportController.selection.activeRow,
      column: viewportController.selection.activeColumn,
      clipboardText: clipboardText,
    );
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
      focusNode: widget.focusNode,
      onKeyEvent: _handleKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _handleViewportPointerDown(),
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
                                onFormulaReferencePointerDown:
                                  _startFormulaReferenceSelection,
                                onFormulaReferencePointerMove:
                                  _updateFormulaReferenceSelection,
                                onFormulaReferencePointerUp:
                                  _finishFormulaReferenceSelection,
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
                                focusNode: widget.focusNode,
                                referenceInsertion:
                                  _formulaReferenceInsertion,
                                formulaReferenceStart:
                                  _formulaReferenceStart,
                                formulaReferenceEnd:
                                  _formulaReferenceEnd,
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