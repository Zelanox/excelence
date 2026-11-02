import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/live/live_messages.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

/// Two rows, three columns: A1 = 1, B1 = 2, C1 = "=A1+B1" (shows 3).
SheetModel sheet({String sheetId = 's1'}) {
  CellModel cell(int row, int column, [String value = '', String? formula]) =>
      CellModel(row: row, column: column, value: value, formula: formula);

  return SheetModel(
    name: 'Sheet1',
    headers: const ['A', 'B', 'C'],
    allRows: [
      RowModel(index: 0, cells: [
        cell(0, 0, '1'),
        cell(0, 1, '2'),
        cell(0, 2, '3', '=A1+B1'),
      ]),
      RowModel(index: 1, cells: [cell(1, 0), cell(1, 1), cell(1, 2)]),
    ],
    sheetId: sheetId,
    rowIds: const ['r1', 'r2'],
    columnIds: const ['c1', 'c2', 'c3'],
  );
}

BatchMessage batch(
  List<Map<String, dynamic>> ops, {
  String client = 'someone-else-0001',
  String sheetId = 's1',
  String kind = 'ops',
  int revision = 1,
}) {
  return BatchMessage(batch: {
    'revision': revision,
    'kind': kind,
    'client_id': client,
    'client_batch_id': 'b1',
    'sheet_id': sheetId,
    'ops': ops,
  });
}

Map<String, dynamic> setCells(List<List<Object?>> cells) => {
      'op': 'set_cells',
      'cells': [
        for (final c in cells) {'row': c[0], 'column': c[1], 'value': c[2]},
      ],
    };

class Setup {
  Setup(SheetModel model) {
    service = SpreadsheetService(ApiClient(baseUrl: 'http://localhost'));
    controller = SpreadsheetController(service)..showSheetForTesting(model);
    controller.addListener(() => notifications++);
  }

  late final SpreadsheetService service;
  late final SpreadsheetController controller;
  int notifications = 0;

  CellModel cell(int row, int column) =>
      controller.spreadsheet!.activeSheet.allRows[row].cells[column];
}

void main() {
  test('puts the values into the grid and recalculates what depends on them', () {
    final s = Setup(sheet());
    addTearDown(s.controller.dispose);

    final applied = s.controller.applyRemoteBatchForTesting(
      batch([
        setCells([
          ['r1', 'c1', '10'],
        ]),
      ]),
    );

    expect(applied, isTrue);
    expect(s.cell(0, 0).value, '10');
    expect(s.cell(0, 2).value, '12');          // =A1+B1
    expect(s.cell(0, 2).formula, '=A1+B1');
    expect(s.notifications, 1);
  });

  test('a formula typed by someone else stays a formula here too', () {
    final s = Setup(sheet());
    addTearDown(s.controller.dispose);

    s.controller.applyRemoteBatchForTesting(
      batch([
        setCells([
          ['r2', 'c2', '=A1*2'],
        ]),
      ]),
    );

    expect(s.cell(1, 1).formula, '=A1*2');
    expect(s.cell(1, 1).value, '2');
  });

  test('null clears a cell, and several cells and operations are applied together', () {
    final s = Setup(sheet());
    addTearDown(s.controller.dispose);

    final applied = s.controller.applyRemoteBatchForTesting(
      batch([
        setCells([
          ['r1', 'c2', null],
          ['r2', 'c1', 'x'],
        ]),
        setCells([
          ['r2', 'c3', 'y'],
        ]),
      ]),
    );

    expect(applied, isTrue);
    expect(s.cell(0, 1).value, '');
    expect(s.cell(1, 0).value, 'x');
    expect(s.cell(1, 2).value, 'y');
    expect(s.cell(0, 2).value, isNot('3'));   // =A1+B1 was recalculated
  });

  test('changes that cannot be applied leave the grid exactly as it was', () {
    final cases = <String, BatchMessage>{
      'another sheet': batch(
        [
          setCells([
            ['r1', 'c1', 'z'],
          ]),
        ],
        sheetId: 's2',
      ),
      'a kind of entry that is not a batch of operations': batch(
        [
          setCells([
            ['r1', 'c1', 'z'],
          ]),
        ],
        kind: 'resync',
      ),
      'an operation that is not a cell change': batch([
        {'op': 'insert_row', 'before': null, 'id': 'r3'},
      ]),
      'an unknown row': batch([
        setCells([
          ['r9', 'c1', 'z'],
        ]),
      ]),
      'an unknown column': batch([
        setCells([
          ['r1', 'c9', 'z'],
        ]),
      ]),
      'one good cell and one unknown': batch([
        setCells([
          ['r1', 'c1', 'z'],
          ['r9', 'c1', 'z'],
        ]),
      ]),
    };

    cases.forEach((name, message) {
      final s = Setup(sheet());
      addTearDown(s.controller.dispose);

      expect(s.controller.applyRemoteBatchForTesting(message), isFalse, reason: name);
      expect(s.cell(0, 0).value, '1', reason: name);
      expect(s.notifications, 0, reason: name);
    });
  });

  test('a sheet without usable IDs is never changed this way', () {
    final s = Setup(sheet(sheetId: ''));
    addTearDown(s.controller.dispose);

    final applied = s.controller.applyRemoteBatchForTesting(
      batch(
        [
          setCells([
            ['r1', 'c1', 'z'],
          ]),
        ],
        sheetId: '',
      ),
    );

    expect(applied, isFalse);
    expect(s.cell(0, 0).value, '1');
  });

  test('this client\'s own changes are not applied a second time', () {
    final s = Setup(sheet());
    addTearDown(s.controller.dispose);

    final applied = s.controller.applyRemoteBatchForTesting(
      batch(
        [
          setCells([
            ['r1', 'c1', 'from the echo'],
          ]),
        ],
        client: s.service.clientId,
      ),
    );

    expect(applied, isTrue);                   // nothing to do counts as done
    expect(s.cell(0, 0).value, '1');
    expect(s.notifications, 0);
  });
}
