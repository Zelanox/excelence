import 'sheet_model.dart';

class SpreadsheetModel {
  const SpreadsheetModel({
    required this.sheets,
    required this.activeSheetIndex,
    this.availableSheetNames = const [],
  });

  final List<SheetModel> sheets;
  final int activeSheetIndex;

  /// Every worksheet name in the open workbook, in backend order - NOT
  /// the same as [sheets], which only ever holds the currently active
  /// sheet's full loaded grid data (rows/cells/headers). This list drives
  /// the sheet-tab bar; switching tabs fetches that sheet's data fresh
  /// rather than keeping every sheet's data resident at once.
  final List<String> availableSheetNames;

  SheetModel get activeSheet => sheets[activeSheetIndex];
}