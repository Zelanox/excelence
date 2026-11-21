import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/viewport_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/presentation_v2/widgets/grid_column_header.dart';
import 'package:frontend/features/spreadsheet/presentation_v2/widgets/spreadsheet_grid.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

import 'support/fake_spreadsheet_service.dart';

class _AutoFitService extends FakeService {
  double? savedWidth;

  @override
  Future<SpreadsheetData> setColumnWidth({
    required String name,
    required double width,
  }) async {
    savedWidth = width;
    return SpreadsheetData(
      headers: [name],
      rows: const [],
      rowCount: 0,
      columnCount: 1,
    );
  }
}

void main() {
  testWidgets('double-click fits and saves content from filtered rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = _AutoFitService();
    final spreadsheet = SpreadsheetController(service);
    final viewport = ViewportController();
    spreadsheet.showSheetForTesting(
      SheetModel(
        name: 'Sheet1',
        headers: const ['Details'],
        allRows: const [
          RowModel(index: 0, cells: [CellModel(row: 0, column: 0, value: 'x')]),
          RowModel(
            index: 1,
            cells: [
              CellModel(
                row: 1,
                column: 0,
                value:
                    'This long cell value is hidden by the current filter and must still fit.',
              ),
            ],
          ),
        ],
        viewToSource: const [0],
      ),
    );
    addTearDown(spreadsheet.dispose);
    addTearDown(viewport.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpreadsheetGrid(
            spreadsheetController: spreadsheet,
            viewportController: viewport,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byType(GridColumnHeader).first;
    final headerRect = tester.getRect(header);
    final resizeEdge = Offset(headerRect.right - 5, headerRect.center.dy);

    await tester.tapAt(resizeEdge);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(resizeEdge);
    await tester.pumpAndSettle();

    final width = spreadsheet.spreadsheet!.activeSheet.columnWidths['Details'];
    expect(width, greaterThan(SpreadsheetGrid.columnWidth));
    expect(service.savedWidth, width);
    expect(find.byType(TextField), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
