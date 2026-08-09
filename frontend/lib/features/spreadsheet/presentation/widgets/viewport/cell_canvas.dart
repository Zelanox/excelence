import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/spreadsheet_model.dart';
import '../../../models/visible_range_model.dart';

import 'cell_metrics.dart';
import 'grid_painter.dart';
import 'cell_painter.dart';

class CellCanvas extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final sheet = spreadsheet.activeSheet;

    final totalRows = sheet.rows.length;

    final totalColumns = totalRows > 0
        ? sheet.rows.first.cells.length
        : 0;

    if (totalRows == 0 || totalColumns == 0) {
      return const ColoredBox(
        color: Colors.white,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        final VisibleRangeModel visibleRange =
            viewportController.getVisibleRange(
          viewportSize: viewportSize,
          totalRows: totalRows,
          totalColumns: totalColumns,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            viewportController.selectFromPixel(
              x: details.localPosition.dx,
              y: details.localPosition.dy,
            );
          },
          child: SingleChildScrollView(
            controller: verticalController,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: CellMetrics.columnWidth * totalColumns,
                height: CellMetrics.rowHeight * totalRows,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size(
                        CellMetrics.columnWidth * totalColumns,
                        CellMetrics.rowHeight * totalRows,
                      ),
                      painter: GridPainter(
                        visibleRange: visibleRange,
                      ),
                    ),

                    CustomPaint(
                      size: Size(
                        CellMetrics.columnWidth * totalColumns,
                        CellMetrics.rowHeight * totalRows,
                      ),
                      painter: CellPainter(
                        spreadsheet: spreadsheet,
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