import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_text.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/live/live_channel.dart';
import '../../../core/live/live_coordinator.dart';
import '../../../core/preferences/app_preferences.dart';
import '../../../core/speech/speech_service_factory.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../../spreadsheet/services/spreadsheet_service.dart';
import '../dictation_controller.dart';
import '../startup_status.dart';
import '../widgets/app_menu_bar.dart';
import '../widgets/workspace.dart';
import '../widgets/status_bar.dart';
import '../widgets/toolbar.dart';
import '../widgets/search_bar.dart';
import '../widgets/sheet_tabs.dart';

/// The document opened automatically on first launch, before any
/// document has ever been successfully opened/created and recorded via
/// AppPreferences.setLastOpenedDocument.
const _defaultDocument = 'test.xlsx';

/// Owns the SpreadsheetController and ViewportController for the whole
/// shell. These used to be created privately inside SpreadsheetFeatureV2,
/// but Toolbar (a sibling of Workspace here, not a descendant of it) also
/// needs access to the same controller instances - it reads the current
/// selection and triggers insert/delete row/column operations. Lifting
/// ownership up here lets both widgets share the same controllers rather
/// than each having their own disconnected copy.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key, this.onLocaleChanged});

  final ValueChanged<Locale>? onLocaleChanged;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WidgetsBindingObserver {
  late final SpreadsheetController spreadsheetController;
  late final ViewportController viewportController;

  /// Speech to text (PC only; see DictationController).
  late final DictationController dictation;
  bool _listeningShown = false;
  bool _preparingSpeechShown = false;
  int _shownDictationNotice = 0;

  /// Whether the first document has been tried, and why there is none.
  final StartupStatus startup = StartupStatus();

  @override
  void initState() {
    super.initState();

    // The server's address (and optional access token) are build-time
    // settings - see ApiConfig - so this same code can talk to a server on
    // another machine.
    final api = ApiClient(
      baseUrl: ApiConfig.baseUrl,
      accessToken: ApiConfig.accessToken.isEmpty ? null : ApiConfig.accessToken,
      clientName: ApiConfig.clientName.isEmpty ? null : ApiConfig.clientName,
    );
    final service = SpreadsheetService(api);

    // Last-opened document and preferences are stored by the backend (see
    // AppPreferences for why the browser can't be relied on). Must be set
    // before _loadInitialDocument reads them.
    AppPreferences.useBackend(api);
    _loadInterfaceLanguage();

    spreadsheetController = SpreadsheetController(
      service,
      // Other people's changes to the open document arrive over a live
      // (WebSocket) connection; the controller starts it once a document
      // has been loaded.
      liveFactory: ({
        required reload,
        required onChanged,
        required onSessionLost,
        required applyBatch,
      }) =>
          LiveCoordinator(
        addressFor: (since) => api.liveUri(since: since),
        connect: WebSocketLiveChannel.new,
        reload: reload,
        onChanged: onChanged,
        onSessionLost: onSessionLost,
        applyBatch: applyBatch,
        onReloadFailed: (error) =>
            debugPrint('[Live] reload failed: $error'),
      ),
    );
    viewportController = ViewportController();

    dictation = DictationController(
      speech: createSpeechService(),
      spreadsheetController: spreadsheetController,
      viewportController: viewportController,
    );
    dictation.speechLanguageReady = false;
    _loadSpeechLanguage();
    dictation.addListener(_onDictationChanged);

    // Keep the viewport's valid row/column range in sync with whatever
    // sheet is currently active - this covers every path that can change
    // the grid's dimensions (row/column insert/delete, search, sheet
    // switch/add/delete) in one place, rather than duplicating a bounds
    // refresh into each feature that can trigger one. Individual features
    // (Toolbar, SpreadsheetGrid, the search bar) also call
    // setSheetBounds directly after their own mutations for immediate
    // feedback - setSheetBounds is a pure recompute, so the occasional
    // redundant call here is harmless.
    spreadsheetController.addListener(_syncViewportBounds);

    // Autosave waits a moment after the last change. If the app loses
    // focus or its tab is hidden/closed in that moment, save right away.
    WidgetsBinding.instance.addObserver(this);

    _loadInitialDocument();
  }

  Future<void> _loadSpeechLanguage() async {
    final revision = dictation.localeRevision;
    final language = await const AppPreferences().getSpeechLanguage();

    if (!mounted) {
      return;
    }

    if (dictation.localeRevision == revision) {
      dictation.localeId = language == 'system' ? 'auto' : language;
    }
    dictation.speechLanguageReady = true;
  }

  Future<void> _loadInterfaceLanguage() async {
    final language = await const AppPreferences().getInterfaceLanguage();

    if (mounted) {
      widget.onLocaleChanged?.call(Locale(language));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(spreadsheetController.flushPendingChanges());
    }
  }

  /// Opens the last document the user had open (recorded whenever
  /// loadDocument succeeds), or falls back to _defaultDocument if none
  /// is recorded yet (first run) or the remembered one can no longer be
  /// opened (e.g. it was deleted/moved since). The fallback itself is
  /// still surfaced to the user via loadDocument's normal error path if
  /// IT also fails - this only guards the one retry, not indefinitely.
  Future<void> _loadInitialDocument() async {
    startup.begin();

    final lastOpened = await const AppPreferences().getLastOpenedDocument();

    if (!mounted) return;

    final target = lastOpened ?? _defaultDocument;

    try {
      await spreadsheetController.loadDocument(target);
    } catch (_) {
      // The remembered document may no longer exist. Only retry with
      // the default if we weren't already trying it - otherwise this
      // would silently mask a real failure to open the default itself.
      if (target != _defaultDocument) {
        try {
          await spreadsheetController.loadDocument(_defaultDocument);
        } catch (_) {
          // Swallow here too - there's genuinely no document available
          // to show, and loadDocument already logs its own failures.
          // The grid's own "no document loaded" empty state (a loading
          // spinner, per SpreadsheetGrid.build) covers the UI.
        }
      }
    }

    if (mounted) {
      _syncViewportBounds();

      startup.finish(
        problem: spreadsheetController.hasDocument
            ? null
            : appText(
                context,
                'Could not open a document. Check that the server is running and that this device can reach it.',
              ),
      );
    }
  }

  void _syncViewportBounds() {
    if (spreadsheetController.hasDocument) {
      startup.clearProblem();
    }

    final spreadsheet = spreadsheetController.spreadsheet;
    if (spreadsheet == null) {
      return;
    }
    viewportController.setSheetBounds(
      rowCount: spreadsheet.activeSheet.rows.length,
      columnCount: spreadsheet.activeSheet.headers.length,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    spreadsheetController.removeListener(_syncViewportBounds);
    spreadsheetController.dispose();
    dictation.removeListener(_onDictationChanged);
    dictation.dispose();
    viewportController.dispose();
    startup.dispose();
    super.dispose();
  }

  /// Tells the user what speech to text is doing: a notice while it is
  /// listening, and one message for every outcome.
  void _onDictationChanged() {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    if (dictation.state == DictationState.starting) {
      if (!_preparingSpeechShown) {
        _preparingSpeechShown = true;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              appText(
                context,
                'Preparing offline speech recognition. First use downloads a roughly 460 MB model; audio stays on this device.',
              ),
            ),
            duration: const Duration(days: 1),
          ),
        );
      }

      return;
    }

    if (dictation.isListening) {
      if (!_listeningShown) {
        _listeningShown = true;
        _preparingSpeechShown = false;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              appText(
                context,
                dictation.isSearchCapture
                    ? 'Listening... say what to search for. Press Ctrl+Shift+M to stop.'
                    : 'Listening... say what the cell should contain. Press Ctrl+Shift+M to stop.',
              ),
            ),
            duration: Duration(days: 1),
          ),
        );
      }

      return;
    }

    if (_listeningShown || _preparingSpeechShown) {
      _listeningShown = false;
      _preparingSpeechShown = false;
      messenger.hideCurrentSnackBar();
    }

    final message = dictation.message;

    if (message != null && dictation.messageSerial != _shownDictationNotice) {
      _shownDictationNotice = dictation.messageSerial;
      messenger.showSnackBar(
        SnackBar(content: Text(appText(context, message))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DictationShortcut(
      dictation: dictation,
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppMenuBar(
              spreadsheetController: spreadsheetController,
              dictation: dictation,
            ),
            Toolbar(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
              dictation: dictation,
              onLocaleChanged: widget.onLocaleChanged,
            ),
            SpreadsheetSearchBar(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
              dictation: dictation,
            ),
            Workspace(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
              startup: startup,
              onRetry: _loadInitialDocument,
            ),
            SheetTabs(spreadsheetController: spreadsheetController),
            StatusBar(
              spreadsheetController: spreadsheetController,
              viewportController: viewportController,
            ),
          ],
        ),
      ),
    );
  }
}