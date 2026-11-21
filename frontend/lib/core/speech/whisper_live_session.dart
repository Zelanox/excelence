import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart'
    show WhisperLiveSession, startWhisperLiveSession;

abstract interface class SpeechWhisperLiveSession {
  Stream<String> get partials;

  void feed(Uint8List pcm16Bytes);

  Future<String> stop();
}

class _PackageSpeechWhisperLiveSession implements SpeechWhisperLiveSession {
  _PackageSpeechWhisperLiveSession(this._session);

  final WhisperLiveSession _session;

  @override
  Stream<String> get partials => _session.partials;

  @override
  void feed(Uint8List pcm16Bytes) => _session.feed(pcm16Bytes);

  @override
  Future<String> stop() => _session.stop();
}

Future<SpeechWhisperLiveSession> startSpeechWhisperLiveSession({
  required String modelPath,
  required String language,
  required bool keepModelLoaded,
}) async {
  if (Platform.isWindows) {
    return _startWindowsWhisperLiveSession(
      modelPath: modelPath,
      language: language,
      keepModelLoaded: keepModelLoaded,
    );
  }

  final session = await startWhisperLiveSession(
    modelPath: modelPath,
    lang: language,
    keepModelLoaded: keepModelLoaded,
  );
  return _PackageSpeechWhisperLiveSession(session);
}

typedef _StreamStartNative = Pointer<Utf8> Function(Pointer<Utf8> body);
typedef _StreamFeedNative =
    Pointer<Utf8> Function(Pointer<Float> pcm, Int32 nSamples);
typedef _StreamFeedDart =
    Pointer<Utf8> Function(Pointer<Float> pcm, int nSamples);
typedef _StreamStopNative = Pointer<Utf8> Function();
typedef _NativeFree = Void Function(Pointer<Void> pointer);
typedef _NativeFreeDart = void Function(Pointer<Void> pointer);

/// Windows bridge adapted from whisper_ggml 2.10.0's live protocol.
/// Its MIT license is retained in frontend/LICENSES/whisper_ggml.MIT.
Future<SpeechWhisperLiveSession> _startWindowsWhisperLiveSession({
  required String modelPath,
  required String language,
  required bool keepModelLoaded,
}) async {
  final fromWorker = ReceivePort();
  final ready = Completer<SendPort>();
  final started = Completer<void>();
  final partials = StreamController<String>();
  final finalText = Completer<String>();

  final worker = await Isolate.spawn<List<Object?>>(_windowsWhisperWorker, [
    fromWorker.sendPort,
    kDebugMode ? 'ucrtbased.dll' : 'ucrtbase.dll',
  ]);

  var lastText = '';
  late final _WindowsSpeechWhisperLiveSession session;

  fromWorker.listen((dynamic message) {
    final List<dynamic> event = message as List<dynamic>;
    switch (event[0] as String) {
      case 'ready':
        if (!ready.isCompleted) {
          ready.complete(event[1] as SendPort);
        }
      case 'bootstrapError':
        final error = StateError(event[1] as String);
        if (!ready.isCompleted) {
          ready.completeError(error);
        }
      case 'started':
        if (!started.isCompleted) {
          started.complete();
        }
      case 'partial':
        lastText = event[1] as String;
        if (!partials.isClosed) {
          partials.add(lastText);
        }
      case 'final':
        if (!partials.isClosed) {
          partials.close();
        }
        if (!finalText.isCompleted) {
          finalText.complete(event[1] as String);
        }
        fromWorker.close();
        worker.kill();
      case 'error':
        final error = StateError(event[1] as String);
        if (!started.isCompleted) {
          started.completeError(error);
        } else if (!finalText.isCompleted) {
          if (!partials.isClosed) {
            partials
              ..addError(error)
              ..close();
          }
          finalText.complete(lastText);
          fromWorker.close();
          worker.kill();
        }
    }
  });

  late final SendPort toWorker;
  try {
    toWorker = await ready.future;
  } catch (_) {
    worker.kill(priority: Isolate.immediate);
    fromWorker.close();
    await partials.close();
    rethrow;
  }

  session = _WindowsSpeechWhisperLiveSession(
    toWorker: toWorker,
    partials: partials,
    finalText: finalText,
  );
  toWorker.send([
    'start',
    jsonEncode({
      'model': modelPath,
      'language': language,
      'threads': 4,
      'is_translate': false,
      'keep_model_loaded': keepModelLoaded,
    }),
  ]);

  try {
    await started.future;
  } catch (_) {
    worker.kill(priority: Isolate.immediate);
    fromWorker.close();
    await partials.close();
    rethrow;
  }
  return session;
}

class _WindowsSpeechWhisperLiveSession implements SpeechWhisperLiveSession {
  _WindowsSpeechWhisperLiveSession({
    required this._toWorker,
    required this._partials,
    required this._finalText,
  });

  final SendPort _toWorker;
  final StreamController<String> _partials;
  final Completer<String> _finalText;
  bool _stopped = false;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  void feed(Uint8List pcm16Bytes) {
    if (!_stopped) {
      _toWorker.send(['feed', pcm16Bytes]);
    }
  }

  @override
  Future<String> stop() {
    if (!_stopped) {
      _stopped = true;
      _toWorker.send(const ['stop']);
    }
    return _finalText.future;
  }
}

void _windowsWhisperWorker(List<Object?> config) {
  final toMain = config[0] as SendPort;
  final crtLibrary = config[1] as String;

  late final DynamicLibrary whisperLibrary;
  late final _NativeFreeDart freeNativeResponse;
  late final Pointer<NativeFunction<_StreamStartNative>> startPointer;
  late final Pointer<NativeFunction<_StreamFeedNative>> feedPointer;
  late final Pointer<NativeFunction<_StreamStopNative>> stopPointer;
  try {
    whisperLibrary = DynamicLibrary.open('whisper_ggml.dll');
    final crt = DynamicLibrary.open(crtLibrary);
    // The DLL returns strings allocated by the CRT; ffi.malloc.free uses
    // CoTaskMemFree on Windows and must not free these pointers.
    freeNativeResponse = crt.lookupFunction<_NativeFree, _NativeFreeDart>(
      'free',
    );
    startPointer = whisperLibrary.lookup('stream_start');
    feedPointer = whisperLibrary.lookup('stream_feed');
    stopPointer = whisperLibrary.lookup('stream_stop');
  } catch (error) {
    toMain.send(['bootstrapError', error.toString()]);
    return;
  }

  final start = startPointer.asFunction<_StreamStartNative>();
  final feed = feedPointer.asFunction<_StreamFeedDart>();
  final stop = stopPointer.asFunction<_StreamStopNative>();
  final inbox = ReceivePort();
  toMain.send(['ready', inbox.sendPort]);

  String lastText = '';
  var pendingByte = -1;

  Map<String, dynamic> parseResponse(Pointer<Utf8> response) {
    if (response.address == 0) {
      throw StateError('Whisper returned an empty native response.');
    }

    try {
      final decoded = jsonDecode(response.toDartString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Whisper returned invalid JSON.');
      }
      return decoded;
    } finally {
      freeNativeResponse(response.cast<Void>());
    }
  }

  inbox.listen((dynamic message) {
    final List<dynamic> event = message as List<dynamic>;
    try {
      switch (event[0] as String) {
        case 'start':
          final body = (event[1] as String).toNativeUtf8();
          late final Map<String, dynamic> result;
          try {
            result = parseResponse(start(body));
          } finally {
            malloc.free(body);
          }
          if (result['@type'] == 'error') {
            toMain.send(['error', result['message'] as String]);
          } else {
            toMain.send(const ['started']);
          }
        case 'feed':
          var bytes = event[1] as Uint8List;
          if (pendingByte >= 0 ||
              bytes.offsetInBytes.isOdd ||
              bytes.length.isOdd) {
            final merged = Uint8List(bytes.length + (pendingByte >= 0 ? 1 : 0));
            var offset = 0;
            if (pendingByte >= 0) {
              merged[offset++] = pendingByte;
            }
            merged.setRange(offset, offset + bytes.length, bytes);
            if (merged.length.isOdd) {
              pendingByte = merged.last;
              bytes = Uint8List.sublistView(merged, 0, merged.length - 1);
            } else {
              pendingByte = -1;
              bytes = merged;
            }
          }
          if (bytes.isEmpty) {
            return;
          }

          final samples = bytes.buffer.asInt16List(
            bytes.offsetInBytes,
            bytes.length ~/ 2,
          );
          final pcm = malloc.allocate<Float>(samples.length * sizeOf<Float>());
          try {
            final output = pcm.asTypedList(samples.length);
            for (var index = 0; index < samples.length; index++) {
              output[index] = samples[index] / 32768.0;
            }
            final result = parseResponse(feed(pcm, samples.length));
            if (result['@type'] == 'error') {
              toMain.send(['error', result['message'] as String]);
            } else {
              final text = result['text'] as String? ?? '';
              if (text != lastText) {
                lastText = text;
                toMain.send(['partial', text]);
              }
            }
          } finally {
            malloc.free(pcm);
          }
        case 'stop':
          final result = parseResponse(stop());
          final text = result['@type'] == 'error'
              ? lastText
              : result['text'] as String;
          toMain.send(['final', text]);
          inbox.close();
      }
    } catch (error) {
      toMain.send(['error', error.toString()]);
    }
  });
}
