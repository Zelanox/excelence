import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/models/selection_model.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

void main() {
  test('recalculates direct and chained dependencies', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '10');
    controller.editCell(row: 0, column: 1, value: '=A1*2');
    controller.editCell(row: 0, column: 2, value: '=B1+5');
    controller.editCell(row: 0, column: 3, value: '=C1*2');

    controller.editCell(row: 0, column: 0, value: '20');

    expect(_value(controller, 0), '20');
    expect(_value(controller, 1), '40');
    expect(_value(controller, 2), '45');
    expect(_value(controller, 3), '90');
  });

  test('clearing a referenced cell recalculates dependents', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '10');
    controller.editCell(row: 0, column: 1, value: '=A1+5');

    controller.clearSelection(const SelectionModel());

    expect(_value(controller, 0), '');
    expect(_value(controller, 1), '#ERROR!');
  });

  test('formula replacement uses the new dependency formula', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '10');
    controller.editCell(row: 0, column: 1, value: '=A1*2');
    controller.editCell(row: 0, column: 1, value: '=A1*3');

    controller.editCell(row: 0, column: 0, value: '20');

    expect(_value(controller, 1), '60');
    expect(_formula(controller, 1), '=A1*3');
  });

  test('circular references return errors without recursing forever', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '=B1+1');
    controller.editCell(row: 0, column: 1, value: '=A1+1');

    expect(_value(controller, 0), '#ERROR!');
    expect(_value(controller, 1), '#ERROR!');
  });

  test('undo and redo restore recalculated formula state atomically', () {
    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '10');
    controller.editCell(row: 0, column: 1, value: '=A1*2');
    controller.editCell(row: 0, column: 0, value: '20');

    controller.undo();
    expect(_value(controller, 0), '10');
    expect(_value(controller, 1), '20');

    controller.redo();
    expect(_value(controller, 0), '20');
    expect(_value(controller, 1), '40');
  });
}

SpreadsheetController _controller() {
  final controller = SpreadsheetController(
    SpreadsheetService(
      ApiClient(baseUrl: 'http://localhost'),
    ),
  );
  controller.loadMockData();
  return controller;
}

String _value(SpreadsheetController controller, int column) {
  return controller.spreadsheet!.activeSheet.rows[0].cells[column].value;
}

String? _formula(SpreadsheetController controller, int column) {
  return controller.spreadsheet!.activeSheet.rows[0].cells[column].formula;
}
