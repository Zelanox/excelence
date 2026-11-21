import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/app/app.dart';
import 'package:frontend/core/connection/connection_scope.dart';
import 'package:frontend/core/connection/server_connection.dart';
import 'package:frontend/features/shell/widgets/connection_form.dart';
import 'package:frontend/features/shell/widgets/settings_dialog.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';

import 'support/fake_spreadsheet_service.dart';

/// The connection form, the first-run screen and the Settings tab.
/// Nothing here touches the network: the connection check is a fake.

class FakeCheck {
  FakeCheck([this.result = ConnectionTestResult.ok]);

  ConnectionTestResult result;
  final List<String> calls = [];

  Future<ConnectionTestResult> call({
    required String address,
    required String token,
  }) async {
    calls.add('$address|$token');
    return result;
  }
}

Future<void> pumpForm(
  WidgetTester tester, {
  required FakeCheck check,
  required Future<void> Function(ServerConnection) onSave,
  ServerConnection? initial,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConnectionForm(
            initial: initial,
            onSave: onSave,
            tester: check.call,
          ),
        ),
      ),
    ),
  );
}

Finder get addressField => find.byType(TextField).first;
Finder get tokenField => find.byType(TextField).last;

void main() {
  group('ConnectionForm', () {
    testWidgets('refuses localhost without asking the server', (tester) async {
      final check = FakeCheck();
      final saved = <ServerConnection>[];

      await pumpForm(tester, check: check, onSave: (c) async => saved.add(c));
      await tester.enterText(addressField, 'localhost:8000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('localhost cannot be used'), findsOneWidget);
      expect(check.calls, isEmpty);
      expect(saved, isEmpty);
    });

    testWidgets('asks for an address when the field is empty', (tester) async {
      final check = FakeCheck();

      await pumpForm(tester, check: check, onSave: (_) async {});
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the server address.'), findsOneWidget);
      expect(check.calls, isEmpty);
    });

    testWidgets('saves the cleaned address and token after a good check', (tester) async {
      final check = FakeCheck();
      final saved = <ServerConnection>[];

      await pumpForm(tester, check: check, onSave: (c) async => saved.add(c));
      await tester.enterText(addressField, ' 192.168.1.20:8000 ');
      await tester.enterText(tokenField, ' secret-token-123 ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(check.calls, ['http://192.168.1.20:8000|secret-token-123']);
      expect(saved, hasLength(1));
      expect(saved.single.address, 'http://192.168.1.20:8000');
      expect(saved.single.token, 'secret-token-123');
    });

    testWidgets('a failed check explains why and offers Save anyway', (tester) async {
      final check = FakeCheck(ConnectionTestResult.unreachable);
      final saved = <ServerConnection>[];

      await pumpForm(tester, check: check, onSave: (c) async => saved.add(c));
      await tester.enterText(addressField, '192.168.1.20:8000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
      expect(saved, isEmpty);
      expect(find.text('Save anyway'), findsOneWidget);

      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(check.calls, hasLength(1)); // it did not check a second time
    });

    testWidgets('changing the text after a failed check goes back to Save', (tester) async {
      final check = FakeCheck(ConnectionTestResult.wrongToken);

      await pumpForm(tester, check: check, onSave: (_) async {});
      await tester.enterText(addressField, '192.168.1.20:8000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Save anyway'), findsOneWidget);

      await tester.enterText(tokenField, 'another-token-123');
      await tester.pump();

      expect(find.text('Save anyway'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Test connection reports the result and saves nothing', (tester) async {
      final check = FakeCheck(ConnectionTestResult.ok);
      final saved = <ServerConnection>[];

      await pumpForm(tester, check: check, onSave: (c) async => saved.add(c));
      await tester.enterText(addressField, '192.168.1.20:8000');
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.text('Connected to the Excelence server.'), findsOneWidget);
      expect(saved, isEmpty);

      check.result = ConnectionTestResult.wrongToken;
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.textContaining('refused the access token'), findsOneWidget);
    });

    testWidgets('shows the reason when the change is blocked', (tester) async {
      await pumpForm(
        tester,
        check: FakeCheck(),
        onSave: (_) async => throw const ConnectionChangeBlocked('Blocked for a reason.'),
      );
      await tester.enterText(addressField, '192.168.1.20:8000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Blocked for a reason.'), findsOneWidget);
    });

    testWidgets('shows a friendly message for an unexpected failure', (tester) async {
      await pumpForm(
        tester,
        check: FakeCheck(),
        onSave: (_) async => throw StateError('boom'),
      );
      await tester.enterText(addressField, '192.168.1.20:8000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Could not apply the new address. Please try again.'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('starts with the saved values and hides the token', (tester) async {
      await pumpForm(
        tester,
        check: FakeCheck(),
        onSave: (_) async {},
        initial: const ServerConnection(address: 'http://192.168.1.20:8000', token: 'abc-def-ghi-jkl'),
      );

      expect(tester.widget<TextField>(addressField).controller!.text, 'http://192.168.1.20:8000');
      expect(tester.widget<TextField>(tokenField).controller!.text, 'abc-def-ghi-jkl');
      expect(tester.widget<TextField>(tokenField).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      expect(tester.widget<TextField>(tokenField).obscureText, isFalse);
    });
  });

  group('ConnectScreen', () {
    testWidgets('connecting hands the connection to the app', (tester) async {
      ServerConnection? connected;

      await tester.pumpWidget(
        ConnectionScope(
          connection: null,
          change: (c) async => connected = c,
          child: MaterialApp(home: ConnectScreen(tester: FakeCheck().call)),
        ),
      );

      expect(find.text('Connect to your Excelence server'), findsOneWidget);

      await tester.enterText(addressField, '192.168.1.20:8000');
      await tester.enterText(tokenField, 'secret-token-123');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(connected?.address, 'http://192.168.1.20:8000');
      expect(connected?.token, 'secret-token-123');
    });
  });

  group('the app', () {
    testWidgets('asks for a server address instead of trying localhost', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const ExcelenceApp());
      await tester.pumpAndSettle();

      expect(find.text('Connect to your Excelence server'), findsOneWidget);
    });

    testWidgets('a saved localhost address is not used', (tester) async {
      SharedPreferences.setMockInitialValues({
        'server_address': 'http://localhost:8000',
      });

      await tester.pumpWidget(const ExcelenceApp());
      await tester.pumpAndSettle();

      expect(find.text('Connect to your Excelence server'), findsOneWidget);
    });
  });

  group('Settings > Connection', () {
    Future<void> openSettings(WidgetTester tester, {ServerConnection? connection, bool withScope = true}) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = SpreadsheetController(FakeService());
      addTearDown(controller.dispose);

      Widget app = MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SettingsDialog.show(context, spreadsheetController: controller),
              child: const Text('open settings'),
            ),
          ),
        ),
      );

      if (withScope) {
        app = ConnectionScope(connection: connection, change: (_) async {}, child: app);
      }

      await tester.pumpWidget(app);
      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('the Connection tab shows the saved server', (tester) async {
      await openSettings(
        tester,
        connection: const ServerConnection(address: 'http://192.168.1.20:8000', token: 'abc-def-ghi-jkl'),
      );

      // The tab bar scrolls sideways when the dialog is narrow.
      await tester.ensureVisible(find.text('Connection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionForm), findsOneWidget);
      expect(tester.widget<TextField>(addressField).controller!.text, 'http://192.168.1.20:8000');
    });

    testWidgets('there is no Connection tab when the app provides no connection', (tester) async {
      await openSettings(tester, withScope: false);

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Connection'), findsNothing);
    });
  });
}
