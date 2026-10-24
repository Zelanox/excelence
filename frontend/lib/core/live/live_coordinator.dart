import 'dart:async';

import 'live_channel.dart';
import 'live_connection.dart';
import 'live_messages.dart';
import 'live_sync.dart';

Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

/// Everything the app needs for live collaboration on ONE open document: the
/// connection, the logic that decides when to reload, and who is here.
///
/// Create one when a document has been opened (and its data loaded), call
/// [dataLoaded] with the revision that data carried, [start] it, and
/// [dispose] it when the document is closed. It has no Flutter in it;
/// [onChanged] is how the UI is told to redraw.
class LiveCoordinator {
  LiveCoordinator({
    required Uri Function(int since) addressFor,
    required ChannelFactory connect,
    required Future<void> Function() reload,
    this.onChanged,
    this.onSessionLost,
    void Function(Object error)? onReloadFailed,
    Duration pingInterval = const Duration(seconds: 30),
    Duration debounce = const Duration(milliseconds: 150),
    Future<void> Function(Duration)? delay,
  }) {
    final wait = delay ?? _realDelay;

    _sync = LiveSync(
      reload: reload,
      debounce: debounce,
      delay: wait,
      onReloadFailed: onReloadFailed,
    );

    _connection = LiveConnection(
      addressFor: addressFor,
      sinceProvider: () => _sync.knownRevision,
      connect: connect,
      pingInterval: pingInterval,
      delay: wait,
    );

    _messageSubscription = _connection.messages.listen(_onMessage);
    _stateSubscription = _connection.states.listen(_onState);
  }

  /// Called whenever something the UI shows (people, connection state, last
  /// problem) has changed.
  final void Function()? onChanged;

  /// Called when the server says it does not have this document open (for
  /// example after a restart): the app should open the document again.
  final void Function()? onSessionLost;

  late final LiveSync _sync;
  late final LiveConnection _connection;
  late final StreamSubscription<LiveMessage> _messageSubscription;
  late final StreamSubscription<LiveState> _stateSubscription;

  List<LivePerson> _people = const [];
  String? _lastError;
  bool _disposed = false;

  /// Who is connected now, oldest connection first, this client included.
  /// Empty while not connected.
  List<LivePerson> get people => _people;

  LiveState get state => _connection.state;

  /// Why live updates stopped for good, or null.
  LiveStopReason? get stopReason => _connection.stopReason;

  /// The last problem the server reported (for example the document is no
  /// longer open on it), or null.
  String? get lastError => _lastError;

  /// The server revision this client's copy of the document matches.
  int get knownRevision => _sync.knownRevision;

  bool get isConnected => _connection.state == LiveState.connected;

  /// Opens the connection (and keeps it open, reconnecting when needed).
  void start() => _connection.start();

  /// A response with grid data arrived; [revision] is the one it carried.
  void dataLoaded(int revision) => _sync.dataLoaded(revision);

  /// This client is about to change the document on the server.
  void localRequestStarted() => _sync.localRequestStarted();

  /// That request has finished (successfully or not).
  void localRequestFinished() => _sync.localRequestFinished();

  /// Closes the connection and forgets everything. Safe to call twice.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _sync.dispose();
    unawaited(_messageSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_connection.dispose());
  }

  void _onMessage(LiveMessage message) {
    if (_disposed) {
      return;
    }

    switch (message) {
      case PresenceMessage(:final people):
        _people = people;
        _changed();

      case ErrorMessage(:final code, message: final text):
        _lastError = '$code: $text';
        _changed();

        if (code == 'SESSION_NOT_OPEN') {
          onSessionLost?.call();
        }

      case CatchUpMessage() ||
            ResyncMessage() ||
            BatchMessage() ||
            ResultMessage() ||
            PongMessage():
        break;
    }

    _sync.onMessage(message);
  }

  void _onState(LiveState state) {
    if (_disposed) {
      return;
    }

    if (state == LiveState.connected) {
      _lastError = null;
    } else if (_people.isNotEmpty) {
      _people = const [];       // a list from a connection that is gone would mislead
    }

    _changed();
  }

  void _changed() {
    if (!_disposed) {
      onChanged?.call();
    }
  }
}
