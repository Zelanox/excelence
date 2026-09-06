import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/cell_position.dart';
import '../../../models/spreadsheet_model.dart';
import '../../../models/visible_range_model.dart';

import 'cell_metrics.dart';
import 'grid_painter.dart';
import 'cell_painter.dart';

class CellCanvas extends StatefulWidget {
  const CellCanvas({
    super.key,
    required this.horizontalController,
    required this.verticalController,
    required this.viewportController,
    required this.spreadsheet,
    this.onFormulaReferencePointerDown,
    this.onFormulaReferencePointerMove,
    this.onFormulaReferencePointerUp,
  });

  final ScrollController horizontalController;
  final ScrollController verticalController;
  final ViewportController viewportController;
  final SpreadsheetModel spreadsheet;
  final ValueChanged<Offset>? onFormulaReferencePointerDown;
  final ValueChanged<Offset>? onFormulaReferencePointerMove;
  final ValueChanged<Offset>? onFormulaReferencePointerUp;

  @override
  State<CellCanvas> createState() => _CellCanvasState();
}

class _CellCanvasState extends State<CellCanvas> {
  bool _isDragging = false;
  CellPosition? _lastFormulaReferencePosition;

  @override
  void initState() {
    super.initState();

    widget.viewportController.addListener(_onViewportChanged);
  }

  void _onViewportChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  void dispose() {
    widget.viewportController.removeListener(_onViewportChanged);

    super.dispose();
  }

  // ============================================================
  // MOUSE SELECTION
  // ============================================================

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }

    if ((event.buttons & kPrimaryButton) == 0) {
      return;
    }

    if (widget.viewportController.isEditing &&
        widget.onFormulaReferencePointerDown != null) {
      _isDragging = true;
      final position = widget.viewportController.positionFromPixel(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
      );
      _lastFormulaReferencePosition = position;
      debugPrint(
        '[FormulaReference.pointerDown] '
        'local=(${event.localPosition.dx},${event.localPosition.dy}) '
        'global=(${event.position.dx},${event.position.dy}) '
        'scroll=(${widget.viewportController.viewport.scrollX},'
        '${widget.viewportController.viewport.scrollY})',
      );
      widget.onFormulaReferencePointerDown!(event.localPosition);
      return;
    }

    _isDragging = true;

    widget.viewportController.startSelectionFromPixel(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDragging) {
      return;
    }

    if ((event.buttons & kPrimaryButton) == 0) {
      return;
    }

    if (widget.viewportController.isEditing &&
        widget.onFormulaReferencePointerMove != null) {
      final position = widget.viewportController.positionFromPixel(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
      );
      if (_lastFormulaReferencePosition?.row != position.row ||
          _lastFormulaReferencePosition?.column != position.column) {
        _lastFormulaReferencePosition = position;
        debugPrint(
          '[FormulaReference.pointerMove] '
          'local=(${event.localPosition.dx},${event.localPosition.dy}) '
          'resolved=(${position.row},${position.column}) '
          'scroll=(${widget.viewportController.viewport.scrollX},'
          '${widget.viewportController.viewport.scrollY})',
        );
      }
      widget.onFormulaReferencePointerMove!(event.localPosition);
    } else {
      widget.viewportController.updateSelectionFromPixel(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }

    _isDragging = false;
    if (widget.viewportController.isEditing &&
        widget.onFormulaReferencePointerUp != null) {
      final position = widget.viewportController.positionFromPixel(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
      );
      debugPrint(
        '[FormulaReference.pointerUp] '
        'local=(${event.localPosition.dx},${event.localPosition.dy}) '
        'resolved=(${position.row},${position.column})',
      );
      widget.onFormulaReferencePointerUp!(event.localPosition);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        final sheet = widget.spreadsheet.activeSheet;

        final totalRows = sheet.rows.length;

        final totalColumns = sheet.rows.isEmpty
            ? 0
            : sheet.rows
                .map((row) => row.cells.length)
                .fold<int>(
                  0,
                  (max, length) => length > max ? length : max,
                );

        if (totalRows == 0 || totalColumns == 0) {
          return const SizedBox.expand();
        }

        final VisibleRangeModel visibleRange =
            widget.viewportController.getVisibleRange(
          viewportSize: viewportSize,
          totalRows: totalRows,
          totalColumns: totalColumns,
        );

        return GestureDetector(
          behavior: HitTestBehavior.translucent,

          // Double-click → edit the selected cell.
          onDoubleTap: widget.viewportController.isEditing
              ? null
              : () {
            debugPrint(
              '[CellCanvas] editing begins at '
              '(${widget.viewportController.selection.startRow}, '
              '${widget.viewportController.selection.startColumn})',
            );
            widget.viewportController.startEditing();
          },

          child: Listener(
            behavior: HitTestBehavior.opaque,

            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,

            child: ScrollConfiguration(
              behavior: const _SpreadsheetScrollBehavior(),
              child: SingleChildScrollView(
                controller: widget.verticalController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  controller: widget.horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width:
                        CellMetrics.columnWidth * totalColumns,
                    height:
                        CellMetrics.rowHeight * totalRows,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size.infinite,
                          painter: GridPainter(
                            visibleRange: visibleRange,
                          ),
                        ),

                        CustomPaint(
                          size: Size.infinite,
                          painter: CellPainter(
                            spreadsheet: widget.spreadsheet,
                            visibleRange: visibleRange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mouse dragging belongs to cell selection.
///
/// Touch/stylus dragging may still be used by the
/// ScrollViews for scrolling.
class _SpreadsheetScrollBehavior extends MaterialScrollBehavior {
  const _SpreadsheetScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      };
}
