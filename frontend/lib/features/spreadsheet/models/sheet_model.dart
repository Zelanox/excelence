import 'row_model.dart';
import 'text_style_spec.dart';

class SheetModel {
  const SheetModel({
    required this.name,
    required this.rows,
    this.headers = const [],
    this.columnWidths = const {},
    this.isRtl = false,
    this.textDefaults = TextStyleSpec.empty,
  });

  final String name;
  final List<RowModel> rows;

  /// Real column header names as returned by the backend (e.g. "Name",
  /// "Age", "Score") - NOT the same as the display letters (A, B, C) used
  /// by GridColumnHeader. The backend's insert/delete-column endpoints
  /// identify columns by this name, not by letter/index, so it needs to
  /// be tracked here rather than only derived from column position.
  final List<String> headers;

  /// Column name to display width, for any column with an explicitly
  /// set width. Keyed by name (like [headers], not by position) for the
  /// same reason - a column's width should survive an unrelated
  /// insert/delete elsewhere in the sheet, and letter/index positions
  /// shift while names don't. A column absent from this map has no
  /// explicitly set width and falls back to SpreadsheetGrid.columnWidth.
  final Map<String, double> columnWidths;

  /// Whether this sheet is right-to-left (mirrors the backend's
  /// Sheet.rtl, itself backed by the worksheet's native sheet_view.
  /// rightToLeft). Deliberately does NOT change [headers]' order - the
  /// backend always returns columns in true logical order regardless of
  /// direction, so column 0 is always the real first column. Only the
  /// grid's rendering (via an ambient Directionality wrapping the
  /// TableView - see SpreadsheetGrid) flips which physical edge that
  /// logical order renders at. Reordering headers here on top of that
  /// would double-flip the layout.
  final bool isRtl;

  /// The sheet-wide default text style. Each cell's own
  /// [CellModel.style] is merged over this; a field unset in both falls
  /// through to the grid's built-in style. Backed by the backend's
  /// Sheet.text_defaults (stored in the .xlsx).
  final TextStyleSpec textDefaults;

  SheetModel copyWith({
    String? name,
    List<RowModel>? rows,
    List<String>? headers,
    Map<String, double>? columnWidths,
    bool? isRtl,
    TextStyleSpec? textDefaults,
  }) {
    return SheetModel(
      name: name ?? this.name,
      rows: rows ?? this.rows,
      headers: headers ?? this.headers,
      columnWidths: columnWidths ?? this.columnWidths,
      isRtl: isRtl ?? this.isRtl,
      textDefaults: textDefaults ?? this.textDefaults,
    );
  }
}