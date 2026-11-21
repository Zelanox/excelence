import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'speech_service.dart';
import 'whisper_live_session.dart';

SpeechService createSpeechService() => OfflineWhisperSpeechService();

class OfflineWhisperSpeechService implements SpeechService {
  OfflineWhisperSpeechService()
    : _recorder = AudioRecorder(),
      _whisper = WhisperController();

  static const _model = WhisperModel.small;
  final AudioRecorder _recorder;
  final WhisperController _whisper;

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<String>? _partialSubscription;
  SpeechWhisperLiveSession? _session;
  bool _isStarting = false;
  bool _recorderStartAttempted = false;
  bool _isRecording = false;
  bool _isEnding = false;
  int _generation = 0;
  Future<void>? _stopOperation;

  void Function(String text, bool isFinal)? _onResult;
  void Function(SpeechProblem problem)? _onError;
  void Function()? _onEnded;

  @override
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<SpeechStartResult> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechProblem problem) onError,
    required void Function() onEnded,
    String? localeId,
  }) async {
    if (_isStarting || _isRecording || _isEnding || _session != null) {
      return const SpeechStartResult.failed(SpeechProblem.other);
    }

    final generation = ++_generation;
    _isStarting = true;
    _onResult = onResult;
    _onError = onError;
    _onEnded = onEnded;

    var failureProblem = SpeechProblem.unavailable;

    try {
      if (!await _recorder.hasPermission()) {
        _clearCallbacks();
        return const SpeechStartResult.failed(SpeechProblem.permissionDenied);
      }

      failureProblem = SpeechProblem.modelUnavailable;
      final modelPath = await _ensureModel();
      if (!_isCurrent(generation)) {
        return const SpeechStartResult.failed(SpeechProblem.other);
      }

      final session = await startSpeechWhisperLiveSession(
        modelPath: modelPath,
        language: languageCodeFor(localeId),
        keepModelLoaded: !Platform.isWindows,
      );
      if (!_isCurrent(generation)) {
        await session.stop();
        return const SpeechStartResult.failed(SpeechProblem.other);
      }
      _session = session;
      _partialSubscription = session.partials.listen(
        (text) => _onPartial(generation, text),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            '[OfflineWhisperSpeechService] Whisper stream failed: $error',
          );
          unawaited(_finishWithError(generation));
        },
      );

      failureProblem = SpeechProblem.unavailable;
      _recorderStartAttempted = true;
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      if (!_isCurrent(generation)) {
        await _cleanupActive(cancelRecorder: true);
        return const SpeechStartResult.failed(SpeechProblem.other);
      }

      _recorderStartAttempted = false;
      _isRecording = true;
      _audioSubscription = audioStream.listen(
        _feedAudio,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            '[OfflineWhisperSpeechService] microphone stream failed: $error',
          );
          unawaited(_finishWithError(generation));
        },
      );

      return const SpeechStartResult.ok();
    } catch (error, stackTrace) {
      debugPrint(
        '[OfflineWhisperSpeechService] could not start speech: $error\n'
        '$stackTrace',
      );
      if (!_isCurrent(generation)) {
        return const SpeechStartResult.failed(SpeechProblem.other);
      }

      await _cleanupActive(cancelRecorder: _recorderStartAttempted);
      _clearCallbacks();
      return SpeechStartResult.failed(
        error.toString().toLowerCase().contains('permission')
            ? SpeechProblem.permissionDenied
            : failureProblem,
      );
    } finally {
      if (_isCurrent(generation)) {
        _isStarting = false;
      }
    }
  }

  Future<String> _ensureModel() async {
    final path = await _whisper.getPath(_model);
    final modelFile = File(path);
    if (await modelFile.exists()) {
      return path;
    }

    await modelFile.parent.create(recursive: true);
    final partialFile = File('$path.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await client.getUrl(_model.modelUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Model download returned HTTP ${response.statusCode}.',
          uri: _model.modelUri,
        );
      }

      var receivedBytes = 0;
      final sink = partialFile.openWrite();
      try {
        await for (final chunk in response) {
          receivedBytes += chunk.length;
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (receivedBytes == 0 ||
          (response.contentLength >= 0 &&
              receivedBytes != response.contentLength)) {
        throw const FormatException(
          'The downloaded speech model is incomplete.',
        );
      }

      await partialFile.rename(path);
      return path;
    } catch (_) {
      if (await partialFile.exists()) {
        try {
          await partialFile.delete();
        } catch (error) {
          debugPrint(
            '[OfflineWhisperSpeechService] could not remove partial model: '
            '$error',
          );
        }
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  static String languageCodeFor(String? localeId) {
    if (localeId == null || localeId.trim().isEmpty) {
      return 'ar';
    }

    final code = localeId.replaceAll('_', '-').split('-').first.toLowerCase();
    if (code == 'auto') {
      return 'auto';
    }
    return RegExp(r'^[a-z]{2,3}$').hasMatch(code) ? code : 'ar';
  }

  void _feedAudio(Uint8List chunk) {
    _session?.feed(chunk);
  }

  void _onPartial(int generation, String text) {
    if (!_isCurrent(generation) || !_isRecording) {
      return;
    }
    _onResult?.call(text, false);
  }

  bool _isCurrent(int generation) => generation == _generation;

  @override
  Future<void> stop() {
    final activeStop = _stopOperation;
    if (activeStop != null) {
      return activeStop;
    }
    if (!_isRecording) {
      return Future<void>.value();
    }

    final generation = _generation;
    final operation = _stopAndFinish(generation);
    _stopOperation = operation;
    return operation.whenComplete(() {
      if (identical(_stopOperation, operation)) {
        _stopOperation = null;
      }
    });
  }

  Future<void> _stopAndFinish(int generation) async {
    try {
      await _recorder.stop();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isRecording = false;

      if (!_isCurrent(generation)) {
        return;
      }

      final session = _session;
      _session = null;
      await _partialSubscription?.cancel();
      _partialSubscription = null;

      final text = await session?.stop() ?? '';
      if (!_isCurrent(generation)) {
        return;
      }

      final result = _onResult;
      final error = _onError;
      final ended = _onEnded;
      _clearCallbacks();

      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        error?.call(SpeechProblem.noSpeech);
      } else {
        result?.call(trimmed, true);
      }
      ended?.call();
    } catch (error, stackTrace) {
      debugPrint(
        '[OfflineWhisperSpeechService] could not finish transcription: '
        '$error\n$stackTrace',
      );
      if (_isCurrent(generation)) {
        await _cleanupActive();
        _reportError(SpeechProblem.transcriptionFailed);
      }
    }
  }

  Future<void> _finishWithError(int generation) async {
    if (!_isCurrent(generation) || _isEnding) {
      return;
    }

    _isEnding = true;
    try {
      await _cleanupActive(cancelRecorder: true);
      if (_isCurrent(generation)) {
        _reportError(SpeechProblem.transcriptionFailed);
      }
    } finally {
      _isEnding = false;
    }
  }

  Future<void> _cleanupActive({bool cancelRecorder = false}) async {
    final shouldCancelRecorder =
        cancelRecorder || _isRecording || _recorderStartAttempted;
    _isRecording = false;
    _isStarting = false;
    _recorderStartAttempted = false;

    if (shouldCancelRecorder) {
      try {
        await _recorder.cancel();
      } catch (error) {
        debugPrint(
          '[OfflineWhisperSpeechService] could not cancel recording: $error',
        );
      }
    }

    final audioSubscription = _audioSubscription;
    _audioSubscription = null;
    try {
      await audioSubscription?.cancel();
    } catch (error) {
      debugPrint(
        '[OfflineWhisperSpeechService] could not close microphone stream: '
        '$error',
      );
    }

    final partialSubscription = _partialSubscription;
    _partialSubscription = null;
    try {
      await partialSubscription?.cancel();
    } catch (error) {
      debugPrint(
        '[OfflineWhisperSpeechService] could not close Whisper stream: $error',
      );
    }

    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.stop();
      } catch (error) {
        debugPrint(
          '[OfflineWhisperSpeechService] could not stop Whisper session: '
          '$error',
        );
      }
    }
  }

  void _reportError(SpeechProblem problem) {
    final error = _onError;
    final ended = _onEnded;
    _clearCallbacks();
    error?.call(problem);
    ended?.call();
  }

  void _clearCallbacks() {
    _onResult = null;
    _onError = null;
    _onEnded = null;
  }

  @override
  Future<void> cancel() async {
    final recorderWasStarting = _recorderStartAttempted;
    _generation++;
    await _cleanupActive(cancelRecorder: recorderWasStarting);
    _clearCallbacks();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
    if (!Platform.isWindows) {
      await _whisper.releaseModel();
    }
  }
}
