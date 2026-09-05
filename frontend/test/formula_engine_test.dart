import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/models/spreadsheet_model.dart';
import 'package:frontend/features/spreadsheet/models/selection_model.dart';
import 'package:frontend/features/spreadsheet/services/formula_engine.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

void main() {
  group('FormulaEngine', () {
    const engine = FormulaEngine();

    test('evaluates arithmetic expressions', () {
      final spreadsheet = _spreadsheet();

      expect(engine.evaluate('=1+2', spreadsheet), '3');
      expect(engine.evaluate('=10/2', spreadsheet), '5');
      expect(engine.evaluate('=2*3+4', spreadsheet), '10');
      expect(engine.evaluate('=(2+3)*4', spreadsheet), '20');
    });

    test('resolves cell references', () {
      final spreadsheet = _spreadsheet(
        values: const {
          'A1': '10',
          'B1': '5',
          'AA1': '2',
        },
      );

      expect(engine.evaluate('=A1+B1', spreadsheet), '15');
      expect(engine.evaluate('=A1*2', spreadsheet), '20');
      expect(engine.evaluate('=AA1+1', spreadsheet), '3');
    });

    test('returns an error for invalid formulas', () {
      final spreadsheet = _spreadsheet();

      expect(engine.evaluate('=10/0', spreadsheet), '#ERROR!');
      expect(engine.evaluate('=UnknownCell', spreadsheet), '#ERROR!');
      expect(engine.evaluate('=A1+', spreadsheet), '#ERROR!');
      expect(engine.evaluate('=A999', spreadsheet), '#ERROR!');
    });
  });

  group('SpreadsheetController formula integration', () {
    test('stores evaluated value and original formula', () {
      final controller = _controller();
      controller.editCell(row: 0, column: 0, value: '10');
      controller.editCell(row: 0, column: 1, value: '5');
      controller.editCell(row: 0, column: 2, value: '=A1+B1');

      final cell = controller.spreadsheet!.activeSheet.rows[0].cells[2];
      expect(cell.value, '15');
      expect(cell.formula, '=A1+B1');
    });

    test('evaluates pasted formulas and restores them with undo/redo', () async {
      final controller = _controller();
      controller.editCell(row: 0, column: 0, value: '10');
      controller.editCell(row: 0, column: 1, value: '5');

      await controller.pasteClipboard(
        row: 0,
        column: 2,
        clipboardText: '=A1+B1',
      );

      var cell = controller.spreadsheet!.activeSheet.rows[0].cells[2];
      expect(cell.value, '15');
      expect(cell.formula, '=A1+B1');

      controller.clearSelection(const SelectionModel());
      cell = controller.spreadsheet!.activeSheet.rows[0].cells[0];
      expect(cell.value, '');
      expect(cell.formula, isNull);

      controller.undo();
      cell = controller.spreadsheet!.activeSheet.rows[0].cells[0];
      expect(cell.value, '10');

      controller.redo();
      cell = controller.spreadsheet!.activeSheet.rows[0].cells[0];
      expect(cell.value, '');
    });
  });
}

SpreadsheetController _controller() {
  final service = SpreadsheetService(
    ApiClient(baseUrl: 'http://localhost'),
  );
  final controller = SpreadsheetController(service);
  controller.loadMockData();
  return controller;
}

SpreadsheetModel _spreadsheet({Map<String, String> values = const {}}) {
  final cells = List.generate(
    27,
    (column) {
      final address = '${_columnName(column)}1';
      return CellModel(
        row: 0,
        column: column,
        value: values[address] ?? '',
      );
    },
  );

  return SpreadsheetModel(
    activeSheetIndex: 0,
    sheets: [
      SheetModel(
        name: 'Sheet1',
        rows: [RowModel(index: 0, cells: cells)],
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
