import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  final List<SpreadsheetModel> _undoStack = [];
  final List<SpreadsheetModel> _redoStack = [];

  SpreadsheetModel? get spreadsheet => _spreadsheet;
  
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

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
  // History management (Undo/Redo)
  // ============================================================

  void _recordHistoryPoint() {
    if (_spreadsheet == null) {
      return;
    }

    _undoStack.add(_spreadsheet!);
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo || _spreadsheet == null) {
      return;
    }

    _redoStack.add(_spreadsheet!);
    _spreadsheet = _undoStack.removeLast();

    notifyListeners();
  }

  void redo() {
    if (!canRedo || _spreadsheet == null) {
      return;
    }

    _undoStack.add(_spreadsheet!);
    _spreadsheet = _redoStack.removeLast();

    notifyListeners();
  }

  // ============================================================
  // Formula detection
  // ============================================================

  bool _isFormula(String text) {
    return text.startsWith('=');
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
    // Record history point before mutation
    // ----------------------------------------------------------

    _recordHistoryPoint();

    // ----------------------------------------------------------
    // Determine if input is a formula or normal value
    // ----------------------------------------------------------

    final isFormula = _isFormula(value);
    final newValue = value;
    final newFormula = isFormula ? value : null;

    // ----------------------------------------------------------
    // Create the new cell
    // ----------------------------------------------------------

    final oldCell = currentRow.cells[column];

    final newCell = oldCell.copyWith(
      value: newValue,
      formula: newFormula,
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

  Future<void> copySelection(SelectionModel selection) async {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    final startRow =
        selection.startRow <= selection.endRow
            ? selection.startRow
            : selection.endRow;

    final endRow =
        selection.startRow <= selection.endRow
            ? selection.endRow
            : selection.startRow;

    final startColumn =
        selection.startColumn <= selection.endColumn
            ? selection.startColumn
            : selection.endColumn;

    final endColumn =
        selection.startColumn <= selection.endColumn
            ? selection.endColumn
            : selection.startColumn;

    final rows = <String>[];

    for (int row = startRow; row <= endRow; row++) {
      final cells = <String>[];

      for (
        int column = startColumn;
        column <= endColumn;
        column++
      ) {
        cells.add(
          currentSheet.rows[row].cells[column].value,
        );
      }

      rows.add(cells.join('\t'));
    }

    await Clipboard.setData(
      ClipboardData(
        text: rows.join('\n'),
      ),
    );
  }

  Future<void> pasteClipboard({
    required int row,
    required int column,
    required String clipboardText,
  }) async {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    // ----------------------------------------------------------
    // Parse clipboard text as TSV
    // ----------------------------------------------------------

    final lines = clipboardText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    // Ignore a trailing newline from the clipboard.
    if (lines.length > 1 && lines.last.isEmpty) {
      lines.removeLast();
    }

    if (lines.isEmpty || lines.first.isEmpty) {
      return;
    }

    final pastedRows = lines.map(
      (line) => line.split('\t'),
    ).toList();

    // ----------------------------------------------------------
    // Validate paste origin
    // ----------------------------------------------------------

    if (row < 0 || row >= currentSheet.rows.length) {
      return;
    }

    if (column < 0 ||
        column >= currentSheet.rows[row].cells.length) {
      return;
    }

    // ----------------------------------------------------------
    // Record history point before mutation
    // ----------------------------------------------------------

    _recordHistoryPoint();

    // ----------------------------------------------------------
    // Create new rows
    // ----------------------------------------------------------

    final newRows =
        List<RowModel>.from(currentSheet.rows);

    for (int pastedRow = 0;
        pastedRow < pastedRows.length;
        pastedRow++) {
      final targetRow = row + pastedRow;

      if (targetRow >= currentSheet.rows.length) {
        break;
      }

      final currentRow = currentSheet.rows[targetRow];

      final newCells =
          List<CellModel>.from(currentRow.cells);

      final values = pastedRows[pastedRow];

      for (int pastedColumn = 0;
          pastedColumn < values.length;
          pastedColumn++) {
        final targetColumn = column + pastedColumn;

        if (targetColumn >= currentRow.cells.length) {
          break;
        }

        final oldCell = currentRow.cells[targetColumn];
        final pastedValue = values[pastedColumn];

        // Determine if pasted value is a formula
        final isFormula = _isFormula(pastedValue);
        final cellFormula = isFormula ? pastedValue : null;

        newCells[targetColumn] = CellModel(
          row: oldCell.row,
          column: oldCell.column,
          value: pastedValue,
          formula: cellFormula,
          isSelected: oldCell.isSelected,
          isEditing: false,
        );
      }

      newRows[targetRow] = RowModel(
        index: currentRow.index,
        cells: newCells,
      );
    }

    // ----------------------------------------------------------
    // Create new sheet
    // ----------------------------------------------------------

    final newSheet = SheetModel(
      name: currentSheet.name,
      rows: newRows,
    );

    // ----------------------------------------------------------
    // Create new sheet list
    // ----------------------------------------------------------

    final newSheets =
        List<SheetModel>.from(
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

  void clearSelection(SelectionModel selection) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    // ----------------------------------------------------------
    // Normalize selection bounds
    // ----------------------------------------------------------

    final startRow =
        selection.startRow <= selection.endRow
            ? selection.startRow
            : selection.endRow;

    final endRow =
        selection.startRow <= selection.endRow
            ? selection.endRow
            : selection.startRow;

    final startColumn =
        selection.startColumn <= selection.endColumn
            ? selection.startColumn
            : selection.endColumn;

    final endColumn =
        selection.startColumn <= selection.endColumn
            ? selection.endColumn
            : selection.startColumn;

    // ----------------------------------------------------------
    // Validate selection
    // ----------------------------------------------------------

    if (startRow < 0 ||
        startRow >= currentSheet.rows.length) {
      return;
    }

    // ----------------------------------------------------------
    // Record history point before mutation
    // ----------------------------------------------------------

    _recordHistoryPoint();

    // ----------------------------------------------------------
    // Create new rows
    // ----------------------------------------------------------

    final newRows =
        List<RowModel>.from(currentSheet.rows);

    for (int row = startRow; row <= endRow; row++) {
      if (row >= currentSheet.rows.length) {
        break;
      }

      final currentRow = currentSheet.rows[row];

      final newCells =
          List<CellModel>.from(currentRow.cells);

      for (
        int column = startColumn;
        column <= endColumn;
        column++
      ) {
        if (column < 0 ||
            column >= currentRow.cells.length) {
          continue;
        }

        final oldCell = currentRow.cells[column];

        newCells[column] = CellModel(
          row: oldCell.row,
          column: oldCell.column,
          value: "",
          formula: null,
          isSelected: oldCell.isSelected,
          isEditing: false,
        );
      }

      newRows[row] = RowModel(
        index: currentRow.index,
        cells: newCells,
      );
    }

    // ----------------------------------------------------------
    // Create new sheet
    // ----------------------------------------------------------

    final newSheet = SheetModel(
      name: currentSheet.name,
      rows: newRows,
    );

    // ----------------------------------------------------------
    // Create new sheet list
    // ----------------------------------------------------------

    final newSheets =
        List<SheetModel>.from(
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