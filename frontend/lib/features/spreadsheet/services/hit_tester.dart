import '../models/cell_position.dart';

/// Converts a raw pixel offset (relative to the grid's top-left corner)
/// into a row/column [CellPosition], accounting for scroll offset and
/// cell size.
///
/// This is pure positioning math with no dependency on any widget or
/// controller - it was previously (mistakenly) filed under the v1
/// presentation/widgets/viewport/ folder, which made it look like UI code
/// and got deleted along with the rest of that folder during the v2
/// rebuild. It has been restored here, in services/, since
/// ViewportController (a real, actively-used controller, not UI) depends
/// on it directly.
class HitTester {
  const HitTester({
    this.columnWidth = 80.0,
    this.rowHeight = 28.0,
  });

  final double columnWidth;
  final double rowHeight;

  CellPosition fromPixel({
    required double x,
    required double y,
    double scrollX = 0,
    double scrollY = 0,
  }) {
    final contentX = x + scrollX;
    final contentY = y + scrollY;

    final column = (contentX / columnWidth).floor();
    final row = (contentY / rowHeight).floor();

    return CellPosition(
      row: row,
      column: column,
    );
  }
}
