import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/spreadsheet/presentation/widgets/viewport/cell_editor.dart';

void main() {
  testWidgets('inserts a formula reference at the current cursor', (
    tester,
  ) async {
    final insertion = ValueNotifier<String?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: '=SUM(',
            referenceInsertion: insertion,
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    insertion.value = 'A1:A5';
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, '=SUM(A1:A5');
    expect(textField.controller!.selection.baseOffset, '=SUM(A1:A5'.length);
  });

  testWidgets('initializes a direct-typing buffer with a collapsed cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: 'H',
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'H');
    expect(textField.controller!.selection.isCollapsed, isTrue);
    expect(textField.controller!.selection.baseOffset, 1);
  });

  testWidgets('keeps the initial formula character caret collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: '=',
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(
      textField.controller!.selection,
      const TextSelection.collapsed(offset: 1),
    );
  });

  testWidgets('places the cursor after existing cell text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: 'Hello',
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'Hello');
    expect(textField.controller!.selection.isCollapsed, isTrue);
    expect(textField.controller!.selection.baseOffset, 5);
  });

  testWidgets('places the cursor after an existing formula', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: '=A1+B1',
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.selection.isCollapsed, isTrue);
    expect(textField.controller!.selection.baseOffset, 6);
  });

  testWidgets('typing after existing text appends at the cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: 'hello',
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'helloX');

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'helloX');
  });

  testWidgets('direct-typing buffer keeps its initial character', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellEditor(
            initialValue: 'H',
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'He');

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'He');
  });
}
