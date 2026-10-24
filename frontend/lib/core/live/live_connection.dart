import 'dart:async';
import 'dart:convert';

import 'live_channel.dart';
import 'live_messages.dart';

enum LiveState {
  /// Not started, or stopped by the app.
  idle,

  /// Opening a connection.
  connecting,

  /// The server accepted the connection and has started talking.
  connected,

  /// The connection was lost; waiting before trying again.
  waiting,

  /// Stopped for good because the server refused or replaced this client
  /// (see [LiveConnection.stopReason]).
  stopped,
}

enum LiveStopReason {
  /// Close code 1008: bad parameters, the document is not open on the
  /// server, or a wrong/missing access token. Retrying cannot help; the
  /// document has to be opened again (or the token fixed).
  refused,

  /// Close code 4001: another connection with this client's id took over.
  /// Reconnecting would only make the two replace each other.
  replaced,
}

/// What to do when the server closes the connection with [code].
LiveStopReason? stopReasonForCloseCode(int? code) {
  switch (code) {
    case 1008:
      return LiveStopReason.refused;
    case 4001:
      return LiveStopReason.replaced;
    default:
      return null;      // 1012, 1013, 1011, 1000, 1006, unknown...: reconnect
  }
}

/// How long to wait before reconnect attempt number [attempt] (0 is the
/// first): 1, 2, 4, 8, then 15 seconds.
Duration backoffFor(int attempt) {
  final seconds = 1 << (attempt > 4 ? 4 : attempt);

  return Duration(seconds: seconds > 15 ? 15 : seconds);
}

Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

/// The client's live connection to one document: opens it, keeps it alive
/// with a ping, and reconnects (asking for what it missed) when it drops.
///
/// Everything the server says arrives on [messages]; [state] says whether
/// the connection is up. The window between connections is covered by the
/// server's catch-up: each (re)connection asks from [sinceProvider]'s
/// revision.
class LiveConnection {
  LiveConnection({
    required this.addressFor,
    required this.sinceProvider,
    required ChannelFactory connect,
    this.pingInterval = const Duration(seconds: 30),
    Future<void> Function(Duration) delay = _realDelay,
  })  : _connect = connect,
        _delay = delay;

  /// The address to connect to, given the revision to catch up from.
  final Uri Function(int since) addressFor;

  /// The newest revision the client has applied, asked at every (re)connect.
  final int Function() sinceProvider;

  /// How often to ping. The server forgets clients idle for 120 seconds.
  final Duration pingInterval;

  final ChannelFactory _connect;
  final Future<void> Function(Duration) _delay;

  final StreamController<LiveMessage> _messages =
      StreamController<LiveMessage>.broadcast();
  final StreamController<LiveState> _states =
      StreamController<LiveState>.broadcast();

  LiveState _state = LiveState.idle;
  LiveStopReason? _stopReason;
  LiveChannel? _channel;
  Completer<int?>? _finished;
  int _generation = 0;
  bool _disposed = false;

  Stream<LiveMessage> get messages => _messages.stream;

  Stream<LiveState> get states => _states.stream;

  LiveState get state => _state;

  /// Why the connection stopped for good, or null.
  LiveStopReason? get stopReason => _stopReason;

  /// Opens the connection and keeps it open until [stop].
  void start() {
    final canStart = _state == LiveState.idle || _state == LiveState.stopped;

    if (_disposed || !canStart) {
      return;
    }

    _stopReason = null;
    _generation++;
    unawaited(_run(_generation));
  }

  /// Closes the connection and stops reconnecting.
  Future<void> stop() async {
    _generation++;
    _setState(LiveState.idle);

    final channel = _channel;
    _channel = null;

    final finished = _finished;

    if (finished != null && !finished.isCompleted) {
      finished.complete(null);
    }

    if (channel != null) {
      _closeQuietly(channel);
    }
  }

  /// Sends a message to the server. False (nothing sent) when the connection
  /// is not up; the caller keeps the message and sends it after reconnecting.
  bool send(Map<String, dynamic> message) {
    final channel = _channel;

    if (channel == null || _state != LiveState.connected) {
      return false;
    }

    channel.send(jsonEncode(message));
    return true;
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _messages.close();
    await _states.close();
  }

  bool _isCurrent(int generation) => generation == _generation && !_disposed;

  void _setState(LiveState state) {
    if (_state == state || _disposed) {
      return;
    }

    _state = state;
    _states.add(state);
  }

  Future<void> _run(int generation) async {
    var attempt = 0;

    while (_isCurrent(generation)) {
      final outcome = await _connectOnce(generation);

      if (!_isCurrent(generation)) {
        return;
      }

      final reason = stopReasonForCloseCode(outcome.closeCode);

      if (reason != null) {
        _stopReason = reason;
        _setState(LiveState.stopped);
        return;
      }

      if (outcome.established) {
        attempt = 0;
      }

      _setState(LiveState.waiting);
      await _delay(backoffFor(attempt));
      attempt++;
    }
  }

  Future<_Outcome> _connectOnce(int generation) async {
    _setState(LiveState.connecting);

    final LiveChannel channel;

    try {
      channel = _connect(addressFor(sinceProvider()));
    } catch (_) {
      return const _Outcome(closeCode: null, established: false);
    }

    try {
      await channel.ready;
    } catch (_) {
      _closeQuietly(channel);
      return const _Outcome(closeCode: null, established: false);
    }

    if (!_isCurrent(generation)) {
      _closeQuietly(channel);
      return const _Outcome(closeCode: null, established: false);
    }

    _channel = channel;

    final finished = Completer<int?>();
    _finished = finished;
    var established = false;

    final subscription = channel.stream.listen(
      (data) {
        if (data is! String) {
          return;
        }

        final message = LiveMessage.tryParse(data);

        if (message == null) {
          return;
        }

        // The server starts talking as soon as it accepts the connection, so
        // the first message it understands means the connection is fully up.
        if (!established) {
          established = true;
          _setState(LiveState.connected);
        }

        if (!_messages.isClosed) {
          _messages.add(message);
        }
      },
      onError: (Object _) {
        if (!finished.isCompleted) {
          finished.complete(channel.closeCode);
        }
      },
      onDone: () {
        if (!finished.isCompleted) {
          finished.complete(channel.closeCode);
        }
      },
      cancelOnError: true,
    );

    unawaited(_pingWhileOpen(generation, channel, finished));

    final code = await finished.future;

    await subscription.cancel();

    if (identical(_channel, channel)) {
      _channel = null;
    }

    return _Outcome(closeCode: code, established: established);
  }

  Future<void> _pingWhileOpen(
    int generation,
    LiveChannel channel,
    Completer<int?> finished,
  ) async {
    while (true) {
      await _delay(pingInterval);

      if (!_isCurrent(generation) ||
          finished.isCompleted ||
          !identical(_channel, channel)) {
        return;
      }

      channel.send(jsonEncode({'type': 'ping'}));
    }
  }
}

/// Closes a channel without waiting for the closing handshake (which a dead
/// network may never finish) and without caring whether it was already closed.
void _closeQuietly(LiveChannel channel) {
  try {
    unawaited(channel.close().catchError((Object _) {}));
  } catch (_) {
    // Already closed.
  }
}

class _Outcome {
  const _Outcome({required this.closeCode, required this.established});

  final int? closeCode;
  final bool established;
}
