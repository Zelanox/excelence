/// Why speech recognition could not start or stopped.
enum SpeechProblem {
  /// No recognizer, no microphone, or access was refused.
  unavailable,

  /// The system says microphone access is blocked.
  permissionDenied,

  /// Nothing was heard.
  noSpeech,

  /// The offline model could not be downloaded or loaded.
  modelUnavailable,

  /// The transcription engine could not process the audio.
  transcriptionFailed,

  /// Anything else.
  other,
}

/// The answer to "can you start listening?".
class SpeechStartResult {
  const SpeechStartResult.ok()
      : ok = true,
        problem = null;

  const SpeechStartResult.failed(SpeechProblem this.problem) : ok = false;

  final bool ok;
  final SpeechProblem? problem;
}

/// Speech recognition, as far as the app cares. The real engine lives behind
/// this interface so the rest of the app and its tests never depend on the
/// platform speech plugins.
abstract class SpeechService {
  /// Whether this platform offers it at all. Phones are left out on purpose:
  /// their keyboards already have dictation.
  bool get isSupported;

  /// Starts listening. [onResult] gets the text heard so far (and whether
  /// it is final), [onError] a problem while listening, [onEnded] the end of
  /// listening for any reason.
  Future<SpeechStartResult> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechProblem problem) onError,
    required void Function() onEnded,
    String? localeId,
  });

  /// Stops listening and asks for the final result (which still arrives
  /// through the callbacks given to [start]).
  Future<void> stop();

  /// Stops listening and drops what was heard.
  Future<void> cancel();

  /// Releases resources owned by the speech engine.
  Future<void> dispose() async {}
}
