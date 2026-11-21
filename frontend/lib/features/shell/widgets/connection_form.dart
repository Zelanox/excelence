import 'package:flutter/material.dart';

import '../../../app/app_text.dart';
import '../../../core/connection/connection_scope.dart';
import '../../../core/connection/server_connection.dart';

/// How the form checks a connection (replaced in tests).
typedef ConnectionTester = Future<ConnectionTestResult> Function({
  required String address,
  required String token,
});

Future<ConnectionTestResult> _defaultTester({
  required String address,
  required String token,
}) =>
    testServerConnection(address: address, token: token);

enum _Busy { none, testing, saving }

/// The server address and access token fields with Test connection and Save.
///
/// Used on the first-run screen, in Settings > Connection and in the
/// "Change server address" dialog. Save checks the connection first; if the
/// check fails the message says why and Save becomes "Save anyway", so an
/// address can still be stored before the server is switched on.
class ConnectionForm extends StatefulWidget {
  const ConnectionForm({
    super.key,
    this.initial,
    required this.onSave,
    this.saveLabel = 'Save',
    this.tester = _defaultTester,
  });

  final ServerConnection? initial;

  /// Called with the checked, cleaned-up connection. May throw
  /// [ConnectionChangeBlocked] to show its message instead.
  final Future<void> Function(ServerConnection connection) onSave;

  final String saveLabel;
  final ConnectionTester tester;

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  late final TextEditingController _address =
      TextEditingController(text: widget.initial?.address ?? '');
  late final TextEditingController _token =
      TextEditingController(text: widget.initial?.token ?? '');

  _Busy _busy = _Busy.none;
  String? _message;
  bool _isError = false;
  bool _hideToken = true;

  /// The address and token of the last failed check, so that pressing Save
  /// again for the same values saves them anyway.
  String? _failedKey;

  String get _key => '${_address.text.trim()}|${_token.text.trim()}';

  @override
  void initState() {
    super.initState();
    _address.addListener(_onEdited);
    _token.addListener(_onEdited);
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  void _onEdited() {
    if (mounted) {
      setState(() {});
    }
  }

  AddressCheck? _validate() {
    final check = checkServerAddress(_address.text);

    if (!check.isValid) {
      setState(() {
        _message = addressProblemMessage(check.problem!);
        _isError = true;
      });

      return null;
    }

    return check;
  }

  Future<void> _test() async {
    final check = _validate();

    if (check == null) {
      return;
    }

    final key = _key;

    setState(() {
      _busy = _Busy.testing;
      _message = null;
    });

    final result = await widget.tester(
      address: check.address!,
      token: _token.text.trim(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _busy = _Busy.none;
      _message = connectionResultMessage(result);
      _isError = result != ConnectionTestResult.ok;
      _failedKey = result == ConnectionTestResult.ok ? null : key;
    });
  }

  Future<void> _save() async {
    final check = _validate();

    if (check == null) {
      return;
    }

    final key = _key;
    final token = _token.text.trim();

    if (_failedKey != key) {
      setState(() {
        _busy = _Busy.testing;
        _message = null;
      });

      final result = await widget.tester(address: check.address!, token: token);

      if (!mounted) {
        return;
      }

      if (result != ConnectionTestResult.ok) {
        setState(() {
          _busy = _Busy.none;
          _message = connectionResultMessage(result);
          _isError = true;
          _failedKey = key;
        });

        return;
      }
    }

    setState(() => _busy = _Busy.saving);

    try {
      await widget.onSave(ServerConnection(address: check.address!, token: token));
    } on ConnectionChangeBlocked catch (blocked) {
      if (mounted) {
        setState(() {
          _message = blocked.message;
          _isError = true;
        });
      }
    } catch (error) {
      debugPrint('[Connection] could not apply the new address: $error');

      if (mounted) {
        setState(() {
          _message = 'Could not apply the new address. Please try again.';
          _isError = true;
        });
      }
    }

    if (mounted) {
      setState(() => _busy = _Busy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _busy != _Busy.none;
    final saveAnyway = _failedKey != null && _failedKey == _key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _address,
          enabled: !busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: appText(context, 'Server address'),
            hintText: 'http://192.168.1.20:8000',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          enabled: !busy,
          obscureText: _hideToken,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => busy ? null : _save(),
          decoration: InputDecoration(
            labelText: appText(context, 'Access token (if the server has one)'),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: appText(context, _hideToken ? 'Show' : 'Hide'),
              icon: Icon(_hideToken ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _hideToken = !_hideToken),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            context,
            'The server shows its address and token with: excelence-server config show',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            appText(context, _message!),
            style: TextStyle(
              color: _isError ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: busy ? null : _test,
              child: Text(appText(context, 'Test connection')),
            ),
            FilledButton(
              onPressed: busy ? null : _save,
              child: Text(
                appText(context, saveAnyway ? 'Save anyway' : widget.saveLabel),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ],
    );
  }
}

/// A dialog with just the connection form (opened from "Change server
/// address" when the server cannot be reached).
class ServerAddressDialog extends StatelessWidget {
  const ServerAddressDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const ServerAddressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = ConnectionScope.maybeOf(context);
    final navigator = Navigator.of(context);

    return AlertDialog(
      title: Text(appText(context, 'Server address')),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: ConnectionForm(
            initial: scope?.connection,
            onSave: (connection) async {
              navigator.pop();
              await scope?.change(connection);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => navigator.pop(),
          child: Text(appText(context, 'Close')),
        ),
      ],
    );
  }
}

/// Shown instead of the app until the user has entered a server address.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key, this.tester = _defaultTester});

  final ConnectionTester tester;

  @override
  Widget build(BuildContext context) {
    final scope = ConnectionScope.maybeOf(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lan_outlined, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    appText(context, 'Connect to your Excelence server'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appText(
                      context,
                      'Enter the network address of the PC that runs the server. It is kept on this device; you can change it later in Settings.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConnectionForm(
                    saveLabel: 'Connect',
                    tester: tester,
                    onSave: (connection) async {
                      await scope?.change(connection);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
