import 'dart:async';
import 'dart:collection';

import 'live_messages.dart';

Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

/// Decides when this client's copy of the document is out of date and must
/// be loaded again, from what arrives on the live connection.
///
/// Without [applyBatch] every change by someone else is handled by reloading
/// the document ("reload mode"): simple and always correct. With it, a batch
/// of changes is applied directly (see [applyBatch]) and the document is
/// reloaded only when that is not possible.
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
    this.applyBatch,
  })  : _reload = reload,
        _delay = delay;

  final Future<void> Function() _reload;
  final Future<void> Function(Duration) _delay;

  /// How long to wait for more messages before reloading.
  final Duration debounce;

  /// Called when a reload throws. The sync stays armed: the next message or
  /// finished local request tries again.
  final void Function(Object error)? onReloadFailed;

  /// Applies one batch of someone else's changes to the local copy and says
  /// whether it could (false: it can't be applied, so the document is
  /// reloaded instead). Batches are offered strictly in order, each exactly
  /// one revision after the previous, never one the local copy already
  /// includes, and never while this client has a request of its own in
  /// flight. Null turns this off (reload mode).
  final bool Function(BatchMessage batch)? applyBatch;

  // Batches that arrived but could not be applied yet, by revision (an
  // earlier one is missing, or a request of our own is still in flight).
  final SplayTreeMap<int, BatchMessage> _waiting =
      SplayTreeMap<int, BatchMessage>();

  // Revisions that are this client's own changes: already in the local copy
  // (applied when the user made them), so they are stepped over, not applied.
  final Set<int> _own = <int>{};

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

  /// This client's own change was accepted by the server as [revision]. It is
  /// already in the local copy, but that does NOT mean the copy is up to date
  /// through [revision]: somebody else's change may have come just before it
  /// (then it must still be applied, in order). So this only steps over the
  /// revision when it directly follows what the copy has.
  void ownBatch(int revision) {
    if (revision <= _known) {
      return;
    }

    _own.add(revision);
    _see(revision);
    _advanceOwn();
    _applyWaiting();
    _requestCheck();
  }

  /// Forget everything: the document was closed or another one opened.
  void reset([int revision = 0]) {
    _known = revision;
    _latestSeen = revision;
    _force = false;
    _waiting.clear();
    _own.clear();
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
      case final CatchUpMessage catchUp:
        _see(catchUp.revision);

        for (final entry in catchUp.batches) {
          if (entry['revision'] is int) {
            _keep(BatchMessage(batch: entry));
          }
        }

      case final BatchMessage batch:
        _see(batch.revision);
        _keep(batch);

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

    _applyWaiting();
    _requestCheck();
  }

  void dispose() {
    _disposed = true;
  }

  void _keep(BatchMessage batch) {
    if (applyBatch != null && batch.revision > _known) {
      _waiting[batch.revision] = batch;
    }
  }

  /// Applies, in order, every waiting batch that follows directly on what the
  /// local copy has. Stops at a gap (something is missing: the check will
  /// reload) or at a batch that can't be applied (reload as well).
  void _applyWaiting() {
    final apply = applyBatch;

    _advanceOwn();

    if (apply == null || _disposed || _reloading || _pendingLocal > 0) {
      return;
    }

    while (true) {
      _waiting.removeWhere((revision, _) => revision <= _known);

      if (_advanceOwn()) {
        continue;
      }

      final next = _waiting[_known + 1];

      if (next == null) {
        return;
      }

      bool applied;

      try {
        applied = apply(next);
      } catch (error) {
        applied = false;
        onReloadFailed?.call(error);
      }

      if (!applied) {
        _waiting.clear();
        _force = true;
        return;
      }

      _waiting.remove(next.revision);
      _known = next.revision;
    }
  }

  /// Steps over our own revisions that directly follow the local copy.
  /// Returns whether it moved.
  bool _advanceOwn() {
    var moved = false;

    _own.removeWhere((revision) => revision <= _known);

    while (_own.remove(_known + 1)) {
      _known++;
      moved = true;
    }

    return moved;
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
    if (_disposed || _reloading || _pendingLocal > 0) {
      return;
    }

    _applyWaiting();

    if (!_outOfDate) {
      return;
    }

    _reloading = true;
    _force = false;
    _waiting.clear();
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
