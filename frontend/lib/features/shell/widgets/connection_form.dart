import 'package:flutter/material.dart';

import '../../../app/app_text.dart';
import '../../../core/connection/connection_scope.dart';
import '../../../core/connection/server_connection.dart';
import '../../../core/connection/server_discovery.dart';

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

/// How the form looks for servers on the network (replaced in tests).
typedef ServerFinder = Future<List<DiscoveredServer>> Function({
  required String token,
});

Future<List<DiscoveredServer>> _defaultFinder({required String token}) =>
    findServers(token: token);

enum _Busy { none, testing, saving, finding }

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
    this.finder = _defaultFinder,
    this.searchSupported = networkSearchAvailable,
  });

  final ServerConnection? initial;

  /// Called with the checked, cleaned-up connection. May throw
  /// [ConnectionChangeBlocked] to show its message instead.
  final Future<void> Function(ServerConnection connection) onSave;

  final String saveLabel;
  final ConnectionTester tester;
  final ServerFinder finder;

  /// False in a browser: Find server then explains that it cannot search.
  final bool searchSupported;

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

  /// Looks for the server on the network and fills in its address. The
  /// access token must be typed first: it is how the server proves it is
  /// yours (the token itself is never sent).
  Future<void> _find() async {
    if (!widget.searchSupported) {
      setState(() {
        _message = 'Searching the network is not possible in a web browser. Type the server address.';
        _isError = true;
      });

      return;
    }

    final token = _token.text.trim();

    if (token.isEmpty) {
      setState(() {
        _message = 'Enter the access token first: it is how your server is recognised.';
        _isError = true;
      });

      return;
    }

    setState(() {
      _busy = _Busy.finding;
      _message = null;
    });

    final found = await widget.finder(token: token);

    if (!mounted) {
      return;
    }

    if (found.isEmpty) {
      setState(() {
        _busy = _Busy.none;
        _message =
            'No server found with this token. Check that the server is running on this network and that discovery is allowed through its firewall (UDP 8765), or type the address.';
        _isError = true;
      });

      return;
    }

    setState(() => _busy = _Busy.none);

    final chosen = found.length == 1
        ? found.single
        : await showDialog<DiscoveredServer>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text(appText(context, 'Choose a server')),
              children: [
                for (final server in found)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(server),
                    child: Text('${server.name}  ${server.address}'),
                  ),
              ],
            ),
          );

    if (!mounted || chosen == null) {
      return;
    }

    _address.text = chosen.address;

    setState(() {
      _message = 'Found ${chosen.name} at ${chosen.address}. Press Save to use it.';
      _isError = false;
    });
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
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              onPressed: busy ? null : _find,
              label: Text(appText(context, 'Find server')),
            ),
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
  const ConnectScreen({
    super.key,
    this.tester = _defaultTester,
    this.finder = _defaultFinder,
  });

  final ConnectionTester tester;
  final ServerFinder finder;

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
                    finder: finder,
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

enum _Search { searching, found, same, none, hidden }

/// Shown under "No document open" when the saved server could not be
/// reached: looks for the server on the network by itself, once, and offers
/// to switch when it answers somewhere else. Nothing is switched or saved
/// until the user presses "Use it".
class ServerFinderPanel extends StatefulWidget {
  const ServerFinderPanel({
    super.key,
    this.finder = _defaultFinder,
    this.searchSupported = networkSearchAvailable,
  });

  final ServerFinder finder;
  final bool searchSupported;

  @override
  State<ServerFinderPanel> createState() => _ServerFinderPanelState();
}

class _ServerFinderPanelState extends State<ServerFinderPanel> {
  _Search _state = _Search.searching;
  List<DiscoveredServer> _found = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_search);
  }

  ConnectionScope? get _scope =>
      context.getInheritedWidgetOfExactType<ConnectionScope>();

  Future<void> _search() async {
    if (!widget.searchSupported) {
      return;
    }

    final current = _scope?.connection;

    if (current == null || current.token.isEmpty) {
      setState(() => _state = _Search.none);

      return;
    }

    setState(() => _state = _Search.searching);

    final found = await widget.finder(token: current.token);

    if (!mounted) {
      return;
    }

    final others = found.where((s) => s.address != current.address).toList();

    setState(() {
      _found = others;
      _state = others.isNotEmpty
          ? _Search.found
          : found.isNotEmpty
              ? _Search.same
              : _Search.none;
    });
  }

  Future<void> _use(DiscoveredServer server) async {
    final scope = _scope;
    final current = scope?.connection;

    if (scope == null || current == null) {
      return;
    }

    await scope.change(ServerConnection(address: server.address, token: current.token));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.searchSupported) {
      return const SizedBox.shrink();
    }

    switch (_state) {
      case _Search.hidden:
        return const SizedBox.shrink();
      case _Search.searching:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(appText(context, 'Looking for the server on this network...')),
          ],
        );
      case _Search.same:
        return Text(
          appText(context, 'The server answers at the saved address. Press Try again.'),
          textAlign: TextAlign.center,
        );
      case _Search.none:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appText(context, 'The server was not found on this network.'),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: _search,
              child: Text(appText(context, 'Find server')),
            ),
          ],
        );
      case _Search.found:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final server in _found)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${appText(context, 'Server found')}: ${server.name}  ${server.address}',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                    FilledButton(
                      onPressed: () => _use(server),
                      child: Text(appText(context, 'Use it')),
                    ),
                  ],
                ),
              ),
            TextButton(
              onPressed: () => setState(() => _state = _Search.hidden),
              child: Text(appText(context, 'Ignore')),
            ),
          ],
        );
    }
  }
}
