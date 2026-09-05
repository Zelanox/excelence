import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/cell_model.dart';
import '../models/row_model.dart';
import '../models/sheet_model.dart';
import '../models/spreadsheet_model.dart';
import '../models/selection_model.dart';

import '../services/spreadsheet_service.dart';
import '../services/formula_engine.dart';
import '../services/formula_dependency_graph.dart';

class SpreadsheetController extends ChangeNotifier {
  SpreadsheetController(this._service);

  final SpreadsheetService _service;
  final FormulaEngine _formulaEngine = const FormulaEngine();

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

  SpreadsheetModel _recalculateDependents(
    SpreadsheetModel spreadsheet,
    Set<String> changedCells,
  ) {
    final graph = FormulaDependencyGraph(
      spreadsheet,
      _formulaEngine,
    );
    final cellsToRecalculate = graph.dependentsOf(changedCells);

    for (final changedCell in changedCells) {
      final position = FormulaDependencyGraph.positionFor(changedCell);
      final cell = spreadsheet.activeSheet.rows[position.row]
          .cells[position.column];
      if (cell.formula != null) {
        cellsToRecalculate.add(changedCell);
      }
    }

    var recalculatedSpreadsheet = spreadsheet;
    for (final address in cellsToRecalculate) {
      final position = FormulaDependencyGraph.positionFor(address);
      final cell = recalculatedSpreadsheet.activeSheet.rows[position.row]
          .cells[position.column];
      final formula = cell.formula;
      if (formula == null) {
        continue;
      }

      final value = _formulaEngine.evaluate(
        formula,
        recalculatedSpreadsheet,
        resolving: {address},
      );
      recalculatedSpreadsheet = _replaceCell(
        recalculatedSpreadsheet,
        position.row,
        position.column,
        CellModel(
          row: cell.row,
          column: cell.column,
          value: value,
          formula: formula,
          isSelected: cell.isSelected,
          isEditing: false,
        ),
      );
    }

    return recalculatedSpreadsheet;
  }

  SpreadsheetModel _replaceCell(
    SpreadsheetModel spreadsheet,
    int row,
    int column,
    CellModel cell,
  ) {
    final sheet = spreadsheet.activeSheet;
    final rows = List<RowModel>.from(sheet.rows);
    final cells = List<CellModel>.from(rows[row].cells);
    cells[column] = cell;
    rows[row] = RowModel(index: rows[row].index, cells: cells);

    final sheets = List<SheetModel>.from(spreadsheet.sheets);
    sheets[spreadsheet.activeSheetIndex] = SheetModel(
      name: sheet.name,
      rows: rows,
    );

    return SpreadsheetModel(
      sheets: sheets,
      activeSheetIndex: spreadsheet.activeSheetIndex,
    );
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

    debugPrint(
      '[SpreadsheetController.editCell] target=($row,$column) '
      'activeSheet=$activeSheetIndex value="$value"',
    );
    final references = RegExp(r'[A-Z]+[1-9][0-9]*').allMatches(value);
    for (final match in references) {
      final reference = match.group(0)!;
      final positionMatch =
          RegExp(r'^([A-Z]+)([1-9][0-9]*)$').firstMatch(reference);
      if (positionMatch == null) {
        continue;
      }
      var referenceColumn = 0;
      for (final code in positionMatch.group(1)!.codeUnits) {
        referenceColumn = referenceColumn * 26 + code - 64;
      }
      final referenceRow = int.parse(positionMatch.group(2)!) - 1;
      if (referenceRow >= 0 &&
          referenceRow < currentSheet.rows.length &&
          referenceColumn - 1 >= 0 &&
          referenceColumn - 1 < currentSheet.rows[referenceRow].cells.length) {
        final referencedCell =
            currentSheet.rows[referenceRow].cells[referenceColumn - 1];
        debugPrint(
          '[SpreadsheetController.editCell] referenced cell $reference: '
          'value="${referencedCell.value}"; '
          'formula="${referencedCell.formula}"',
        );
      } else {
        debugPrint(
          '[SpreadsheetController.editCell] referenced cell $reference: '
          'does not exist in active sheet',
        );
      }
      if (referenceRow == row && referenceColumn - 1 == column) {
        debugPrint(
          '[FormulaEngine.selfReference] target=($row,$column) '
          'reference=$reference',
        );
      }
    }

    // ----------------------------------------------------------
    // Record history point before mutation
    // ----------------------------------------------------------

    _recordHistoryPoint();

    // ----------------------------------------------------------
    // Determine if input is a formula or normal value
    // ----------------------------------------------------------

    final isFormula = _isFormula(value);
    late final String newValue;
    if (isFormula) {
      debugPrint(
        '[SpreadsheetController.formula] formula="$value" '
        'target=($row,$column)',
      );
      newValue = _formulaEngine.evaluate(value, currentSpreadsheet);
      debugPrint(
        '[SpreadsheetController.formula.result] formula="$value" '
        'result="$newValue"',
      );
    } else {
      newValue = value;
    }
    final newFormula = isFormula ? value : null;

    // ----------------------------------------------------------
    // Create the new cell
    // ----------------------------------------------------------

    final oldCell = currentRow.cells[column];

    final newCell = CellModel(
      row: oldCell.row,
      column: oldCell.column,
      value: newValue,
      formula: newFormula,
      isSelected: oldCell.isSelected,
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

    final updatedSpreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
    );

    _spreadsheet = _recalculateDependents(
      updatedSpreadsheet,
      {
        FormulaDependencyGraph.addressFor(
          row: row,
          column: column,
        ),
      },
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
        final cell = currentSheet.rows[row].cells[column];
        cells.add(cell.formula ?? cell.value);
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
    final changedCells = <String>{};

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
        changedCells.add(
          FormulaDependencyGraph.addressFor(
            row: targetRow,
            column: targetColumn,
          ),
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

    final updatedSpreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
    );

    _spreadsheet = _recalculateDependents(
      updatedSpreadsheet,
      changedCells,
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
    final changedCells = <String>{};

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
        changedCells.add(
          FormulaDependencyGraph.addressFor(
            row: row,
            column: column,
          ),
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

    final updatedSpreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
    );

    _spreadsheet = _recalculateDependents(
      updatedSpreadsheet,
      changedCells,
    );

    notifyListeners();
  }

}