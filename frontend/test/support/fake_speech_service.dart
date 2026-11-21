import 'dart:async';

import 'package:frontend/core/speech/speech_service.dart';

/// A scripted speech engine: the test decides what is "heard" and when
/// listening ends.
class FakeSpeechService implements SpeechService {
  FakeSpeechService({this.supported = true});

  final bool supported;

  final List<String> calls = [];
  String? lastLocaleId;

  SpeechStartResult startResult = const SpeechStartResult.ok();

  /// When true (the default) stop() ends listening at once, like a real
  /// engine that answers promptly.
  bool endOnStop = true;

  /// When set, start() waits for it.
  Completer<void>? startGate;

  void Function(String text, bool isFinal)? _onResult;
  void Function(SpeechProblem problem)? _onError;
  void Function()? _onEnded;

  @override
  bool get isSupported => supported;

  @override
  Future<SpeechStartResult> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechProblem problem) onError,
    required void Function() onEnded,
    String? localeId,
  }) async {
    calls.add('start');
    lastLocaleId = localeId;
    _onResult = onResult;
    _onError = onError;
    _onEnded = onEnded;

    await startGate?.future;

    return startResult;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');

    if (endOnStop) {
      _onEnded?.call();
    }
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
  }

  @override
  Future<void> dispose() async {
    await cancel();
  }

  // What the "engine" does on its own:
  void say(String text, {bool isFinal = false}) =>
      _onResult?.call(text, isFinal);
  void fail(SpeechProblem problem) => _onError?.call(problem);
  void end() => _onEnded?.call();
}
