import 'speech_service.dart';
import 'unsupported_speech_service.dart'
    if (dart.library.io) 'offline_whisper_speech_service.dart' as platform;

SpeechService createSpeechService() => platform.createSpeechService();
