import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/shell/widgets/app_menu_bar.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';

import 'support/fake_spreadsheet_service.dart';

/// The top menus already have their final shape: items that are not built
/// yet are shown greyed out and do nothing.

Future<void> pumpBar(WidgetTester tester, {double width = 800}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = SpreadsheetController(FakeService());
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [AppMenuBar(spreadsheetController: controller)],
        ),
      ),
    ),
  );
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

void main() {
  test('every top menu has planned items', () {
    expect(
      plannedMenuItems.keys,
      containsAll(['File', 'Edit', 'View', 'Insert', 'Data', 'Tools', 'Help']),
    );

    for (final entry in plannedMenuItems.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
    }
  });

  for (final menu in ['Edit', 'View', 'Insert', 'Data', 'Tools', 'Help']) {
    testWidgets('$menu opens and all its items are greyed out', (tester) async {
      await pumpBar(tester);

      await tester.tap(find.text(menu));
      await tester.pumpAndSettle();

      for (final item in plannedMenuItems[menu]!) {
        expect(find.text(item), findsOneWidget, reason: item);
        expect(isEnabled(tester, item), isFalse, reason: item);
      }
    });
  }

  testWidgets('the File menu lists its planned items greyed out too', (tester) async {
    await pumpBar(tester);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    for (final item in plannedMenuItems['File']!) {
      expect(find.text(item), findsOneWidget, reason: item);
      expect(isEnabled(tester, item), isFalse, reason: item);
    }

    // The working items are still enabled.
    expect(isEnabled(tester, 'New'), isTrue);
    expect(isEnabled(tester, 'Open...'), isTrue);
  });

  testWidgets('the menu bar does not overflow on a very narrow screen', (tester) async {
    await pumpBar(tester, width: 280);

    expect(tester.takeException(), isNull);
    expect(find.text('Help'), findsOneWidget);
  });
}
