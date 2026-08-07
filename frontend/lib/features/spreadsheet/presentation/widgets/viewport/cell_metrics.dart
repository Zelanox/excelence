class CellMetrics {
  const CellMetrics._();

  static const double rowHeight = 28;

  static const double columnWidth = 80;

  static const double rowHeaderWidth = 48;

  static const double columnHeaderHeight = 32;

  static int columnFromPixel(double x) =>
    (x / columnWidth).floor();

  static int rowFromPixel(double y) =>
    (y / rowHeight).floor();

}