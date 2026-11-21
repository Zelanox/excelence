import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/speech/offline_whisper_speech_service.dart';

void main() {
  test('Whisper defaults to Arabic but keeps explicit language detection', () {
    expect(OfflineWhisperSpeechService.languageCodeFor(null), 'ar');
    expect(OfflineWhisperSpeechService.languageCodeFor('ar_SA'), 'ar');
    expect(OfflineWhisperSpeechService.languageCodeFor('en_US'), 'en');
    expect(OfflineWhisperSpeechService.languageCodeFor('auto'), 'auto');
  });
}
