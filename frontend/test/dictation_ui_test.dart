import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/shell/dictation_controller.dart';
import 'package:frontend/features/shell/widgets/app_menu_bar.dart';
import 'package:frontend/features/shell/widgets/settings_dialog.dart';
import 'package:frontend/features/shell/widgets/search_bar.dart';
import 'package:frontend/features/shell/widgets/toolbar.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/viewport_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';

import 'support/fake_spreadsheet_service.dart';
import 'support/fake_speech_service.dart';

/// Speech to text in the app: the toolbar microphone, the Tools menu item and
/// the Ctrl+Shift+M shortcut.

SheetModel sheet() {
  CellModel cell(int row, int column, [String value = '']) =>
      CellModel(row: row, column: column, value: value);

  return SheetModel(
    name: 'Sheet1',
    headers: const ['A'],
    allRows: [
      RowModel(index: 0, cells: [cell(0, 0, '1')]),
    ],
    sheetId: 's1',
    rowIds: const ['r1'],
    columnIds: const ['c1'],
  );
}

class Rig {
  Rig({bool supported = true, bool withDocument = true}) {
    speech = FakeSpeechService(supported: supported);
    controller = SpreadsheetController(FakeService());
    viewport = ViewportController();

    if (withDocument) {
      controller.showSheetForTesting(sheet(), filename: 'book.xlsx');
    }

    dictation = DictationController(
      speech: speech,
      spreadsheetController: controller,
      viewportController: viewport,
    );
  }

  late final FakeSpeechService speech;
  late final SpreadsheetController controller;
  late final ViewportController viewport;
  late final DictationController dictation;

  void dispose() {
    dictation.dispose();
    controller.dispose();
    viewport.dispose();
  }
}

Future<void> pumpToolbar(WidgetTester tester, Rig rig, {bool withDictation = true}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Toolbar(
              spreadsheetController: rig.controller,
              viewportController: rig.viewport,
              dictation: withDictation ? rig.dictation : null,
            ),
          ],
        ),
      ),
    ),
  );
}

const micTip = 'Speech to text (Ctrl+Shift+M)';
const stopTip = 'Stop speech to text (Ctrl+Shift+M)';

void main() {
  testWidgets('the toolbar shows a microphone where speech is supported', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);

    await pumpToolbar(tester, rig);

    expect(find.byTooltip(micTip), findsOneWidget);
  });

  testWidgets('no microphone on a platform without speech, or without a dictation controller', (tester) async {
    final unsupported = Rig(supported: false);
    addTearDown(unsupported.dispose);

    await pumpToolbar(tester, unsupported);
    expect(find.byTooltip(micTip), findsNothing);

    final rig = Rig();
    addTearDown(rig.dispose);

    await pumpToolbar(tester, rig, withDictation: false);
    expect(find.byTooltip(micTip), findsNothing);
  });

  testWidgets('tapping the microphone starts listening; tapping again stops and places the text', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await pumpToolbar(tester, rig);

    await tester.tap(find.byTooltip(micTip));
    await tester.pump();

    expect(rig.dictation.isListening, isTrue);
    expect(find.byTooltip(stopTip), findsOneWidget);

    rig.speech.say('hello');
    await tester.tap(find.byTooltip(stopTip));
    await tester.pump();

    expect(rig.viewport.initialEditValue, 'hello');
    expect(find.byTooltip(micTip), findsOneWidget);
  });

  testWidgets('the microphone is disabled without a document', (tester) async {
    final rig = Rig(withDocument: false);
    addTearDown(rig.dispose);
    await pumpToolbar(tester, rig);

    final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.mic));

    expect(button.onPressed, isNull);
  });

  testWidgets('Ctrl+Shift+M starts and stops speech to text', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DictationShortcut(
          dictation: rig.dictation,
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    Future<void> press() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await press();
    expect(rig.dictation.isListening, isTrue);

    rig.speech.say('spoken');
    await press();

    expect(rig.speech.calls, ['start', 'stop']);
    expect(rig.viewport.initialEditValue, 'spoken');
  });

  testWidgets('M alone, or Ctrl+M, does not start it', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DictationShortcut(
          dictation: rig.dictation,
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(rig.speech.calls, isEmpty);
  });

  testWidgets('the Tools menu offers Speech to text, and the planned items stay greyed', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppMenuBar(
                spreadsheetController: rig.controller,
                dictation: rig.dictation,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    PopupMenuItem item(String label) => tester.widget(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
          ),
        ) as PopupMenuItem;

    expect(item(micTip).enabled, isTrue);
    expect(item('Spell check').enabled, isFalse);

    await tester.tap(find.text(micTip));
    await tester.pumpAndSettle();

    expect(rig.dictation.isListening, isTrue);
  });

  testWidgets('without speech support the Tools menu only has the planned items', (tester) async {
    final rig = Rig(supported: false);
    addTearDown(rig.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppMenuBar(
                spreadsheetController: rig.controller,
                dictation: rig.dictation,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    expect(find.text(micTip), findsNothing);
    expect(find.text('Spell check'), findsOneWidget);
  });

  testWidgets('voice search fills the query and filters without editing a cell', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpreadsheetSearchBar(
            spreadsheetController: rig.controller,
            viewportController: rig.viewport,
            dictation: rig.dictation,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Search by voice'));
    await tester.pump();
    await tester.pump();
    expect(rig.dictation.isSearchCapture, isTrue);

    rig.speech.say('quarterly revenue', isFinal: true);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'quarterly revenue');
    expect(rig.controller.searchQuery, 'quarterly revenue');
    expect(rig.viewport.isEditing, isFalse);
    expect(rig.dictation.isSearchCapture, isFalse);
  });

  testWidgets('settings lets the user choose Arabic for the interface', (tester) async {
    final rig = Rig();
    addTearDown(rig.dispose);
    Locale? selectedLocale;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialog(
            spreadsheetController: rig.controller,
            onLocaleChanged: (locale) => selectedLocale = locale,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<Locale>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arabic').last);
    await tester.pumpAndSettle();

    expect(selectedLocale, const Locale('ar'));
  });

  testWidgets('settings are organized into General, Sheet, and Appearance tabs', (
    tester,
  ) async {
    final rig = Rig();
    addTearDown(rig.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialog(
            spreadsheetController: rig.controller,
            dictation: rig.dictation,
          ),
        ),
      ),
    );

    final tabBar = find.byType(TabBar);
    expect(find.descendant(of: tabBar, matching: find.text('General')), findsOneWidget);
    expect(find.descendant(of: tabBar, matching: find.text('Sheet')), findsOneWidget);
    expect(find.descendant(of: tabBar, matching: find.text('Appearance')), findsOneWidget);

    await tester.tap(find.descendant(of: tabBar, matching: find.text('Sheet')));
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(tabBar)).index, 1);

    await tester.tap(find.descendant(of: tabBar, matching: find.text('Appearance')));
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(tabBar)).index, 2);
  });
}
