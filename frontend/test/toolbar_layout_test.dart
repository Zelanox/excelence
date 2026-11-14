import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/shell/widgets/toolbar.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/viewport_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

/// Round A of docs/UI_REQUIREMENTS.md: the toolbar fits any width.
/// Nothing here talks to a server and no button that sends a request is
/// tapped - the tests look at layout only.

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

class Harness {
  Harness({required this.withSheet}) {
    controller = SpreadsheetController(
      SpreadsheetService(ApiClient(baseUrl: 'http://localhost')),
    );
    if (withSheet) {
      controller.showSheetForTesting(sheet());
    }
    viewport = ViewportController();
  }

  final bool withSheet;
  late final SpreadsheetController controller;
  late final ViewportController viewport;

  void dispose() {
    controller.dispose();
    viewport.dispose();
  }
}

const iconTooltips = <String>[
  'Bold (Ctrl+B)',
  'Italic (Ctrl+I)',
  'Underline (Ctrl+U)',
  'Strikethrough',
  'Text color',
  'Fill color',
];

Future<void> pumpToolbar(
  WidgetTester tester, {
  required double width,
  double scale = 1.0,
  bool rtl = false,
  bool withSheet = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final harness = Harness(withSheet: withSheet);
  addTearDown(harness.dispose);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Column(
          children: [
            Toolbar(
              spreadsheetController: harness.controller,
              viewportController: harness.viewport,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The Font button: icon only (a tooltip) when narrow, with its label
/// when wide.
Finder fontButton({required bool compact}) => compact
    ? find.byTooltip('Font...')
    // TextButton.icon builds a private subclass, so match by type test.
    : find.ancestor(
        of: find.text('Font...'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );

void main() {
  for (final width in [320.0, 360.0, 640.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'every button is reachable at width $width, text scale $scale',
        (tester) async {
          await pumpToolbar(tester, width: width, scale: scale);

          // No overflow stripe or layout exception.
          expect(tester.takeException(), isNull);

          final compact = width < compactToolbarWidth;
          final settings = find.byTooltip('Settings');
          expect(settings, findsOneWidget);
          final settingsRect = tester.getRect(settings);

          final finders = <Finder>[
            for (final tip in iconTooltips) find.byTooltip(tip),
            fontButton(compact: compact),
          ];

          for (final finder in finders) {
            expect(finder, findsOneWidget);

            await tester.ensureVisible(finder);
            await tester.pump();

            final rect = tester.getRect(finder);

            // On screen, not hidden behind the pinned Settings button,
            // and big enough to touch.
            expect(rect.left >= 0, isTrue, reason: '$finder left edge');
            expect(rect.right <= settingsRect.left + 0.5, isTrue,
                reason: '$finder is behind Settings');
            expect(rect.width >= 40 && rect.height >= 40, isTrue,
                reason: '$finder is smaller than 40 px');
          }

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Settings stays on screen when the buttons are scrolled',
      (tester) async {
    await pumpToolbar(tester, width: 320);

    final before = tester.getRect(find.byTooltip('Settings'));
    expect(before.left >= 0 && before.right <= 320, isTrue);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-500, 0),
    );
    await tester.pump();

    expect(tester.getRect(find.byTooltip('Settings')), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Font button is icon-only below 600 wide, full from 600',
      (tester) async {
    await pumpToolbar(tester, width: 599);
    expect(find.text('Font...'), findsNothing);
    expect(find.byTooltip('Font...'), findsOneWidget);

    await pumpToolbar(tester, width: 600);
    expect(find.text('Font...'), findsOneWidget);
    expect(find.byTooltip('Font...'), findsNothing);
  });

  testWidgets('without a document the formatting buttons are disabled',
      (tester) async {
    await pumpToolbar(tester, width: 320, withSheet: false);
    expect(tester.takeException(), isNull);

    IconButton bold() => tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.format_bold),
        );
    IconButton settings() => tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.settings),
        );

    expect(bold().onPressed, isNull);
    expect(settings().onPressed, isNotNull);

    await pumpToolbar(tester, width: 320, withSheet: true);
    expect(bold().onPressed, isNotNull);
  });

  testWidgets('resizing the window while open re-lays the toolbar out',
      (tester) async {
    await pumpToolbar(tester, width: 1200);
    expect(find.text('Font...'), findsOneWidget);

    tester.view.physicalSize = const Size(320, 800);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Font...'), findsNothing);
    expect(find.byTooltip('Font...'), findsOneWidget);
  });

  testWidgets('the toolbar keeps its order in a right-to-left setting',
      (tester) async {
    await pumpToolbar(tester, width: 1200, rtl: true);

    double left(String tooltip) => tester.getRect(find.byTooltip(tooltip)).left;

    expect(left('Bold (Ctrl+B)') < left('Strikethrough'), isTrue);
    expect(left('Strikethrough') < left('Settings'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
