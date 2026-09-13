// Basic smoke test: confirms the Excelence app boots and renders without
// throwing. This replaces the default counter-app test that Flutter
// generates on `flutter create` (which tested a `MyApp`/counter widget
// that no longer exists in this project).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/app.dart';

void main() {
  testWidgets('ExcelenceApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const ExcelenceApp());

    // The app should render a MaterialApp as its root widget.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
