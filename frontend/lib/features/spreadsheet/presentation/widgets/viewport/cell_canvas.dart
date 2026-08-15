import 'package:flutter/material.dart';

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
          behavior: HitTestBehavior.opaque,

          // Double-click → edit the selected cell.
          onDoubleTap: () {
            widget.viewportController.startEditing();
          },

          // Mouse button pressed.
          onPanDown: (details) {
            _isDragging = true;

            widget.viewportController.startSelectionFromPixel(
              x: details.localPosition.dx,
              y: details.localPosition.dy,
            );
          },

          // Mouse is being dragged.
          onPanUpdate: (details) {
            if (!_isDragging) {
              return;
            }

            widget.viewportController.updateSelectionFromPixel(
              x: details.localPosition.dx,
              y: details.localPosition.dy,
            );
          },

          // Mouse button released.
          onPanEnd: (_) {
            _isDragging = false;
          },

          child: SingleChildScrollView(
            controller: widget.verticalController,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              controller: widget.horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: CellMetrics.columnWidth * totalColumns,
                height: CellMetrics.rowHeight * totalRows,
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
        );
      },
    );
  }
}