import 'sheet_model.dart';

class SpreadsheetModel {
  const SpreadsheetModel({
    required this.sheets,
    required this.activeSheetIndex,
  });

  final List<SheetModel> sheets;
  final int activeSheetIndex;

  SheetModel get activeSheet => sheets[activeSheetIndex];
}