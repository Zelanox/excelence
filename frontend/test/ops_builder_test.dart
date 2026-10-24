import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/services/ops_builder.dart';

SheetModel sheet({
  String sheetId = 's1',
  List<String> rowIds = const ['r1', 'r2'],
  List<String> columnIds = const ['c1', 'c2'],
}) {
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
    sheetId: sheetId,
    rowIds: rowIds,
    columnIds: columnIds,
  );
}

void main() {
  test('names rows, columns and the sheet by their IDs', () {
    final batch = buildSetCellsBatch(
      sheet: sheet(),
      edits: [
        (row: 1, column: 0, value: 'hello'),
        (row: 0, column: 1, value: '=A1+1'),
      ],
      clientBatchId: 'b-1',
      baseRevision: 7,
    );

    expect(batch, {
      'client_batch_id': 'b-1',
      'base_revision': 7,
      'sheet_id': 's1',
      'ops': [
        {
          'op': 'set_cells',
          'cells': [
            {'row': 'r2', 'column': 'c1', 'value': 'hello'},
            {'row': 'r1', 'column': 'c2', 'value': '=A1+1'},
          ],
        },
      ],
    });
  });

  test('an empty value is sent as the empty text, like the older request', () {
    final batch = buildSetCellsBatch(
      sheet: sheet(),
      edits: [(row: 0, column: 0, value: '')],
      clientBatchId: 'b-1',
    )!;

    final cell = (batch['ops'] as List).single['cells'].single;

    expect(cell['value'], '');
    expect(batch['base_revision'], 0);
  });

  test('no batch when the sheet has no IDs or they do not match its shape', () {
    final edits = [(row: 0, column: 0, value: 'x')];

    expect(
      buildSetCellsBatch(sheet: sheet(sheetId: ''), edits: edits, clientBatchId: 'b'),
      isNull,
    );
    expect(
      buildSetCellsBatch(sheet: sheet(rowIds: const ['r1']), edits: edits, clientBatchId: 'b'),
      isNull,
    );
    expect(
      buildSetCellsBatch(sheet: sheet(columnIds: const []), edits: edits, clientBatchId: 'b'),
      isNull,
    );
  });

  test('no batch for edits outside the sheet, no edits, or too many', () {
    expect(
      buildSetCellsBatch(
        sheet: sheet(),
        edits: [(row: 2, column: 0, value: 'x')],
        clientBatchId: 'b',
      ),
      isNull,
    );
    expect(
      buildSetCellsBatch(
        sheet: sheet(),
        edits: [(row: 0, column: -1, value: 'x')],
        clientBatchId: 'b',
      ),
      isNull,
    );
    expect(buildSetCellsBatch(sheet: sheet(), edits: const [], clientBatchId: 'b'), isNull);
    expect(
      buildSetCellsBatch(
        sheet: sheet(),
        edits: [
          for (var i = 0; i <= maxOpsBatchSize; i++) (row: 0, column: 0, value: '$i'),
        ],
        clientBatchId: 'b',
      ),
      isNull,
    );
  });

  test('batch ids are unique and short enough for the server', () {
    final ids = BatchIdGenerator();
    final seen = <String>{for (var i = 0; i < 1000; i++) ids.next()};

    expect(seen, hasLength(1000));
    expect(seen.every((id) => id.isNotEmpty && id.length <= 64), isTrue);
  });
}
