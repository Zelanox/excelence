import 'cell_model.dart';

class RowModel {
  const RowModel({
    required this.index,
    required this.cells,
  });

  final int index;
  final List<CellModel> cells;
}