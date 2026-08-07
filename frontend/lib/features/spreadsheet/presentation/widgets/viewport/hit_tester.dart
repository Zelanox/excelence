import '../../../models/cell_position.dart';
import 'cell_metrics.dart';

class HitTester {
  const HitTester();

  CellPosition fromPixel({
    required double x,
    required double y,
  }) {
    final column = (x / CellMetrics.columnWidth).floor();
    final row = (y / CellMetrics.rowHeight).floor();

    return CellPosition(
      row: row,
      column: column,
    );
  }
}