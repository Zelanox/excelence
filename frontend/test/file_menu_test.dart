import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/shell/widgets/app_menu_bar.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/file_action_result.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';

import 'support/fake_spreadsheet_service.dart';

/// Round B3: the File menu, its dialogs and the messages the user reads.
/// The service is scripted (no server); the menu is the real widget.

SheetModel sheet() {
  CellModel cell(int row, int column, [String value = '']) =>
      CellModel(row: row, column: column, value: value);

  return SheetModel(
    name: 'Sheet1',
    headers: const ['A', 'B'],
    allRows: [
      RowModel(index: 0, cells: [cell(0, 0, '1'), cell(0, 1, '2')]),
    ],
    sheetId: 's1',
    rowIds: const ['r1'],
    columnIds: const ['c1', 'c2'],
  );
}

Future<(SpreadsheetController, FakeService)> pumpMenu(
  WidgetTester tester, {
  bool withDocument = true,
}) async {
  final service = FakeService();
  final controller = SpreadsheetController(service);
  addTearDown(controller.dispose);

  if (withDocument) {
    controller.showSheetForTesting(sheet(), filename: 'book.xlsx');
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [AppMenuBar(spreadsheetController: controller)],
        ),
      ),
    ),
  );

  return (controller, service);
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.text('File'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label) async {
  await openMenu(tester);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

bool isEnabled(WidgetTester tester, String label) {
  final item = tester.widget(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    ),
  ) as PopupMenuItem;

  return item.enabled;
}

Future<void> typeName(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

const menuLabels = [
  'New',
  'Open...',
  'Save',
  'Save as...',
  'Rename...',
  'Close',
  'Delete...',
];

const otherPeople = 'Other people are working in this document. Ask them to leave first.';

void main() {
  testWidgets('the File menu offers every action', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    for (final label in menuLabels) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(isEnabled(tester, label), isTrue, reason: label);
    }
  });

  testWidgets('without a document only New and Open are available', (tester) async {
    await pumpMenu(tester, withDocument: false);
    await openMenu(tester);

    expect(isEnabled(tester, 'New'), isTrue);
    expect(isEnabled(tester, 'Open...'), isTrue);

    for (final label in ['Save', 'Save as...', 'Rename...', 'Close', 'Delete...']) {
      expect(isEnabled(tester, label), isFalse, reason: label);
    }
  });

  // ------------------------------------------------------------------ Save

  testWidgets('Save says "Saved." when it worked', (tester) async {
    final (_, service) = await pumpMenu(tester);

    await choose(tester, 'Save');

    expect(service.calls, contains('save'));
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('a failed Save says what to do, never the raw error', (tester) async {
    final (_, service) = await pumpMenu(tester);
    service.saveError = Exception('Failed to save document: 500 <html>boom</html>');

    await choose(tester, 'Save');

    expect(find.text('Could not save the document. Check that the server is running and try again.'), findsOneWidget);
    expect(find.textContaining('<html>'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  // --------------------------------------------------------------- Save as

  testWidgets('Save as asks for a name, copies, and opens the copy', (tester) async {
    final (controller, service) = await pumpMenu(tester);

    await choose(tester, 'Save as...');

    expect(find.text('Save as'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'book copy');

    await typeName(tester, 'copy');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(service.calls, contains('saveAs copy.xlsx'));
    expect(find.byType(TextField), findsNothing); // dialog closed
    expect(find.text('Saved a copy as copy.xlsx.'), findsOneWidget);
    expect(controller.openFilename, 'copy.xlsx');
  });

  testWidgets('a name that is not acceptable is explained in the dialog, without asking the server', (tester) async {
    final (_, service) = await pumpMenu(tester);

    await choose(tester, 'Save as...');
    await typeName(tester, 'a:b');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot contain'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // still open, can be corrected
    expect(service.calls, isEmpty);
  });

  testWidgets('a refused Save as shows the reason inside the dialog and can be cancelled', (tester) async {
    final (controller, service) = await pumpMenu(tester);
    service.saveAsResult = const FileActionResult.failure(
      'A document named copy.xlsx already exists. Choose another name.',
    );

    await choose(tester, 'Save as...');
    await typeName(tester, 'copy');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('A document named copy.xlsx already exists. Choose another name.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(controller.openFilename, 'book.xlsx');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(controller.openFilename, 'book.xlsx');
  });

  // ---------------------------------------------------------------- Rename

  testWidgets('Rename starts from the current name and renames', (tester) async {
    final (controller, service) = await pumpMenu(tester);

    await choose(tester, 'Rename...');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'book');

    await typeName(tester, 'new');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(service.calls, contains('rename new.xlsx'));
    expect(controller.openFilename, 'new.xlsx');
    expect(find.text('Renamed to new.xlsx.'), findsOneWidget);
  });

  testWidgets('Rename refused because others are present explains why', (tester) async {
    final (controller, service) = await pumpMenu(tester);
    service.renameResult = const FileActionResult.failure(otherPeople);

    await choose(tester, 'Rename...');
    await typeName(tester, 'new');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text(otherPeople), findsOneWidget);
    expect(controller.openFilename, 'book.xlsx');
  });

  testWidgets('Rename to the same name is refused in the dialog', (tester) async {
    final (_, service) = await pumpMenu(tester);

    await choose(tester, 'Rename...');
    await typeName(tester, 'BOOK');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('That is already the name of this document.'), findsOneWidget);
    expect(service.calls, isEmpty);
  });

  // ---------------------------------------------------------------- Delete

  testWidgets('Delete asks first; Cancel changes nothing', (tester) async {
    final (controller, service) = await pumpMenu(tester);

    await choose(tester, 'Delete...');

    expect(find.text('Delete book.xlsx?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.calls, isNot(contains('delete')));
    expect(controller.hasDocument, isTrue);
  });

  testWidgets('confirmed Delete removes the document and says so', (tester) async {
    final (controller, service) = await pumpMenu(tester);

    await choose(tester, 'Delete...');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(service.calls, contains('delete'));
    expect(controller.hasDocument, isFalse);
    expect(find.text('Deleted book.xlsx.'), findsOneWidget);
  });

  testWidgets('a refused Delete tells the user and keeps the document', (tester) async {
    final (controller, service) = await pumpMenu(tester);
    service.deleteResult = const FileActionResult.failure(otherPeople);

    await choose(tester, 'Delete...');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Could not delete the document'), findsOneWidget);
    expect(find.text(otherPeople), findsOneWidget);
    expect(controller.hasDocument, isTrue);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Could not delete the document'), findsNothing);
  });

  // ----------------------------------------------------------------- Close

  testWidgets('Close saves and leaves, with no dialog', (tester) async {
    final (controller, service) = await pumpMenu(tester);

    await choose(tester, 'Close');

    expect(service.calls, containsAllInOrder(['save', 'close']));
    expect(controller.hasDocument, isFalse);
  });

  testWidgets('if the save fails, Close offers Cancel, Close anyway and Retry', (tester) async {
    final (controller, service) = await pumpMenu(tester);
    service.saveError = Exception('disk full');

    await choose(tester, 'Close');

    expect(find.text('Could not save your changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Close anyway'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.hasDocument, isTrue); // nothing lost

    await choose(tester, 'Close');
    await tester.tap(find.text('Close anyway'));
    await tester.pumpAndSettle();

    expect(controller.hasDocument, isFalse);
  });

  testWidgets('Retry closes once the save works again', (tester) async {
    final (controller, service) = await pumpMenu(tester);
    service.saveError = Exception('disk full');

    await choose(tester, 'Close');
    expect(find.text('Could not save your changes'), findsOneWidget);

    service.saveError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save your changes'), findsNothing);
    expect(controller.hasDocument, isFalse);
  });
}
