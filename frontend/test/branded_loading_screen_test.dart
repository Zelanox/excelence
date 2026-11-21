import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/branded_loading_screen.dart';

void main() {
  testWidgets('shows the animated Excelence Z/E loading mark', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Excelence loading',
      ),
      findsOneWidget,
    );
    expect(find.text('Excelence'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
