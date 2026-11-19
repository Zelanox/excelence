import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/models/file_action_result.dart';

import 'support/fake_spreadsheet_service.dart';

/// Round B2: Save as, Rename, Delete and Close in the controller, against a
/// scripted service (no server). Every call the controller makes is logged
/// in [FakeService.calls] so the ORDER of what happens can be checked.

Future<(SpreadsheetController, FakeService)> opened([String name = 'book.xlsx']) async {
  final service = FakeService();
  final controller = SpreadsheetController(service);
  addTearDown(controller.dispose);

  await controller.loadDocument(name);
  service.calls.clear();

  return (controller, service);
}

int at(FakeService service, String call) => service.calls.indexOf(call);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- Save as

  test('Save as copies, then opens the copy', () async {
    final (controller, service) = await opened();

    final result = await controller.saveDocumentAs('copy');

    expect(result.ok, isTrue);
    expect(result.name, 'copy.xlsx');
    expect(controller.openFilename, 'copy.xlsx');
    expect(controller.hasDocument, isTrue);
    expect(at(service, 'saveAs copy.xlsx'), isNonNegative);
    expect(at(service, 'open copy.xlsx'), greaterThan(at(service, 'saveAs copy.xlsx')));
    expect(controller.isFileActionBusy, isFalse);
  });

  test('names that are not acceptable never reach the server', () async {
    final (controller, service) = await opened();

    for (final bad in ['', '   ', 'a:b', '../x', 'book.xlsx', 'BOOK', 'a.csv']) {
      final result = await controller.saveDocumentAs(bad);
      expect(result.ok, isFalse, reason: bad);
      expect(result.message, isNotEmpty, reason: bad);
    }

    expect((await controller.renameDocument('book')).ok, isFalse);
    expect(service.calls, isEmpty);
    expect(controller.openFilename, 'book.xlsx');
  });

  test('a refused Save as returns the reason and changes nothing', () async {
    final (controller, service) = await opened();
    service.saveAsResult = const FileActionResult.failure(
      'A document named copy.xlsx already exists. Choose another name.',
    );

    final result = await controller.saveDocumentAs('copy');

    expect(result.ok, isFalse);
    expect(result.message, contains('already exists'));
    expect(controller.openFilename, 'book.xlsx');
    expect(service.calls.where((c) => c.startsWith('open ')), isEmpty);
    expect(controller.isFileActionBusy, isFalse);
  });

  test('if the copy cannot be opened, the original is opened again', () async {
    final (controller, service) = await opened();
    service.openErrors['copy.xlsx'] = Exception('boom');

    final result = await controller.saveDocumentAs('copy');

    expect(result.ok, isFalse);
    expect(result.message, contains('copy.xlsx'));
    expect(result.message, isNot(contains('boom')));
    expect(at(service, 'open book.xlsx'), greaterThan(at(service, 'open copy.xlsx')));
    expect(controller.openFilename, 'book.xlsx');
    expect(controller.hasDocument, isTrue);
  });

  // ----------------------------------------------------------------- Rename

  test('Rename renames, then reopens under the new name', () async {
    final (controller, service) = await opened();

    final result = await controller.renameDocument('new');

    expect(result.ok, isTrue);
    expect(result.name, 'new.xlsx');
    expect(controller.openFilename, 'new.xlsx');
    expect(at(service, 'open new.xlsx'), greaterThan(at(service, 'rename new.xlsx')));
    expect(service.calls.where((c) => c == 'sheets'), hasLength(1)); // only loadDocument's own
  });

  test('a refused Rename keeps the document and checks the session is still open', () async {
    final (controller, service) = await opened();
    service.renameResult = const FileActionResult.failure(
      'Other people are working in this document. Ask them to leave first.',
    );

    final result = await controller.renameDocument('new');

    expect(result.ok, isFalse);
    expect(result.message, contains('Other people'));
    expect(controller.openFilename, 'book.xlsx');
    expect(controller.hasDocument, isTrue);
    expect(service.calls.where((c) => c.startsWith('open ')), isEmpty);
    expect(service.calls, contains('sheets')); // the harmless "are we still open?" question
    expect(controller.isFileActionBusy, isFalse);
  });

  test('if the renamed document cannot be opened, the app says so and shows no document', () async {
    final (controller, service) = await opened();
    service.openErrors['new.xlsx'] = Exception('boom');

    final result = await controller.renameDocument('new');

    expect(result.ok, isFalse);
    expect(result.message, contains('renamed to new.xlsx'));
    expect(controller.hasDocument, isFalse);
    expect(controller.openFilename, isNull);
  });

  // ----------------------------------------------------------------- Delete

  test('Delete removes the document and returns to no document', () async {
    final (controller, service) = await opened();

    final result = await controller.deleteDocument();

    expect(result.ok, isTrue);
    expect(result.name, 'book.xlsx');
    expect(controller.hasDocument, isFalse);
    expect(controller.openFilename, isNull);
    expect(controller.hasUnsavedChanges, isFalse);
    expect(service.calls, contains('delete'));

    // Repeated action: nothing is open now, and nothing is sent.
    service.calls.clear();
    final again = await controller.deleteDocument();
    expect(again.ok, isFalse);
    expect(again.message, 'Open a document first.');
    expect(service.calls, isEmpty);
  });

  test('a refused Delete keeps the document', () async {
    final (controller, service) = await opened();
    service.deleteResult = const FileActionResult.failure(
      'Other people are working in this document. Ask them to leave first.',
    );

    final result = await controller.deleteDocument();

    expect(result.ok, isFalse);
    expect(controller.hasDocument, isTrue);
    expect(controller.openFilename, 'book.xlsx');
    expect(service.calls, contains('sheets'));
  });

  // ------------------------------------------------------------------ Close

  test('Close saves first, then leaves the document', () async {
    final (controller, service) = await opened();

    final result = await controller.closeCurrentDocument();

    expect(result.ok, isTrue);
    expect(controller.hasDocument, isFalse);
    expect(at(service, 'save'), isNonNegative);
    expect(at(service, 'close'), greaterThan(at(service, 'save')));
  });

  test('if the save fails, Close stops and says so; "close anyway" closes without saving', () async {
    final (controller, service) = await opened();
    service.saveError = Exception('disk full');

    final stopped = await controller.closeCurrentDocument();

    expect(stopped.ok, isFalse);
    expect(stopped.saveFailed, isTrue);
    expect(stopped.message, isNot(contains('disk full')));
    expect(controller.hasDocument, isTrue);
    expect(service.calls, isNot(contains('close')));

    service.calls.clear();
    final forced = await controller.closeCurrentDocument(force: true);

    expect(forced.ok, isTrue);
    expect(controller.hasDocument, isFalse);
    expect(service.calls, isNot(contains('save')));
    expect(service.calls, contains('close'));
  });

  // ------------------------------------------------------------ Everything

  test('with no document open every action says so and sends nothing', () async {
    final service = FakeService();
    final controller = SpreadsheetController(service);
    addTearDown(controller.dispose);

    for (final result in [
      await controller.saveDocumentAs('x'),
      await controller.renameDocument('x'),
      await controller.deleteDocument(),
      await controller.closeCurrentDocument(),
    ]) {
      expect(result.ok, isFalse);
      expect(result.message, 'Open a document first.');
    }

    expect(service.calls, isEmpty);
  });

  test('a second action is refused while one is running', () async {
    final (controller, service) = await opened();
    final gate = Completer<void>();
    service.renameGate = gate;

    final first = controller.renameDocument('new');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isFileActionBusy, isTrue);

    final second = await controller.deleteDocument();
    expect(second.ok, isFalse);
    expect(second.message, contains('Another file action'));
    expect(service.calls, isNot(contains('delete')));

    gate.complete();
    final result = await first;

    expect(result.ok, isTrue);
    expect(controller.isFileActionBusy, isFalse);
    expect(controller.openFilename, 'new.xlsx');
  });

  test('listeners hear when an action starts and when it ends', () async {
    final (controller, _) = await opened();
    final busyStates = <bool>[];
    controller.addListener(() => busyStates.add(controller.isFileActionBusy));

    await controller.saveDocumentAs('copy');

    expect(busyStates.first, isTrue);
    expect(busyStates.last, isFalse);
  });
}
