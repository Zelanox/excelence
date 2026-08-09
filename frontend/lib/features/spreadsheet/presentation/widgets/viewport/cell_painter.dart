import 'package:flutter/material.dart';

import 'cell_metrics.dart';
import '../../../models/spreadsheet_model.dart';
import '../../../models/visible_range_model.dart';

class CellPainter extends CustomPainter {
  const CellPainter({
    required this.spreadsheet,
    required this.visibleRange,
  });

  final SpreadsheetModel spreadsheet;
  final VisibleRangeModel visibleRange;

  @override
  void paint(Canvas canvas, Size size) {
    const style = TextStyle(
      fontSize: 12,
      color: Colors.black,
    );

    final painter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final sheet = spreadsheet.activeSheet;

    final firstRow = visibleRange.firstRow;
    final lastRow = visibleRange.lastRow;

    final firstColumn = visibleRange.firstColumn;
    final lastColumn = visibleRange.lastColumn;

    for (
      int rowIndex = firstRow;
      rowIndex <= lastRow;
      rowIndex++
    ) {
      if (rowIndex >= sheet.rows.length) {
        break;
      }

      final row = sheet.rows[rowIndex];

      for (
        int columnIndex = firstColumn;
        columnIndex <= lastColumn;
        columnIndex++
      ) {
        if (columnIndex >= row.cells.length) {
          break;
        }

        final cell = row.cells[columnIndex];

        final x = cell.column * CellMetrics.columnWidth;
        final y = cell.row * CellMetrics.rowHeight;

        final value = cell.value.toString();

        if (value.isEmpty) {
          continue;
        }

        painter.text = TextSpan(
          text: value,
          style: style,
        );

        painter.layout(
          maxWidth: CellMetrics.columnWidth - 8,
        );

        painter.paint(
          canvas,
          Offset(
            x + 4,
            y + 4,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CellPainter oldDelegate) {
    return oldDelegate.spreadsheet != spreadsheet ||
        oldDelegate.visibleRange != visibleRange;
  }
}