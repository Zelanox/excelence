import 'speech_service.dart';

SpeechService createSpeechService() => _UnsupportedSpeechService();

class _UnsupportedSpeechService implements SpeechService {
  @override
  bool get isSupported => false;

  @override
  Future<SpeechStartResult> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechProblem problem) onError,
    required void Function() onEnded,
    String? localeId,
  }) async =>
      const SpeechStartResult.failed(SpeechProblem.unavailable);

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
