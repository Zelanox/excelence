import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/models/spreadsheet_model.dart';
import 'package:frontend/features/spreadsheet/services/formula_engine.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

void main() {
  group('FormulaEngine Phase 3', () {
    const engine = FormulaEngine();

    test('evaluates range functions and arithmetic', () {
      final spreadsheet = _spreadsheet(
        values: const {
          'A1': '10',
          'A2': '20',
          'A3': '30',
          'B1': '5',
          'B2': '2',
          'C1': '7',
          'C2': '8',
          'C3': '9',
        },
      );

      expect(engine.evaluate('=SUM(A1:A3)', spreadsheet), '60');
      expect(engine.evaluate('=AVERAGE(A1:A3)', spreadsheet), '20');
      expect(engine.evaluate('=MIN(A1:A3)', spreadsheet), '10');
      expect(engine.evaluate('=MAX(A1:A3)', spreadsheet), '30');
      expect(engine.evaluate('=COUNT(A1:A3)', spreadsheet), '3');
      expect(engine.evaluate('=SUM(A1:C2)', spreadsheet), '52');
      expect(engine.evaluate('=SUM(A1:A3,C1:C3)', spreadsheet), '84');
      expect(engine.evaluate('=SUM(A1:A3)*2', spreadsheet), '120');
      expect(engine.evaluate('=AVERAGE(A1:A3)+10', spreadsheet), '30');
    });

    test('ignores nonnumeric range members for aggregate functions', () {
      final spreadsheet = _spreadsheet(
        values: const {'A1': '10', 'A2': 'text'},
      );

      expect(engine.evaluate('=SUM(A1:A3)', spreadsheet), '10');
      expect(engine.evaluate('=AVERAGE(A1:A3)', spreadsheet), '10');
      expect(engine.evaluate('=COUNT(A1:A3)', spreadsheet), '1');
      expect(engine.evaluate('=MIN(A1:A3)', spreadsheet), '10');
      expect(engine.evaluate('=MAX(A1:A3)', spreadsheet), '10');
      expect(engine.evaluate('=AVERAGE(B1:B3)', spreadsheet), '#ERROR!');
    });

    test('returns errors for invalid ranges and functions', () {
      final spreadsheet = _spreadsheet();

      expect(engine.evaluate('=SUM(A1:A)', spreadsheet), '#ERROR!');
      expect(engine.evaluate('=UNKNOWN(A1:A3)', spreadsheet), '#ERROR!');
      expect(engine.evaluate('=SUM(A1:A3', spreadsheet), '#ERROR!');
    });

    test('extracts every cell in a two-dimensional range', () {
      final references = engine.extractReferences('=SUM(A1:C2)');

      expect(
        references,
        containsAll(<String>['A1', 'B1', 'C1', 'A2', 'B2', 'C2']),
      );
      expect(references, hasLength(6));
    });
  });

  test('recalculates all cells covered by a range dependency', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '1');
    controller.editCell(row: 1, column: 0, value: '2');
    controller.editCell(row: 2, column: 0, value: '3');
    controller.editCell(row: 0, column: 1, value: '=SUM(A1:A3)');

    controller.editCell(row: 2, column: 0, value: '10');

    expect(_value(controller, 0, 1), '13');
  });

  test('undo and redo restore range recalculation as one operation', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '10');
    controller.editCell(row: 1, column: 0, value: '20');
    controller.editCell(row: 0, column: 1, value: '=SUM(A1:A2)');
    controller.editCell(row: 0, column: 0, value: '30');

    controller.undo();
    expect(_value(controller, 0, 0), '10');
    expect(_value(controller, 0, 1), '30');

    controller.redo();
    expect(_value(controller, 0, 0), '30');
    expect(_value(controller, 0, 1), '50');
  });
}

SpreadsheetController _controller() {
  final controller = SpreadsheetController(
    SpreadsheetService(ApiClient(baseUrl: 'http://localhost')),
  );
  controller.loadMockData();
  return controller;
}

String _value(SpreadsheetController controller, int row, int column) {
  return controller.spreadsheet!.activeSheet.rows[row].cells[column].value;
}

SpreadsheetModel _spreadsheet({Map<String, String> values = const {}}) {
  return SpreadsheetModel(
    activeSheetIndex: 0,
    sheets: [
      SheetModel(
        name: 'Sheet1',
        rows: List.generate(
          3,
          (row) => RowModel(
            index: row,
            cells: List.generate(
              3,
              (column) => CellModel(
                row: row,
                column: column,
                value: values['${_columnName(column)}${row + 1}'] ?? '',
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

String _columnName(int column) {
  var value = column + 1;
  var name = '';

  while (value > 0) {
    final remainder = (value - 1) % 26;
    name = String.fromCharCode(65 + remainder) + name;
    value = (value - 1) ~/ 26;
  }

  return name;
}
