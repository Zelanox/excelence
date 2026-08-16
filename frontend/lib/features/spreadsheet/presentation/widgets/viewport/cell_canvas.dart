import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../../controllers/viewport_controller.dart';
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
  });

  final ScrollController horizontalController;
  final ScrollController verticalController;
  final ViewportController viewportController;
  final SpreadsheetModel spreadsheet;

  @override
  State<CellCanvas> createState() => _CellCanvasState();
}

class _CellCanvasState extends State<CellCanvas> {
  bool _isDragging = false;

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

    widget.viewportController.updateSelectionFromPixel(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }

    _isDragging = false;
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
          onDoubleTap: () {
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