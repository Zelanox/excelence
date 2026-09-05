import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/presentation/widgets/viewport/cell_editor.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

void main() {
  testWidgets('reference insertion reaches the controller unchanged', (
    tester,
  ) async {
    final insertion = ValueNotifier<String?>(null);
    String? committedText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: '=A1*',
            referenceInsertion: insertion,
            onCommit: (value) => committedText = value,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    insertion.value = 'B2';
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, '=A1*B2');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(committedText, '=A1*B2');

    final controller = _controller();
    controller.editCell(row: 0, column: 0, value: '10');
    controller.editCell(row: 1, column: 1, value: '3');
    controller.editCell(row: 0, column: 2, value: committedText!);

    final cell = controller.spreadsheet!.activeSheet.rows[0].cells[2];
    expect(cell.formula, '=A1*B2');
    expect(cell.value, '30');
  });
}

SpreadsheetController _controller() {
  final controller = SpreadsheetController(
    SpreadsheetService(ApiClient(baseUrl: 'http://localhost')),
  );
  controller.loadMockData();
  return controller;
}
