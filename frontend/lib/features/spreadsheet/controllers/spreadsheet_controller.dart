import 'package:flutter/foundation.dart';

import '../models/cell_model.dart';
import '../models/row_model.dart';
import '../models/sheet_model.dart';
import '../models/spreadsheet_model.dart';
import '../models/selection_model.dart';

import '../services/spreadsheet_service.dart';

class SpreadsheetController extends ChangeNotifier {
  SpreadsheetController(this._service);

  final SpreadsheetService _service;

  SpreadsheetModel? _spreadsheet;
  SelectionModel _selection = const SelectionModel();

  SpreadsheetModel? get spreadsheet => _spreadsheet;
  SelectionModel get selection => _selection;

  // ============================================================
  // Mock data
  // ============================================================

  void loadMockData() {
    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: 0,
      sheets: [
        SheetModel(
          name: "Sheet1",
          rows: List.generate(
            100,
            (r) => RowModel(
              index: r,
              cells: List.generate(
                26,
                (c) => CellModel(
                  row: r,
                  column: c,
                  value: "",
                ),
              ),
            ),
          ),
        ),
      ],
    );

    notifyListeners();
  }

  // ============================================================
  // Selection
  // ============================================================

  void selectCell(int row, int column) {
    if (_selection.startRow == row &&
        _selection.startColumn == column) {
      return;
    }

    _selection = SelectionModel(
      startRow: row,
      endRow: row,
      startColumn: column,
      endColumn: column,
    );

    notifyListeners();
  }

  // ============================================================
  // Cell editing
  // ============================================================

  void editCell({
    required int row,
    required int column,
    required String value,
  }) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    if (row < 0 || row >= currentSheet.rows.length) {
      return;
    }

    final currentRow = currentSheet.rows[row];

    if (column < 0 || column >= currentRow.cells.length) {
      return;
    }

    // ----------------------------------------------------------
    // Create the new cell
    // ----------------------------------------------------------

    final oldCell = currentRow.cells[column];

    final newCell = oldCell.copyWith(
      value: value,
      isEditing: false,
    );

    // ----------------------------------------------------------
    // Create a new cell list
    // ----------------------------------------------------------

    final newCells = List<CellModel>.from(
      currentRow.cells,
    );

    newCells[column] = newCell;

    // ----------------------------------------------------------
    // Create a new row
    // ----------------------------------------------------------

    final newRow = RowModel(
      index: currentRow.index,
      cells: newCells,
    );

    // ----------------------------------------------------------
    // Create a new row list
    // ----------------------------------------------------------

    final newRows = List<RowModel>.from(
      currentSheet.rows,
    );

    newRows[row] = newRow;

    // ----------------------------------------------------------
    // Create a new sheet
    // ----------------------------------------------------------

    final newSheet = SheetModel(
      name: currentSheet.name,
      rows: newRows,
    );

    // ----------------------------------------------------------
    // Create a new sheet list
    // ----------------------------------------------------------

    final newSheets = List<SheetModel>.from(
      currentSpreadsheet.sheets,
    );

    newSheets[activeSheetIndex] = newSheet;

    // ----------------------------------------------------------
    // Replace spreadsheet
    // ----------------------------------------------------------

    _spreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
    );

    notifyListeners();
  }
}