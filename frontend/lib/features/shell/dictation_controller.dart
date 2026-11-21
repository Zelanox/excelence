import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/speech/speech_service.dart';
import '../spreadsheet/controllers/spreadsheet_controller.dart';
import '../spreadsheet/controllers/viewport_controller.dart';

enum DictationState { idle, starting, listening }

typedef SpeechCaptureResult = void Function(String text, bool isFinal);

/// Speech to text for the selected cell (an accessibility feature, PC only).
///
/// Start it, say what the cell should contain, and the text appears in the
/// cell's editor - the same state as typing - so it can be corrected and
/// then kept with Enter or discarded with Esc. Nothing is saved without
/// that step.
///
/// While a cell is already being edited it declines and says so; Windows'
/// own voice typing (Win+H) works inside the editor.
class DictationController extends ChangeNotifier {
  DictationController({
    required this.speech,
    required this.spreadsheetController,
    required this.viewportController,
    this.stopGrace = const Duration(milliseconds: 1500),
    String? localeId,
  }) : _localeId = localeId;

  final SpeechService speech;
  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;
  String? _localeId;
  int _localeRevision = 0;

  String? get localeId => _localeId;

  set localeId(String? value) {
    _localeId = value;
    _localeRevision++;
  }

  int get localeRevision => _localeRevision;

  /// How long to wait for the final result after asking the engine to stop.
  final Duration stopGrace;

  static const notSupported = 'Speech to text is not available on this device.';
  static const needsDocument = 'Open a document first.';
  static const finishEditing =
      'Finish editing the cell first (Enter or Esc), then start speech to '
      'text. To dictate while typing in a cell, use Windows voice typing '
      '(Win+H).';
  static const heardNothing = "I didn't hear anything. Try again.";
  static const modelUnavailable =
      'The offline speech model could not be downloaded or loaded. Check your '
      'internet connection on first use and available disk space, then try '
      'again.';
  static const transcriptionFailed =
      'Could not transcribe the audio. Try again.';
  static const speechSettingsLoading =
      'Speech settings are still loading. Please try again in a moment.';
  static const unavailable =
      'Speech to text could not start. Check that a microphone is connected '
      'and that speech recognition is allowed in your system settings.';
  static const permissionDenied =
      'Microphone access is blocked. Allow it in your system settings, '
      'then try again.';
  static const stoppedUnexpectedly =
      'Speech to text stopped unexpectedly. Try again.';
  static const placed =
      'The text is in the cell. Press Enter to keep it, or Esc to discard it.';

  DictationState _state = DictationState.idle;
  String _heard = '';
  String? _message;
  int _messageSerial = 0;
  Timer? _stopTimer;
  bool _disposed = false;
  SpeechCaptureResult? _searchResultListener;
  bool _speechLanguageReady = true;

  DictationState get state => _state;
  bool get isListening => _state == DictationState.listening;
  bool get isBusy => _state != DictationState.idle;
  bool get isSupported => speech.isSupported;
  bool get isSearchCapture => _searchResultListener != null;
  bool get speechLanguageReady => _speechLanguageReady;

  set speechLanguageReady(bool value) {
    _speechLanguageReady = value;
    _changed();
  }

  /// The text heard so far in the current session.
  String get heard => _heard;

  /// The latest notice for the user (null before the first one).
  String? get message => _message;

  /// Increases with every notice, so the screen can show each exactly once.
  int get messageSerial => _messageSerial;

  bool get canStart =>
      isSupported &&
      speechLanguageReady &&
      spreadsheetController.hasDocument &&
      !isBusy;

  void _notice(String text) {
    _message = text;
    _messageSerial++;
    _changed();
  }

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Starts when idle, stops when listening; ignored while starting.
  Future<void> toggle() async {
    if (_state == DictationState.listening) {
      await stop();
    } else if (_state == DictationState.idle) {
      await start();
    }
  }

  Future<void> start() async {
    if (_state != DictationState.idle) {
      return;
    }

    _searchResultListener = null;
    await _start();
  }

  /// Captures speech for a search field instead of inserting it into a cell.
  Future<void> startForSearch(SpeechCaptureResult onResult) async {
    if (_state != DictationState.idle) {
      return;
    }

    _searchResultListener = onResult;
    await _start();
  }

  Future<void> _start() async {
    final isSearchCapture = _searchResultListener != null;

    if (!speechLanguageReady) {
      _searchResultListener = null;
      _notice(speechSettingsLoading);
      return;
    }

    if (!speech.isSupported) {
      _searchResultListener = null;
      _notice(notSupported);
      return;
    }

    if (!spreadsheetController.hasDocument) {
      _searchResultListener = null;
      _notice(needsDocument);
      return;
    }

    if (!isSearchCapture && viewportController.isEditing) {
      _searchResultListener = null;
      _notice(finishEditing);
      return;
    }

    _state = DictationState.starting;
    _heard = '';
    _message = null;
    _changed();

    final result = await speech.start(
      onResult: _onResult,
      onError: _onError,
      onEnded: _onEnded,
      localeId: localeId,
    );

    if (!result.ok) {
      _searchResultListener = null;
      _state = DictationState.idle;
      _notice(_messageFor(result.problem ?? SpeechProblem.unavailable));
      return;
    }

    if (_state == DictationState.starting) {
      _state = DictationState.listening;
      _changed();
    }
  }

  /// Asks the engine to finish; whatever was heard is then placed in the
  /// cell. If the engine never answers, what was heard so far is used.
  Future<void> stop() async {
    if (_state != DictationState.listening) {
      return;
    }

    await speech.stop();

    if (_state == DictationState.listening) {
      _stopTimer?.cancel();
      _stopTimer = Timer(stopGrace, () {
        if (_state != DictationState.idle) {
          _finish();
        }
      });
    }
  }

  void _onResult(String text, bool isFinal) {
    if (_state == DictationState.idle) {
      return;
    }

    _heard = text;
    _searchResultListener?.call(text, isFinal);

    if (isFinal) {
      _finish();
    } else {
      _changed();
    }
  }

  void _onEnded() {
    if (_state == DictationState.listening) {
      _finish();
    }
  }

  void _onError(SpeechProblem problem) {
    if (_state == DictationState.idle) {
      return;
    }

    if (problem == SpeechProblem.noSpeech && _heard.trim().isNotEmpty) {
      _finish();
      return;
    }

    _stopTimer?.cancel();
    _searchResultListener = null;
    _state = DictationState.idle;
    _heard = '';
    _notice(_messageFor(problem));
  }

  String _messageFor(SpeechProblem problem) {
    switch (problem) {
      case SpeechProblem.unavailable:
        return unavailable;
      case SpeechProblem.permissionDenied:
        return permissionDenied;
      case SpeechProblem.noSpeech:
        return heardNothing;
      case SpeechProblem.modelUnavailable:
        return modelUnavailable;
      case SpeechProblem.transcriptionFailed:
        return transcriptionFailed;
      case SpeechProblem.other:
        return stoppedUnexpectedly;
    }
  }

  /// Ends the session and puts what was heard into the cell's editor.
  void _finish() {
    _stopTimer?.cancel();

    final text = _heard.trim();
    final isSearchCapture = _searchResultListener != null;
    _searchResultListener = null;

    _state = DictationState.idle;
    _heard = '';

    if (text.isEmpty) {
      _notice(heardNothing);
      return;
    }

    if (isSearchCapture) {
      _changed();
      return;
    }

    if (viewportController.isEditing) {
      // The user started typing meanwhile; do not replace their work.
      _notice(
        'Heard "$text", but a cell is being edited, so it was not '
        'inserted.',
      );
      return;
    }

    viewportController.startEditing(
      replaceInitialValue: true,
      initialValue: text,
    );

    _notice(placed);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _stopTimer?.cancel();
    _searchResultListener = null;
    unawaited(speech.dispose());

    super.dispose();
  }
}

/// The key that starts and stops speech to text on a PC.
const dictationShortcut = SingleActivator(
  LogicalKeyboardKey.keyM,
  control: true,
  shift: true,
);

/// Makes Ctrl+Shift+M start / stop speech to text anywhere below it (when
/// the key is not used by whatever has focus).
class DictationShortcut extends StatelessWidget {
  const DictationShortcut({
    super.key,
    required this.dictation,
    required this.child,
  });

  final DictationController dictation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        dictationShortcut: () {
          unawaited(dictation.toggle());
        },
      },
      child: child,
    );
  }
}
