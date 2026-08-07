class SelectionModel {
  const SelectionModel({
    this.startRow = 0,
    this.startColumn = 0,
    this.endRow = 0,
    this.endColumn = 0,
  });

  final int startRow;
  final int startColumn;

  final int endRow;
  final int endColumn;

  int get activeRow => startRow;

  int get activeColumn => startColumn;
}