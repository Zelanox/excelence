import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_view.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

SheetModel sheetWithIds() {
  return SheetModel(
    name: 'Sheet1',
    headers: const ['A', 'B'],
    allRows: [
      for (var r = 0; r < 2; r++)
        RowModel(
          index: r,
          cells: [
            for (var c = 0; c < 2; c++) CellModel(row: r, column: c),
          ],
        ),
    ],
    sheetId: 's1',
    rowIds: const ['r1', 'r2'],
    columnIds: const ['c1', 'c2'],
  );
}

void main() {
  test('grid data carries the stable IDs the server sends', () {
    final data = SpreadsheetData.fromJson({
      'headers': ['A', 'B'],
      'rows': [
        {'A': '1', 'B': '2'},
      ],
      'row_ids': ['r1'],
      'column_ids': ['c1', 'c2'],
      'current_sheet_id': 's3',
      'revision': 9,
    });

    expect(data.sheetId, 's3');
    expect(data.rowIds, ['r1']);
    expect(data.columnIds, ['c1', 'c2']);
    expect(data.revision, 9);
  });

  test('data from a server without IDs simply has none', () {
    final data = SpreadsheetData.fromJson({'headers': [], 'rows': []});

    expect(data.sheetId, '');
    expect(data.rowIds, isEmpty);
    expect(data.columnIds, isEmpty);
  });

  test('a sheet knows whether its IDs describe it completely', () {
    expect(sheetWithIds().hasIds, isTrue);

    expect(SheetModel(name: 'x', allRows: const []).hasIds, isFalse);
    expect(
      SheetModel(
        name: 'x',
        allRows: const [],
        sheetId: 's1',
        rowIds: const ['r1'],
      ).hasIds,
      isFalse,
    );
  });

  test('the IDs survive a view, replaced rows and other copies', () {
    final sheet = sheetWithIds();

    final viewed = sheet.withView(SheetView.none);
    final edited = sheet.withSourceRows({
      0: RowModel(index: 0, cells: [
        const CellModel(row: 0, column: 0, value: 'x'),
        const CellModel(row: 0, column: 1),
      ]),
    });
    final renamed = sheet.copyWith(name: 'Other');

    for (final copy in [viewed, edited, renamed]) {
      expect(copy.sheetId, 's1');
      expect(copy.rowIds, ['r1', 'r2']);
      expect(copy.columnIds, ['c1', 'c2']);
      expect(copy.hasIds, isTrue);
    }
  });

  test('a changed header list that no longer matches the columns turns the IDs off', () {
    final grown = sheetWithIds().copyWith(headers: const ['A', 'B', 'C']);

    expect(grown.hasIds, isFalse);
  });

  test('reads the server answer to a batch', () {
    final accepted = OpsResult.fromJson({
      'accepted': true,
      'revision': 12,
      'duplicate': false,
      'dropped': [
        {'reason': 'ROW_DELETED', 'row': 'r9'},
      ],
    });
    final refused = OpsResult.fromJson({
      'accepted': false,
      'code': 'UNKNOWN_ROW',
      'message': 'No such row.',
    });

    expect(accepted.accepted, isTrue);
    expect(accepted.revision, 12);
    expect(accepted.dropped.single['reason'], 'ROW_DELETED');
    expect(refused.accepted, isFalse);
    expect(refused.code, 'UNKNOWN_ROW');
    expect(refused.message, 'No such row.');
  });
}
