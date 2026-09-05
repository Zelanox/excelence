import '../models/spreadsheet_model.dart';
import '../models/cell_position.dart';
import 'formula_engine.dart';

class FormulaDependencyGraph {
  FormulaDependencyGraph(
    SpreadsheetModel spreadsheet,
    FormulaEngine engine,
  ) {
    final sheet = spreadsheet.activeSheet;

    for (final row in sheet.rows) {
      for (final cell in row.cells) {
        final formula = cell.formula;
        if (formula == null) {
          continue;
        }

        final formulaCell = _addressFor(
          row: cell.row,
          column: cell.column,
        );

        for (final reference in engine.extractReferences(formula)) {
          (_dependents[reference] ??= <String>{}).add(formulaCell);
        }
      }
    }
  }

  final Map<String, Set<String>> _dependents = {};

  Set<String> dependentsOf(Iterable<String> changedCells) {
    final affected = <String>{};
    final pending = <String>[...changedCells];

    while (pending.isNotEmpty) {
      final changedCell = pending.removeLast();
      for (final dependent in _dependents[changedCell] ?? const <String>{}) {
        if (affected.add(dependent)) {
          pending.add(dependent);
        }
      }
    }

    return affected;
  }

  static String addressFor({required int row, required int column}) {
    return '${_columnName(column)}${row + 1}';
  }

  static CellPosition positionFor(String address) {
    final match = RegExp(r'^([A-Z]+)([1-9][0-9]*)$').firstMatch(address);
    if (match == null) {
      throw const FormatException();
    }

    var column = 0;
    for (final character in match.group(1)!.codeUnits) {
      column = column * 26 + character - 64;
    }

    return CellPosition(
      row: int.parse(match.group(2)!) - 1,
      column: column - 1,
    );
  }

  static String _addressFor({required int row, required int column}) {
    return addressFor(row: row, column: column);
  }

  static String _columnName(int column) {
    var value = column + 1;
    var name = '';

    while (value > 0) {
      final remainder = (value - 1) % 26;
      name = String.fromCharCode(65 + remainder) + name;
      value = (value - 1) ~/ 26;
    }

    return name;
  }
}
