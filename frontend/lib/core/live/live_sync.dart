import 'dart:async';

import 'live_messages.dart';

Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

/// Decides when this client's copy of the document is out of date and must
/// be loaded again, from what arrives on the live connection.
///
/// For now every change by someone else is handled by reloading the document
/// ("reload mode"): simple and always correct. Applying the changes one by
/// one comes later and replaces only what [onMessage] does with a batch.
///
/// The bookkeeping that matters:
///
/// * [knownRevision] is the server revision the local copy matches. Every
///   response that carries grid data has one; report it with [dataLoaded].
/// * A message whose revision is not newer than that is already included
///   (typically the echo of this client's own change) and is ignored.
/// * While this client has a request of its own in flight
///   ([localRequestStarted] .. [localRequestFinished]) no reload is started:
///   its response will usually bring the copy up to date by itself, and the
///   live message about the same change often arrives first.
/// * Messages arriving in quick succession are answered with one reload, and
///   a message arriving during a reload causes one more after it.
class LiveSync {
  LiveSync({
    required Future<void> Function() reload,
    this.debounce = const Duration(milliseconds: 150),
    Future<void> Function(Duration) delay = _realDelay,
    this.onReloadFailed,
  })  : _reload = reload,
        _delay = delay;

  final Future<void> Function() _reload;
  final Future<void> Function(Duration) _delay;

  /// How long to wait for more messages before reloading.
  final Duration debounce;

  /// Called when a reload throws. The sync stays armed: the next message or
  /// finished local request tries again.
  final void Function(Object error)? onReloadFailed;

  int _known = 0;
  int _latestSeen = 0;
  int _pendingLocal = 0;
  bool _force = false;
  bool _reloading = false;
  bool _checkScheduled = false;
  bool _disposed = false;

  /// The revision of the log that the local copy of the document matches.
  int get knownRevision => _known;

  /// A response with grid data arrived; [revision] is the one it carried.
  void dataLoaded(int revision) {
    if (revision > _known) {
      _known = revision;
    }
  }

  /// Forget everything: the document was closed or another one opened.
  void reset([int revision = 0]) {
    _known = revision;
    _latestSeen = revision;
    _force = false;
  }

  void localRequestStarted() {
    _pendingLocal++;
  }

  void localRequestFinished() {
    if (_pendingLocal > 0) {
      _pendingLocal--;
    }

    if (_pendingLocal == 0) {
      _requestCheck();
    }
  }

  void onMessage(LiveMessage message) {
    switch (message) {
      case CatchUpMessage(:final revision):
        _see(revision);

      case BatchMessage(:final revision):
        _see(revision);

      case ResyncMessage(:final revision, :final reason, :final serverRestarted):
        if (serverRestarted) {
          // The server counts from 0 again: our numbers mean nothing now.
          _known = revision;
          _latestSeen = revision;
          _force = true;
        } else if (reason == 'BEHIND') {
          _see(revision);
          _force = true;
        } else {
          _see(revision);
        }

      case PresenceMessage() ||
            ResultMessage() ||
            ErrorMessage() ||
            PongMessage():
        return;
    }

    _requestCheck();
  }

  void dispose() {
    _disposed = true;
  }

  void _see(int revision) {
    if (revision > _latestSeen) {
      _latestSeen = revision;
    }
  }

  bool get _outOfDate => _force || _latestSeen > _known;

  void _requestCheck() {
    if (_checkScheduled || _disposed) {
      return;
    }

    _checkScheduled = true;

    unawaited(
      _delay(debounce).then((_) {
        _checkScheduled = false;
        return _check();
      }),
    );
  }

  Future<void> _check() async {
    if (_disposed || _reloading || _pendingLocal > 0 || !_outOfDate) {
      return;
    }

    _reloading = true;
    _force = false;
    final seenAtStart = _latestSeen;

    try {
      await _reload();
    } catch (error) {
      // Stay armed (the next message or finished request tries again) but do
      // not retry by ourselves: a server that is down would be hammered.
      _force = true;
      _reloading = false;
      onReloadFailed?.call(error);
      return;
    }

    _reloading = false;

    // The server had at least this much when we asked, so the copy matches
    // it now, whether or not the reload reported a revision of its own.
    if (_known < seenAtStart) {
      _known = seenAtStart;
    }

    // Something else arrived while reloading.
    if (!_disposed && _latestSeen > _known) {
      _requestCheck();
    }
  }
}
