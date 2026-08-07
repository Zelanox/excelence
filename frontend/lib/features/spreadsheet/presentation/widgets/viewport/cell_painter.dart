import 'package:flutter/material.dart';

import 'cell_metrics.dart';
import '../../../models/spreadsheet_model.dart';

class CellPainter extends CustomPainter {
  const CellPainter({
    required this.spreadsheet,
  });

  final SpreadsheetModel spreadsheet;

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

    for (final row in sheet.rows) {
      for (final cell in row.cells) {

        final x = cell.column * CellMetrics.columnWidth;
        final y = cell.row * CellMetrics.rowHeight;

      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}