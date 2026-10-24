import 'row_model.dart';
import 'sheet_appearance.dart';
import 'sheet_view.dart';
import 'text_style_spec.dart';

/// One worksheet as the client holds it.
///
/// There are TWO views of its rows, and keeping them straight is the point
/// of this class:
///
///  * [allRows] - the CANONICAL rows: every row of the data, in the data's
///    own order, never filtered or sorted. Row/column positions here are
///    what formulas (`=A1+A2`) and everything sent to the server mean. All
///    edits ultimately land here.
///  * [rows] - the rows currently SHOWN: [allRows] with this sheet's [view]
///    (search filter and sort) applied. This is what the grid draws, and
///    what a "row number" from the UI refers to. Convert with
///    [sourceRowOf] before touching the data.
///
/// Sorting and filtering are client-local (see [SheetView]): they change
/// which rows [rows] contains, never [allRows].
class SheetModel {
  SheetModel({
    required this.name,
    required this.allRows,
    this.headers = const [],
    this.columnWidths = const {},
    this.isRtl = false,
    this.textDefaults = TextStyleSpec.empty,
    this.appearance = SheetAppearance.empty,
    this.view = SheetView.none,
    this.viewToSource,
    this.sheetId = '',
    this.rowIds = const [],
    this.columnIds = const [],
  }) : assert(
          viewToSource == null ||
              viewToSource.every((index) => index >= 0 && index < allRows.length),
          'viewToSource points outside allRows',
        );

  final String name;

  /// The server's stable ID for this worksheet (it survives a rename), or ''
  /// when the sheet did not come from the server.
  final String sheetId;

  /// The server's stable ID of each row of [allRows], in the same order, and
  /// of each column of [headers]. Changes sent to the server name rows and
  /// columns by these IDs, so they still land correctly when somebody else
  /// inserts or deletes a row or column in the meantime. Empty for a sheet
  /// that did not come from the server; check [hasIds] before relying on them.
  final List<String> rowIds;
  final List<String> columnIds;

  /// Whether the IDs describe this sheet completely. When anything about the
  /// shape was rebuilt locally without updating them, this is false and
  /// callers must not use them (they fall back to positions).
  bool get hasIds =>
      sheetId.isNotEmpty &&
      rowIds.length == allRows.length &&
      columnIds.length == headers.length;

  /// Every row of the data, in the data's own order. See the class comment.
  final List<RowModel> allRows;

  final List<String> headers;

  /// Per-column pixel widths, keyed by column NAME (survives inserts and
  /// deletes elsewhere in the sheet). Absent = default width.
  final Map<String, double> columnWidths;

  final bool isRtl;

  /// The sheet-wide default text style. Each cell's own
  /// [CellModel.style] is merged over this; a field unset in both falls
  /// through to the grid's built-in style. Backed by the backend's
  /// Sheet.text_defaults (stored in the .xlsx).
  final TextStyleSpec textDefaults;

  /// Grid line color and alternating row colors for this sheet.
  final SheetAppearance appearance;

  /// The search filter / sort this client is looking at the sheet through.
  final SheetView view;

  /// For each SHOWN row, the index of its row in [allRows]; null means the
  /// shown rows are exactly [allRows] (the common case: no view).
  ///
  /// This is the view's RESULT, kept rather than recomputed so that editing
  /// a cell doesn't make rows jump around under a sort or vanish under a
  /// filter mid-edit - the order is refreshed only when the view itself, or
  /// the set of rows, changes (see [withView]).
  final List<int>? viewToSource;

  /// The rows currently shown: [allRows] seen through [view]. Computed once
  /// per instance; the same list as [allRows] when there is no view.
  late final List<RowModel> rows = _visibleRows();

  List<RowModel> _visibleRows() {
    final mapping = viewToSource;

    if (mapping == null) {
      return allRows;
    }

    return [for (final index in mapping) allRows[index]];
  }

  /// True when [rows] is a filtered and/or reordered subset of [allRows].
  bool get isViewActive => viewToSource != null;

  /// The index in [allRows] of the row shown at [viewRow].
  int sourceRowOf(int viewRow) {
    final mapping = viewToSource;
    return mapping == null ? viewRow : mapping[viewRow];
  }

  /// The position in [rows] at which canonical row [sourceRow] is shown, or
  /// null if the view hides it.
  int? viewRowOf(int sourceRow) {
    final mapping = viewToSource;

    if (mapping == null) {
      return sourceRow >= 0 && sourceRow < allRows.length ? sourceRow : null;
    }

    final position = mapping.indexOf(sourceRow);
    return position < 0 ? null : position;
  }

  /// A copy looking at the same data through [newView]: the shown rows are
  /// recomputed (filter, then sort) from the CURRENT [allRows].
  SheetModel withView(SheetView newView) {
    return SheetModel(
      name: name,
      allRows: allRows,
      headers: headers,
      columnWidths: columnWidths,
      isRtl: isRtl,
      textDefaults: textDefaults,
      appearance: appearance,
      view: newView,
      viewToSource: newView.apply(headers, allRows),
      sheetId: sheetId,
      rowIds: rowIds,
      columnIds: columnIds,
    );
  }

  /// A copy with the given canonical rows replaced, KEEPING the current
  /// view's row order (see [viewToSource]). [replacements] maps an index in
  /// [allRows] to its new row. The number of rows is unchanged, which is
  /// what keeps the kept mapping valid.
  SheetModel withSourceRows(Map<int, RowModel> replacements) {
    if (replacements.isEmpty) {
      return this;
    }

    final updated = List<RowModel>.of(allRows);

    replacements.forEach((index, row) {
      updated[index] = row;
    });

    return SheetModel(
      name: name,
      allRows: updated,
      headers: headers,
      columnWidths: columnWidths,
      isRtl: isRtl,
      textDefaults: textDefaults,
      appearance: appearance,
      view: view,
      viewToSource: viewToSource,
      sheetId: sheetId,
      rowIds: rowIds,
      columnIds: columnIds,
    );
  }

  /// A copy with other properties changed. The row data and the view are
  /// kept as they are; to change the data's SHAPE (rows added/removed) build
  /// a new sheet, then apply the view with [withView].
  SheetModel copyWith({
    String? name,
    List<String>? headers,
    Map<String, double>? columnWidths,
    bool? isRtl,
    TextStyleSpec? textDefaults,
    SheetAppearance? appearance,
  }) {
    return SheetModel(
      name: name ?? this.name,
      allRows: allRows,
      headers: headers ?? this.headers,
      columnWidths: columnWidths ?? this.columnWidths,
      isRtl: isRtl ?? this.isRtl,
      textDefaults: textDefaults ?? this.textDefaults,
      appearance: appearance ?? this.appearance,
      view: view,
      viewToSource: viewToSource,
      sheetId: sheetId,
      rowIds: rowIds,
      columnIds: columnIds,
    );
  }
}
