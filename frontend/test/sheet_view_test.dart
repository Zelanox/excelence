import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_view.dart';

/// Builds canonical rows from plain values: `rows([['Alice', '90'], ...])`.
List<RowModel> rows(List<List<String>> values) {
  return [
    for (int r = 0; r < values.length; r++)
      RowModel(
        index: r,
        cells: [
          for (int c = 0; c < values[r].length; c++)
            CellModel(row: r, column: c, value: values[r][c]),
        ],
      ),
  ];
}

SheetModel sheet(List<List<String>> values) {
  return SheetModel(
    name: 'Sheet1',
    allRows: rows(values),
    headers: const ['Name', 'Score'],
  );
}

/// The first column of the rows currently SHOWN.
List<String> shownNames(SheetModel sheet) {
  return [for (final row in sheet.rows) row.cells.first.value];
}

/// The first column of the canonical rows.
List<String> dataNames(SheetModel sheet) {
  return [for (final row in sheet.allRows) row.cells.first.value];
}

final scores = [
  ['Alice', '90'],
  ['Bob', '85'],
  ['Charlie', '95'],
  ['Dana', '70'],
];

void main() {
  group('no view', () {
    test('shows every row, in order, as the very same list', () {
      final s = sheet(scores);

      expect(s.isViewActive, isFalse);
      expect(identical(s.rows, s.allRows), isTrue);
      expect(s.sourceRowOf(2), 2);
      expect(s.viewRowOf(2), 2);
      expect(SheetView.none.isIdentity, isTrue);
      expect(SheetView.none.apply(const ['Name', 'Score'], s.allRows), isNull);
    });
  });

  group('search', () {
    test('matches any cell, case-insensitively', () {
      final s = sheet(scores).withView(const SheetView(searchQuery: 'AL'));
      expect(shownNames(s), ['Alice']);

      final byNumber = sheet(scores).withView(const SheetView(searchQuery: '9'));
      expect(shownNames(byNumber), ['Alice', 'Charlie']); // 90 and 95
    });

    test('is a literal match, not a pattern', () {
      final s = sheet([
        ['a.b', '1'],
        ['axb', '2'],
        ['(x', '3'],
      ]);

      expect(shownNames(s.withView(const SheetView(searchQuery: 'a.b'))), ['a.b']);
      expect(shownNames(s.withView(const SheetView(searchQuery: '('))), ['(x']);
    });

    test('blank or whitespace-only means no filter', () {
      expect(sheet(scores).withView(const SheetView(searchQuery: '   ')).isViewActive, isFalse);
      expect(sheet(scores).withView(const SheetView(searchQuery: '')).isViewActive, isFalse);
    });

    test('a query nothing matches shows no rows but keeps the data', () {
      final s = sheet(scores).withView(const SheetView(searchQuery: 'zzz'));
      expect(s.rows, isEmpty);
      expect(s.allRows.length, 4);
    });
  });

  group('sort', () {
    test('numbers first (numerically), ascending and descending', () {
      final asc = sheet(scores).withView(const SheetView(sortColumn: 'Score'));
      expect(shownNames(asc), ['Dana', 'Bob', 'Alice', 'Charlie']);

      final desc = sheet(scores).withView(
        const SheetView(sortColumn: 'Score', sortAscending: false),
      );
      expect(shownNames(desc), ['Charlie', 'Alice', 'Bob', 'Dana']);
    });

    test('numbers sort as numbers, not as text ("9" before "10")', () {
      final s = sheet([
        ['a', '10'],
        ['b', '9'],
        ['c', '100'],
      ]).withView(const SheetView(sortColumn: 'Score'));

      expect(shownNames(s), ['b', 'a', 'c']);
    });

    test('numbers, then text (case-insensitive), then blanks - blanks always last', () {
      final values = [
        ['r0', '3'],
        ['r1', 'banana'],
        ['r2', ''],
        ['r3', '1'],
        ['r4', 'Apple'],
        ['r5', '   '],
        ['r6', '2.5'],
        ['r7', 'cherry'],
      ];

      final asc = sheet(values).withView(const SheetView(sortColumn: 'Score'));
      expect(shownNames(asc), ['r3', 'r6', 'r0', 'r4', 'r1', 'r7', 'r2', 'r5']);

      final desc = sheet(values).withView(
        const SheetView(sortColumn: 'Score', sortAscending: false),
      );
      expect(shownNames(desc), ['r7', 'r1', 'r4', 'r0', 'r6', 'r3', 'r2', 'r5']);
    });

    test('ties keep their original order (the sort is stable)', () {
      final s = sheet([
        ['first', 'x'],
        ['second', 'X'],
        ['third', 'x'],
      ]).withView(const SheetView(sortColumn: 'Score'));

      expect(shownNames(s), ['first', 'second', 'third']);

      final desc = sheet([
        ['first', 'x'],
        ['second', 'X'],
        ['third', 'x'],
      ]).withView(const SheetView(sortColumn: 'Score', sortAscending: false));

      expect(shownNames(desc), ['first', 'second', 'third']);
    });

    test('a sort column that no longer exists is ignored', () {
      final s = sheet(scores).withView(const SheetView(sortColumn: 'Gone'));
      expect(s.isViewActive, isFalse);
      expect(shownNames(s), ['Alice', 'Bob', 'Charlie', 'Dana']);
    });

    test('search then sort: the filtered rows are sorted', () {
      final s = sheet(scores).withView(
        const SheetView(
          searchQuery: 'a',
          sortColumn: 'Score',
          sortAscending: false,
        ),
      );

      // Alice 90, Charlie 95, Dana 70 contain "a"; Bob does not.
      expect(shownNames(s), ['Charlie', 'Alice', 'Dana']);
    });
  });

  group('shown rows versus data rows', () {
    test('a shown row maps back to the data row it really is', () {
      final s = sheet(scores).withView(
        const SheetView(sortColumn: 'Score', sortAscending: false),
      ); // Charlie(2), Alice(0), Bob(1), Dana(3)

      expect(s.sourceRowOf(0), 2);
      expect(s.sourceRowOf(2), 1);
      expect(s.viewRowOf(1), 2); // Bob (data row 1) is shown at position 2
      expect(s.isViewActive, isTrue);
    });

    test('a row the filter hides has no shown position', () {
      final s = sheet(scores).withView(const SheetView(searchQuery: 'dana'));

      expect(s.rows.length, 1);
      expect(s.sourceRowOf(0), 3);
      expect(s.viewRowOf(3), 0);
      expect(s.viewRowOf(0), isNull); // Alice is hidden
    });

    test('changing the view never changes the data', () {
      final s = sheet(scores);
      final sorted = s.withView(const SheetView(sortColumn: 'Score'));
      final filtered = sorted.withView(const SheetView(searchQuery: 'bob'));

      expect(dataNames(sorted), dataNames(s));
      expect(dataNames(filtered), dataNames(s));
      expect(filtered.allRows.length, 4);
    });

    test('editing a canonical row keeps the current order and filter', () {
      final s = sheet(scores).withView(
        const SheetView(sortColumn: 'Score', sortAscending: false),
      ); // Charlie, Alice, Bob, Dana

      final edited = s.withSourceRows({
        1: RowModel(
          index: 1,
          cells: [
            CellModel(row: 1, column: 0, value: 'Robert'),
            CellModel(row: 1, column: 1, value: '85'),
          ],
        ),
      });

      expect(dataNames(edited), ['Alice', 'Robert', 'Charlie', 'Dana']);
      // The order is frozen: Robert stays where Bob was shown.
      expect(shownNames(edited), ['Charlie', 'Alice', 'Robert', 'Dana']);
      // The original is untouched.
      expect(dataNames(s), ['Alice', 'Bob', 'Charlie', 'Dana']);
    });

    test('withSourceRows with nothing to change returns the same sheet', () {
      final s = sheet(scores);
      expect(identical(s.withSourceRows(const {}), s), isTrue);
    });

    test('copyWith keeps both the data and the view', () {
      final s = sheet(scores).withView(const SheetView(searchQuery: 'a'));
      final renamed = s.copyWith(name: 'Other');

      expect(renamed.name, 'Other');
      expect(shownNames(renamed), shownNames(s));
      expect(dataNames(renamed), dataNames(s));
    });

    test('the view can be recomputed after the data changes shape', () {
      var s = sheet(scores).withView(const SheetView(sortColumn: 'Score'));

      // A refresh from the server brings a fifth row; the same view is re-applied.
      s = SheetModel(
        name: 'Sheet1',
        allRows: rows([...scores, ['Eve', '80']]),
        headers: const ['Name', 'Score'],
      ).withView(s.view);

      expect(shownNames(s), ['Dana', 'Eve', 'Bob', 'Alice', 'Charlie']);
    });
  });
}
