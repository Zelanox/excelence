import 'package:flutter/material.dart';

import 'cell_metrics.dart';
import '../../../models/visible_range_model.dart';

class GridPainter extends CustomPainter {
  const GridPainter({
    required this.visibleRange,
  });

  final VisibleRangeModel visibleRange;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    final firstColumn = visibleRange.firstColumn;
    final lastColumn = visibleRange.lastColumn;

    final firstRow = visibleRange.firstRow;
    final lastRow = visibleRange.lastRow;

    // Vertical lines.
    for (
      int column = firstColumn;
      column <= lastColumn + 1;
      column++
    ) {
      final x = column * CellMetrics.columnWidth;

      canvas.drawLine(
        Offset(x, firstRow * CellMetrics.rowHeight),
        Offset(x, (lastRow + 1) * CellMetrics.rowHeight),
        paint,
      );
    }

    // Horizontal lines.
    for (
      int row = firstRow;
      row <= lastRow + 1;
      row++
    ) {
      final y = row * CellMetrics.rowHeight;

      canvas.drawLine(
        Offset(firstColumn * CellMetrics.columnWidth, y),
        Offset((lastColumn + 1) * CellMetrics.columnWidth, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.visibleRange != visibleRange;
  }
}