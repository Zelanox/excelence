import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/shell/file_error.dart';
import 'package:frontend/features/spreadsheet/models/document_name.dart';

/// Round B3: what the user reads when a file action fails.

void main() {
  test('connection problems say the server cannot be reached', () {
    for (final error in [
      Exception('ClientException with SocketException: Connection refused (OS Error: Connection refused, errno = 111), address = localhost, port = 60032'),
      Exception('Failed host lookup: server'),
      TimeoutException('slow'),
    ]) {
      expect(
        describeFileError(error, 'open the document'),
        "Can't reach the server. Check the connection and try again.",
      );
    }
  });

  test("the app's own HTTP error wording is replaced by a plain sentence", () {
    final text = describeFileError(
      Exception('Failed to open document: 400 {"detail":"x"}'),
      'open the document',
    );

    expect(text, 'Could not open the document. Check that the server is running and try again.');
    expect(text, isNot(contains('400')));
  });

  test('a message the server wrote for the user is passed through', () {
    expect(
      describeFileError(Exception('A document named a.xlsx already exists.'), 'create the document'),
      'A document named a.xlsx already exists.',
    );
  });

  test('an empty error still gives a sentence', () {
    expect(describeFileError(Exception(''), 'save the document'), startsWith('Could not save the document'));
  });

  test('the name without its extension, for the dialogs', () {
    expect(documentNameWithoutExtension('book.xlsx'), 'book');
    expect(documentNameWithoutExtension('BOOK.XLSX'), 'BOOK');
    expect(documentNameWithoutExtension('reports/q1.xlsx'), 'reports/q1');
    expect(documentNameWithoutExtension('plain'), 'plain');
    expect(documentNameWithoutExtension('تقرير.xlsx'), 'تقرير');
  });
}
