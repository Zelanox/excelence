import 'row_model.dart';

class SheetModel {
  const SheetModel({
    required this.name,
    required this.rows,
  });

  final String name;
  final List<RowModel> rows;
}