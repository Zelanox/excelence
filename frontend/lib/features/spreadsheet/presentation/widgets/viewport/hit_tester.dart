import '../../../models/cell_position.dart';
import 'cell_metrics.dart';

class HitTester {
  const HitTester();

  CellPosition fromPixel({
    required double x,
    required double y,
    double scrollX = 0,
    double scrollY = 0,
  }) {
    final contentX = x + scrollX;
    final contentY = y + scrollY;

    final column =
        (contentX / CellMetrics.columnWidth).floor();

    final row =
        (contentY / CellMetrics.rowHeight).floor();

    return CellPosition(
      row: row,
      column: column,
    );
  }
}