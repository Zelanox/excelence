import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/live/live_channel.dart';
import 'package:frontend/core/live/live_connection.dart';
import 'package:frontend/core/live/live_coordinator.dart';
import 'package:frontend/core/live/live_messages.dart';

class FakeChannel implements LiveChannel {
  FakeChannel(this.address);

  final Uri address;
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final Completer<void> _ready = Completer<void>();
  int? _closeCode;
  bool closedByClient = false;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  void send(String text) {}

  @override
  Future<void> close() async {
    closedByClient = true;
    _closeCode ??= 1000;

    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }

  @override
  int? get closeCode => _closeCode;

  void accept() => _ready.complete();

  void serverSends(Map<String, Object?> message) =>
      _incoming.add(jsonEncode(message));

  void serverCloses(int? code) {
    _closeCode = code;
    unawaited(_incoming.close());
  }
}

class Wait {
  Wait(this.duration);

  final Duration duration;
  final Completer<void> completer = Completer<void>();
}

class Harness {
  Harness() {
    coordinator = LiveCoordinator(
      addressFor: (since) => Uri.parse('ws://test/spreadsheet/live?since=$since'),
      connect: (address) {
        final channel = FakeChannel(address);
        channels.add(channel);
        return channel;
      },
      reload: () async {
        reloads++;
      },
      onChanged: () => changes++,
      onSessionLost: () => lost++,
      // Pings and reconnect delays wait for the test to release them; the
      // reload debounce does not wait at all.
      debounce: Duration.zero,
      delay: (duration) {
        if (duration == Duration.zero) {
          return Future<void>.value();
        }

        final wait = Wait(duration);
        waits.add(wait);
        return wait.completer.future;
      },
    );
  }

  late final LiveCoordinator coordinator;
  final List<FakeChannel> channels = [];
  final List<Wait> waits = [];
  int reloads = 0;
  int changes = 0;
  int lost = 0;

  FakeChannel get channel => channels.last;

  Future<void> connect({int revision = 0}) async {
    coordinator.start();
    await pumpEventQueue();
    channel.accept();
    await pumpEventQueue();
    channel.serverSends({'type': 'catch_up', 'revision': revision, 'batches': []});
    await pumpEventQueue();
  }

  Future<void> serverSays(Map<String, Object?> message) async {
    channel.serverSends(message);
    await pumpEventQueue();
  }
}

Map<String, Object?> batch(int revision, {String client = 'someone-else-01'}) => {
      'type': 'batch',
      'batch': {'revision': revision, 'kind': 'ops', 'client_id': client},
    };

Map<String, Object?> presence(List<List<String>> people) => {
      'type': 'presence',
      'clients': [
        for (final p in people) {'id': p[0], 'name': p[1]},
      ],
    };

void main() {
  test('connects from the revision of the data that was loaded', () async {
    final h = Harness();
    h.coordinator.dataLoaded(12);

    h.coordinator.start();
    await pumpEventQueue();

    expect(h.channel.address.queryParameters['since'], '12');
    expect(h.coordinator.knownRevision, 12);
  });

  test('knows who is here, and tells the UI when that changes', () async {
    final h = Harness();
    await h.connect();
    final before = h.changes;

    await h.serverSays(presence([
      ['client-alice-0001', 'Alice'],
      ['client-salma-0002', 'سلمى'],
    ]));

    expect(h.coordinator.people.map((p) => p.name), ['Alice', 'سلمى']);
    expect(h.changes, greaterThan(before));
    expect(h.coordinator.isConnected, isTrue);
  });

  test('a change by someone else reloads the document', () async {
    final h = Harness();
    h.coordinator.dataLoaded(3);
    await h.connect(revision: 3);

    await h.serverSays(batch(4));

    expect(h.reloads, 1);
    expect(h.coordinator.knownRevision, 4);
  });

  test('the echo of our own change, already covered by its response, does not reload', () async {
    final h = Harness();
    h.coordinator.dataLoaded(3);
    await h.connect(revision: 3);

    h.coordinator.localRequestStarted();
    await h.serverSays(batch(4, client: 'me-myself-and-i'));     // the broadcast arrives first
    h.coordinator.dataLoaded(4);                                // then our own response
    h.coordinator.localRequestFinished();
    await pumpEventQueue();

    expect(h.reloads, 0);
  });

  test('missing changes when reconnecting are caught up by reloading', () async {
    final h = Harness();
    h.coordinator.dataLoaded(3);
    await h.connect(revision: 3);

    h.channel.serverCloses(1012);
    await pumpEventQueue();
    h.waits.firstWhere((w) => w.duration == const Duration(seconds: 1)).completer.complete();
    await pumpEventQueue();

    expect(h.channels, hasLength(2));
    expect(h.channel.address.queryParameters['since'], '3');

    h.channel.accept();
    await pumpEventQueue();
    h.channel.serverSends({
      'type': 'catch_up',
      'revision': 6,
      'batches': [
        {'revision': 4},
        {'revision': 5},
        {'revision': 6},
      ],
    });
    await pumpEventQueue();

    expect(h.reloads, 1);
    expect(h.coordinator.knownRevision, 6);
  });

  test('the list of people is dropped when the connection is lost', () async {
    final h = Harness();
    await h.connect();
    await h.serverSays(presence([['client-alice-0001', 'Alice']]));
    expect(h.coordinator.people, isNotEmpty);

    h.channel.serverCloses(1013);
    await pumpEventQueue();

    expect(h.coordinator.state, LiveState.waiting);
    expect(h.coordinator.people, isEmpty);
  });

  test('an error from the server is kept until the connection is healthy again', () async {
    final h = Harness();
    h.coordinator.start();
    await pumpEventQueue();
    h.channel.accept();
    await pumpEventQueue();

    await h.serverSays({
      'type': 'error',
      'code': 'SESSION_NOT_OPEN',
      'message': 'Open the document again.',
    });
    h.channel.serverCloses(1008);
    await pumpEventQueue();

    expect(h.coordinator.lastError, 'SESSION_NOT_OPEN: Open the document again.');
    expect(h.coordinator.state, LiveState.stopped);
    expect(h.coordinator.stopReason, LiveStopReason.refused);
  });

  test('a server that restarted makes the client reload from scratch', () async {
    final h = Harness();
    h.coordinator.dataLoaded(40);
    await h.connect(revision: 40);

    await h.serverSays({'type': 'resync', 'revision': 1, 'reason': 'AHEAD_OF_SERVER'});

    expect(h.reloads, 1);
    expect(h.coordinator.knownRevision, 1);
  });

  test('dispose closes the connection and silences everything', () async {
    final h = Harness();
    await h.connect();

    h.coordinator.dispose();
    await pumpEventQueue();
    final changesAtDispose = h.changes;

    expect(h.channel.closedByClient, isTrue);

    h.coordinator.dispose();                   // twice is fine
    await pumpEventQueue();
    expect(h.changes, changesAtDispose);
  });

  test('tells the app when the server no longer has the document open', () async {
    final h = Harness();
    h.coordinator.start();
    await pumpEventQueue();
    h.channel.accept();
    await pumpEventQueue();

    await h.serverSays({
      'type': 'error',
      'code': 'SESSION_NOT_OPEN',
      'message': 'Open the document again.',
    });

    expect(h.lost, 1);
  });

  test('other server errors do not count as a lost document', () async {
    final h = Harness();
    await h.connect();

    await h.serverSays({
      'type': 'error',
      'code': 'BAD_REQUEST',
      'message': 'Nope.',
    });

    expect(h.lost, 0);
  });
}
