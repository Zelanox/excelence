import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/models/document_name.dart';

/// Round B2 of docs/UI_REQUIREMENTS.md: names typed in Save as / Rename.

void main() {
  String? accepted(String input, {String? current}) =>
      checkDocumentName(input, current: current).name;

  String? refusal(String input, {String? current}) =>
      checkDocumentName(input, current: current).error;

  test('.xlsx is added when it is missing, and kept when it is there', () {
    expect(accepted('Budget'), 'Budget.xlsx');
    expect(accepted('Budget.xlsx'), 'Budget.xlsx');
    expect(accepted('Budget.XLSX'), 'Budget.XLSX');
    expect(accepted('Budget v1.2'), 'Budget v1.2.xlsx');
  });

  test('spaces around the name are removed, spaces inside are kept', () {
    expect(accepted('  My Budget  '), 'My Budget.xlsx');
  });

  test('Arabic names and folders are accepted', () {
    expect(accepted('تقرير'), 'تقرير.xlsx');
    expect(accepted('reports/الربع الأول'), 'reports/الربع الأول.xlsx');
    expect(accepted('a/b/c'), 'a/b/c.xlsx');
  });

  test('empty and blank names are refused', () {
    expect(refusal(''), isNotNull);
    expect(refusal('    '), isNotNull);
  });

  test('characters Windows does not allow are refused', () {
    for (final bad in ['a\\b', 'a:b', 'a*b', 'a?b', 'a"b', 'a<b', 'a>b', 'a|b']) {
      expect(refusal(bad), contains('cannot contain'), reason: bad);
    }
  });

  test('control characters are refused', () {
    expect(refusal('a\u0000b'), isNotNull);
    expect(refusal('a\nb'), isNotNull);
    expect(refusal('a\tb'), isNotNull);
  });

  test('paths that climb out of the documents folder are refused', () {
    for (final bad in ['../x', 'a/../b', '/abs', 'a//b', 'a/', './x', 'a/./b']) {
      expect(refusal(bad), isNotNull, reason: bad);
    }
  });

  test('a segment may not start or end with a space', () {
    expect(refusal('a /b'), isNotNull);
    expect(refusal('a/ b'), isNotNull);
  });

  test('a name made only of the extension is refused', () {
    expect(refusal('.xlsx'), contains('before .xlsx'));
    expect(refusal('folder/.xlsx'), contains('before .xlsx'));
  });

  test('other spreadsheet extensions are refused, not doubled', () {
    for (final bad in ['a.xls', 'a.xlsm', 'a.csv', 'a.ods', 'A.CSV']) {
      expect(refusal(bad), contains('Only .xlsx'), reason: bad);
    }
  });

  test('the name of the open document is refused, in any letter case', () {
    expect(refusal('Budget', current: 'Budget.xlsx'), contains('already the name'));
    expect(refusal('BUDGET.xlsx', current: 'budget.xlsx'), contains('already the name'));
    expect(accepted('Budget 2', current: 'Budget.xlsx'), 'Budget 2.xlsx');
  });

  test('a successful check has no error and a failed one has no name', () {
    final good = checkDocumentName('x');
    expect(good.ok, isTrue);
    expect(good.error, isNull);

    final bad = checkDocumentName('');
    expect(bad.ok, isFalse);
    expect(bad.name, isNull);
  });

  test('a very long name is passed on (the server has the last word)', () {
    expect(accepted('a' * 300), '${'a' * 300}.xlsx');
  });
}
