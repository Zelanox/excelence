import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';
import '../../../models/spreadsheet_model.dart';
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

    final rowCount = sheet.rows.length;

    final columnCount = sheet.rows.isEmpty
      ? 0
      : sheet.rows.first.cells.length;
    
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
            width: CellMetrics.columnWidth * columnCount,
            height: CellMetrics.rowHeight * rowCount,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: GridPainter(),
                ),

                CustomPaint(
                  size: Size.infinite,
                  painter: CellPainter(
                    spreadsheet: spreadsheet,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}