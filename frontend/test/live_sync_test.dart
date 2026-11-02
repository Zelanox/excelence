import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/live/live_messages.dart';
import 'package:frontend/core/live/live_sync.dart';

BatchMessage batch(int revision) => BatchMessage(
      batch: {'revision': revision, 'kind': 'ops', 'client_id': 'someone'},
    );

ResyncMessage resync(int revision, [String reason = 'CHANGED']) =>
    ResyncMessage(revision: revision, reason: reason);

class Harness {
  Harness() {
    sync = LiveSync(
      reload: () async {
        reloads++;
        await whileReloading?.call();
      },
      debounce: Duration.zero,
      delay: (_) async {},
      onReloadFailed: failures.add,
    );
  }

  late final LiveSync sync;
  int reloads = 0;
  final List<Object> failures = [];
  Future<void> Function()? whileReloading;

  Future<void> send(LiveMessage message) async {
    sync.onMessage(message);
    await pumpEventQueue();
  }
}

void main() {
  incrementalTests();

  test('a newer batch from someone else reloads the document once', () async {
    final h = Harness();
    h.sync.dataLoaded(3);

    await h.send(batch(4));

    expect(h.reloads, 1);
    expect(h.sync.knownRevision, 4);
  });

  test('messages in quick succession are answered with one reload', () async {
    final h = Harness();

    h.sync.onMessage(batch(1));
    h.sync.onMessage(batch(2));
    h.sync.onMessage(batch(3));
    await pumpEventQueue();

    expect(h.reloads, 1);
    expect(h.sync.knownRevision, 3);
  });

  test('a batch that is not newer than the local copy is ignored', () async {
    final h = Harness();
    h.sync.dataLoaded(5);

    await h.send(batch(5));
    await h.send(batch(4));

    expect(h.reloads, 0);
  });

  test('presence, pong, results and errors never reload', () async {
    final h = Harness();

    await h.send(const PresenceMessage(people: []));
    await h.send(const PongMessage());
    await h.send(const ResultMessage(body: {'accepted': true}));
    await h.send(const ErrorMessage(code: 'X', message: 'x'));

    expect(h.reloads, 0);
  });

  test('while a request of our own is in flight nothing reloads, and its response can settle it', () async {
    final h = Harness();
    h.sync.dataLoaded(3);

    h.sync.localRequestStarted();
    await h.send(resync(4));          // the live message beats our own response
    expect(h.reloads, 0);

    h.sync.dataLoaded(4);             // ...and the response then covers it
    h.sync.localRequestFinished();
    await pumpEventQueue();

    expect(h.reloads, 0);
  });

  test('a change that our own response does not cover is reloaded after it', () async {
    final h = Harness();
    h.sync.dataLoaded(3);

    h.sync.localRequestStarted();
    await h.send(batch(6));
    h.sync.dataLoaded(4);
    h.sync.localRequestFinished();
    await pumpEventQueue();

    expect(h.reloads, 1);
    expect(h.sync.knownRevision, 6);
  });

  test('several local requests: reloading waits for the last one', () async {
    final h = Harness();

    h.sync.localRequestStarted();
    h.sync.localRequestStarted();
    await h.send(batch(2));

    h.sync.localRequestFinished();
    await pumpEventQueue();
    expect(h.reloads, 0);

    h.sync.localRequestFinished();
    await pumpEventQueue();
    expect(h.reloads, 1);
  });

  test('a server that restarted forces a reload and resets the numbering', () async {
    final h = Harness();
    h.sync.dataLoaded(50);

    await h.send(resync(2, 'AHEAD_OF_SERVER'));

    expect(h.reloads, 1);
    expect(h.sync.knownRevision, 2);
  });

  test('BEHIND forces a reload even when the numbers look equal', () async {
    final h = Harness();
    h.sync.dataLoaded(7);

    await h.send(resync(7, 'BEHIND'));

    expect(h.reloads, 1);
  });

  test('a CHANGED resync is only acted on when it is newer', () async {
    final h = Harness();
    h.sync.dataLoaded(7);

    await h.send(resync(7));
    expect(h.reloads, 0);

    await h.send(resync(8));
    expect(h.reloads, 1);
  });

  test('a catch-up with nothing new does nothing, one with news reloads', () async {
    final h = Harness();
    h.sync.dataLoaded(5);

    await h.send(const CatchUpMessage(revision: 5, batches: []));
    expect(h.reloads, 0);

    await h.send(CatchUpMessage(revision: 8, batches: [{'revision': 8}]));
    expect(h.reloads, 1);
    expect(h.sync.knownRevision, 8);
  });

  test('a message that arrives during a reload causes one more reload after it', () async {
    final h = Harness();
    final gate = Completer<void>();
    h.whileReloading = () => gate.future;

    await h.send(batch(6));
    expect(h.reloads, 1);

    await h.send(batch(7));            // while the first reload is still running
    expect(h.reloads, 1);

    h.whileReloading = null;
    gate.complete();
    await pumpEventQueue();

    expect(h.reloads, 2);
    expect(h.sync.knownRevision, 7);
  });

  test('a reload that never reports its revision does not loop', () async {
    final h = Harness();

    await h.send(batch(5));

    expect(h.reloads, 1);
    expect(h.sync.knownRevision, 5);
  });

  test('a failed reload is reported and retried on the next message, not in a loop', () async {
    final h = Harness();
    h.whileReloading = () async => throw Exception('server down');

    await h.send(batch(2));

    expect(h.reloads, 1);
    expect(h.failures, hasLength(1));
    expect(h.sync.knownRevision, 0);

    h.whileReloading = null;
    await h.send(batch(3));

    expect(h.reloads, 2);
    expect(h.sync.knownRevision, 3);
  });

  test('reset forgets everything', () async {
    final h = Harness();
    h.sync.dataLoaded(9);

    h.sync.reset();
    await h.send(batch(1));

    expect(h.reloads, 1);
  });

  test('a disposed sync does nothing', () async {
    final h = Harness();
    h.sync.dispose();

    await h.send(batch(1));

    expect(h.reloads, 0);
  });
}

class ApplyHarness {
  ApplyHarness() {
    sync = LiveSync(
      reload: () async {
        reloads++;
      },
      debounce: Duration.zero,
      delay: (_) async {},
      onReloadFailed: failures.add,
      applyBatch: (batch) {
        applied.add(batch.revision);

        if (throwOnApply) {
          throw Exception('cannot apply');
        }

        return applyResult;
      },
    );
  }

  late final LiveSync sync;
  int reloads = 0;
  final List<int> applied = [];
  final List<Object> failures = [];
  bool applyResult = true;
  bool throwOnApply = false;

  Future<void> send(LiveMessage message) async {
    sync.onMessage(message);
    await pumpEventQueue();
  }
}

void incrementalTests() {
  group('applying changes directly', () {
    test('the next batch is applied and nothing is reloaded', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      await h.send(batch(4));

      expect(h.applied, [4]);
      expect(h.reloads, 0);
      expect(h.sync.knownRevision, 4);
    });

    test('batches are applied in order, even when they arrive out of order', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      h.sync.onMessage(batch(6));
      h.sync.onMessage(batch(5));
      h.sync.onMessage(batch(4));
      await pumpEventQueue();

      expect(h.applied, [4, 5, 6]);
      expect(h.reloads, 0);
      expect(h.sync.knownRevision, 6);
    });

    test('a batch the local copy already has is not applied', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(5);

      await h.send(batch(5));
      await h.send(batch(3));

      expect(h.applied, isEmpty);
      expect(h.reloads, 0);
    });

    test('a gap (something is missing) is answered with a reload', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      await h.send(batch(6));

      expect(h.applied, isEmpty);
      expect(h.reloads, 1);
      expect(h.sync.knownRevision, 6);
    });

    test('a batch that cannot be applied is answered with a reload', () async {
      final h = ApplyHarness()..applyResult = false;
      h.sync.dataLoaded(3);

      await h.send(batch(4));

      expect(h.applied, [4]);
      expect(h.reloads, 1);
      expect(h.sync.knownRevision, 4);
    });

    test('a failure while applying is reported and answered with a reload', () async {
      final h = ApplyHarness()..throwOnApply = true;
      h.sync.dataLoaded(3);

      await h.send(batch(4));

      expect(h.failures, hasLength(1));
      expect(h.reloads, 1);
    });

    test('nothing is applied while a request of our own is in flight', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      h.sync.localRequestStarted();
      await h.send(batch(4));
      expect(h.applied, isEmpty);

      h.sync.localRequestFinished();
      await pumpEventQueue();

      expect(h.applied, [4]);
      expect(h.reloads, 0);
    });

    test('our own change right after what we have is stepped over, not applied', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      h.sync.ownBatch(4);
      expect(h.sync.knownRevision, 4);

      await h.send(batch(4));          // its echo from the server
      await h.send(batch(5));          // then somebody else's change

      expect(h.applied, [5]);
      expect(h.sync.knownRevision, 5);
      expect(h.reloads, 0);
    });

    test('somebody else\'s change that came just before ours is still applied', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      h.sync.localRequestStarted();
      await h.send(batch(4));          // theirs, arrives while our request is out
      h.sync.ownBatch(5);              // ours was accepted as the next one
      expect(h.sync.knownRevision, 3); // we must NOT claim to be up to date yet

      h.sync.localRequestFinished();
      await pumpEventQueue();

      expect(h.applied, [4]);
      expect(h.sync.knownRevision, 5);
      expect(h.reloads, 0);
    });

    test('our own change with something missing before it is answered with a reload', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      h.sync.ownBatch(5);              // 4 never arrives
      await pumpEventQueue();

      expect(h.reloads, 1);
      expect(h.sync.knownRevision, 5);
    });

    test('without direct applying our own contiguous change is still stepped over', () async {
      final h = Harness();
      h.sync.dataLoaded(3);

      h.sync.ownBatch(4);
      await h.send(batch(4));

      expect(h.sync.knownRevision, 4);
      expect(h.reloads, 0);
    });

    test('the batches of a catch-up are applied', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      await h.send(
        CatchUpMessage(
          revision: 5,
          batches: [
            {'revision': 4, 'kind': 'ops'},
            {'revision': 5, 'kind': 'ops'},
          ],
        ),
      );

      expect(h.applied, [4, 5]);
      expect(h.reloads, 0);
      expect(h.sync.knownRevision, 5);
    });

    test('a reload entry in between stops the direct applying', () async {
      final h = ApplyHarness();
      h.sync.dataLoaded(3);

      h.sync.onMessage(batch(4));
      h.sync.onMessage(resync(5));
      h.sync.onMessage(batch(6));
      await pumpEventQueue();

      expect(h.applied, [4]);
      expect(h.reloads, 1);
      expect(h.sync.knownRevision, 6);
    });
  });
}
