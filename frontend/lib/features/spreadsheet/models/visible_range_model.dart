class VisibleRangeModel {
  const VisibleRangeModel({
    required this.firstRow,
    required this.lastRow,
    required this.firstColumn,
    required this.lastColumn,
  });

  final int firstRow;
  final int lastRow;

  final int firstColumn;
  final int lastColumn;

  int get rowCount => lastRow - firstRow + 1;

  int get columnCount => lastColumn - firstColumn + 1;
}