import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/models/text_style_spec.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

void main() {
  test('cell alignment survives style JSON roundtrip', () {
    const style = TextStyleSpec(
      horizontalAlignment: 'right',
      verticalAlignment: 'top',
    );

    expect(TextStyleSpec.fromJson(style.toJson()), style);
    expect(style.toJson(), {
      'horizontal_alignment': 'right',
      'vertical_alignment': 'top',
    });
  });

  test('spreadsheet payload parses row heights by stable row ID', () {
    final data = SpreadsheetData.fromJson({
      'headers': ['Name'],
      'rows': [
        {'Name': 'Alice'},
      ],
      'row_count': 1,
      'column_count': 1,
      'row_ids': ['r1'],
      'row_heights': {'r1': 44},
    });

    expect(data.rowHeights, {'r1': 44.0});
  });

  test('row heights follow their rows through a sorted view', () {
    final sheet = SheetModel(
      name: 'Sheet1',
      allRows: const [
        RowModel(index: 0, cells: []),
        RowModel(index: 1, cells: []),
      ],
      rowIds: const ['r1', 'r2'],
      rowHeights: const {'r2': 52},
      viewToSource: const [1, 0],
    );

    expect(sheet.rowHeightForViewRow(0), 52);
    expect(sheet.rowHeightForViewRow(1), SheetModel.defaultRowHeight);
  });
}
