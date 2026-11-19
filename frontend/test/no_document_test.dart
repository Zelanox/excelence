import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/shell/startup_status.dart';
import 'package:frontend/features/shell/widgets/no_document_view.dart';
import 'package:frontend/features/shell/widgets/workspace.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/viewport_controller.dart';

import 'support/fake_spreadsheet_service.dart';

/// Round B3: the "No document open" screen replaces a spinner that never
/// ends, but only once startup has really finished.

Future<(SpreadsheetController, FakeService, StartupStatus, int Function())> pumpWorkspace(
  WidgetTester tester,
) async {
  final service = FakeService();
  final controller = SpreadsheetController(service);
  final viewport = ViewportController();
  final startup = StartupStatus();
  var retries = 0;

  addTearDown(controller.dispose);
  addTearDown(viewport.dispose);
  addTearDown(startup.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Workspace(
              spreadsheetController: controller,
              viewportController: viewport,
              startup: startup,
              onRetry: () => retries++,
            ),
          ],
        ),
      ),
    ),
  );

  return (controller, service, startup, () => retries);
}

void main() {
  test('StartupStatus: begin, finish and clearProblem notify and keep state', () {
    final startup = StartupStatus();
    var heard = 0;
    startup.addListener(() => heard++);

    expect(startup.done, isFalse);

    startup.finish(problem: 'no server');
    expect(startup.done, isTrue);
    expect(startup.problem, 'no server');

    startup.clearProblem();
    expect(startup.problem, isNull);
    expect(heard, 2);

    startup.clearProblem(); // nothing to clear: no notification
    expect(heard, 2);

    startup.begin();
    expect(startup.done, isFalse);
    expect(heard, 3);

    startup.dispose();
  });

  testWidgets('NoDocumentView offers New and Open, and Try again only after a problem', (tester) async {
    final controller = SpreadsheetController(FakeService());
    addTearDown(controller.dispose);

    var retried = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoDocumentView(
            spreadsheetController: controller,
            problem: 'Could not open a document.',
            onRetry: () => retried++,
          ),
        ),
      ),
    );

    expect(find.text('No document open'), findsOneWidget);
    expect(find.text('Could not open a document.'), findsOneWidget);
    expect(find.text('New...'), findsOneWidget);
    expect(find.text('Open...'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retried, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoDocumentView(spreadsheetController: controller),
        ),
      ),
    );

    expect(find.text('Try again'), findsNothing);
    expect(find.text('Could not open a document.'), findsNothing);
  });

  testWidgets('NoDocumentView fits a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = SpreadsheetController(FakeService());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoDocumentView(
            spreadsheetController: controller,
            problem: 'Could not open a document. Check that the server is running and that this device can reach it.',
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('before startup finishes the grid shows its spinner, not the empty screen', (tester) async {
    await pumpWorkspace(tester);

    expect(find.text('No document open'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('after startup with nothing open the empty screen appears', (tester) async {
    final (_, _, startup, retries) = await pumpWorkspace(tester);

    startup.finish(problem: 'The server could not be reached.');
    await tester.pump();

    expect(find.text('No document open'), findsOneWidget);
    expect(find.text('The server could not be reached.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retries(), 1);
  });

  testWidgets('after startup without a problem there is no Try again', (tester) async {
    final (_, _, startup, _) = await pumpWorkspace(tester);

    startup.finish();
    await tester.pump();

    expect(find.text('No document open'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('while a document is being opened the spinner stays', (tester) async {
    final (controller, service, startup, _) = await pumpWorkspace(tester);
    service.openGate = Completer<void>();

    startup.finish();
    await tester.pump();
    expect(find.text('No document open'), findsOneWidget);

    unawaited(controller.loadDocument('book.xlsx'));
    await tester.pump();

    expect(controller.isLoadingDocument, isTrue);
    expect(find.text('No document open'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
