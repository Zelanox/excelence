import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/shell/widgets/formula_bar.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/viewport_controller.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

void main() {
  testWidgets('formula bar Enter commits through the spreadsheet controller', (
    tester,
  ) async {
    final spreadsheetController = _controller();
    final viewportController = ViewportController();
    final spreadsheetFocusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: spreadsheetFocusNode,
            child: FormulaBar(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
              spreadsheetFocusNode: spreadsheetFocusNode,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '=1+2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final cell = spreadsheetController.spreadsheet!.activeSheet.rows[0].cells[0];
    expect(cell.formula, '=1+2');
    expect(cell.value, '3');
    expect(spreadsheetFocusNode.hasFocus, isTrue);

    viewportController.dispose();
    spreadsheetController.dispose();
    spreadsheetFocusNode.dispose();
  });
}

SpreadsheetController _controller() {
  final controller = SpreadsheetController(
    SpreadsheetService(ApiClient(baseUrl: 'http://localhost')),
  );
  controller.loadMockData();
  return controller;
}
