import 'row_model.dart';

class SheetModel {
  const SheetModel({
    required this.name,
    required this.rows,
    this.headers = const [],
  });

  final String name;
  final List<RowModel> rows;

  /// Real column header names as returned by the backend (e.g. "Name",
  /// "Age", "Score") - NOT the same as the display letters (A, B, C) used
  /// by GridColumnHeader. The backend's insert/delete-column endpoints
  /// identify columns by this name, not by letter/index, so it needs to
  /// be tracked here rather than only derived from column position.
  final List<String> headers;
}