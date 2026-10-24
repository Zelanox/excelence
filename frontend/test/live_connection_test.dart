import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/live/live_channel.dart';
import 'package:frontend/core/live/live_connection.dart';
import 'package:frontend/core/live/live_messages.dart';

class FakeChannel implements LiveChannel {
  FakeChannel(this.address);

  final Uri address;
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final Completer<void> _ready = Completer<void>();
  final List<String> sent = [];
  int? _closeCode;
  bool closedByClient = false;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  void send(String text) => sent.add(text);

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

  void failHandshake() => _ready.completeError(Exception('refused'));

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

const Map<String, Object?> catchUp = {
  'type': 'catch_up',
  'revision': 0,
  'batches': [],
};

class Harness {
  Harness() {
    connection = LiveConnection(
      addressFor: (s) => Uri.parse('ws://test/spreadsheet/live?since=$s'),
      sinceProvider: () => since,
      connect: (address) {
        final channel = FakeChannel(address);
        channels.add(channel);
        return channel;
      },
      pingInterval: const Duration(seconds: 30),
      delay: (duration) {
        final wait = Wait(duration);
        waits.add(wait);
        return wait.completer.future;
      },
    );

    connection.messages.listen(messages.add);
    connection.states.listen(states.add);
  }

  late final LiveConnection connection;
  final List<FakeChannel> channels = [];
  final List<Wait> waits = [];
  final List<LiveMessage> messages = [];
  final List<LiveState> states = [];
  int since = 0;

  FakeChannel get channel => channels.last;

  /// The latest not yet finished wait of this length.
  Wait waitOf(Duration duration) =>
      waits.lastWhere((w) => w.duration == duration && !w.completer.isCompleted);

  bool hasWaitOf(Duration duration) =>
      waits.any((w) => w.duration == duration && !w.completer.isCompleted);

  /// Start, let the server accept, and have it say its first message.
  Future<void> connect() async {
    connection.start();
    await pumpEventQueue();
    channel.accept();
    await pumpEventQueue();
    channel.serverSends(catchUp);
    await pumpEventQueue();
  }

  Future<void> pass(Duration duration) async {
    waitOf(duration).completer.complete();
    await pumpEventQueue();
  }
}

const one = Duration(seconds: 1);
const two = Duration(seconds: 2);
const four = Duration(seconds: 4);
const thirty = Duration(seconds: 30);

void main() {
  test('connects with the revision it has, and is connected once the server speaks', () async {
    final h = Harness()..since = 7;

    h.connection.start();
    await pumpEventQueue();

    expect(h.connection.state, LiveState.connecting);
    expect(h.channel.address.queryParameters['since'], '7');

    h.channel.accept();
    await pumpEventQueue();
    expect(h.connection.state, LiveState.connecting);      // accepted, nothing said yet

    h.channel.serverSends(catchUp);
    await pumpEventQueue();

    expect(h.connection.state, LiveState.connected);
    expect(h.states, [LiveState.connecting, LiveState.connected]);
    expect(h.messages.single, isA<CatchUpMessage>());
  });

  test('messages it does not understand are skipped and do not count as the server speaking', () async {
    final h = Harness();

    h.connection.start();
    await pumpEventQueue();
    h.channel.accept();
    await pumpEventQueue();

    h.channel.serverSends({'type': 'something_new'});
    await pumpEventQueue();
    expect(h.connection.state, LiveState.connecting);
    expect(h.messages, isEmpty);

    h.channel.serverSends({'type': 'pong'});
    await pumpEventQueue();
    expect(h.connection.state, LiveState.connected);
  });

  test('pings every 30 seconds while connected', () async {
    final h = Harness();
    await h.connect();

    expect(h.channel.sent, isEmpty);

    await h.pass(thirty);
    expect(h.channel.sent, [jsonEncode({'type': 'ping'})]);

    await h.pass(thirty);
    expect(h.channel.sent, hasLength(2));
  });

  test('reconnects after a drop, asking from the latest revision, and starts the backoff over', () async {
    final h = Harness();
    await h.connect();

    h.since = 9;
    h.channel.serverCloses(1013);                 // too slow: reconnect
    await pumpEventQueue();

    expect(h.connection.state, LiveState.waiting);
    expect(h.channels, hasLength(1));

    await h.pass(one);
    expect(h.channels, hasLength(2));
    expect(h.channel.address.queryParameters['since'], '9');

    h.channel.accept();
    await pumpEventQueue();
    h.channel.serverSends(catchUp);
    await pumpEventQueue();
    expect(h.connection.state, LiveState.connected);

    h.channel.serverCloses(1012);
    await pumpEventQueue();
    expect(h.hasWaitOf(one), isTrue);             // back to 1 s after a good connection
  });

  test('a network drop (no close code) reconnects too', () async {
    final h = Harness();
    await h.connect();

    h.channel.serverCloses(null);
    await pumpEventQueue();

    expect(h.connection.state, LiveState.waiting);
    await h.pass(one);
    expect(h.channels, hasLength(2));
  });

  test('failed attempts wait 1, 2, 4 seconds', () async {
    final h = Harness();

    h.connection.start();
    await pumpEventQueue();
    h.channel.failHandshake();
    await pumpEventQueue();
    expect(h.connection.state, LiveState.waiting);

    await h.pass(one);
    h.channel.failHandshake();
    await pumpEventQueue();

    await h.pass(two);
    h.channel.failHandshake();
    await pumpEventQueue();

    expect(h.hasWaitOf(four), isTrue);
    expect(h.channels, hasLength(3));
  });

  test('being replaced (4001) stops for good', () async {
    final h = Harness();
    await h.connect();

    h.channel.serverCloses(4001);
    await pumpEventQueue();

    expect(h.connection.state, LiveState.stopped);
    expect(h.connection.stopReason, LiveStopReason.replaced);
    expect(h.hasWaitOf(one), isFalse);
    expect(h.channels, hasLength(1));
  });

  test('being refused (1008) stops for good, after delivering the reason', () async {
    final h = Harness();

    h.connection.start();
    await pumpEventQueue();
    h.channel.accept();
    await pumpEventQueue();
    h.channel.serverSends({
      'type': 'error',
      'code': 'SESSION_NOT_OPEN',
      'message': 'Open the document again.',
    });
    h.channel.serverCloses(1008);
    await pumpEventQueue();

    expect((h.messages.single as ErrorMessage).code, 'SESSION_NOT_OPEN');
    expect(h.connection.state, LiveState.stopped);
    expect(h.connection.stopReason, LiveStopReason.refused);
    expect(h.channels, hasLength(1));
  });

  test('stop closes the connection and nothing reconnects or pings afterwards', () async {
    final h = Harness();
    await h.connect();

    await h.connection.stop();
    await pumpEventQueue();

    expect(h.connection.state, LiveState.idle);
    expect(h.channel.closedByClient, isTrue);

    for (final wait in h.waits) {
      if (!wait.completer.isCompleted) {
        wait.completer.complete();
      }
    }

    await pumpEventQueue();
    expect(h.channels, hasLength(1));
    expect(h.channel.sent, isEmpty);
  });

  test('it can be started again after stop', () async {
    final h = Harness();
    await h.connect();
    await h.connection.stop();
    await pumpEventQueue();

    h.connection.start();
    await pumpEventQueue();

    expect(h.channels, hasLength(2));
    expect(h.connection.state, LiveState.connecting);
  });

  test('it can be started again after being stopped for good', () async {
    final h = Harness();
    await h.connect();
    h.channel.serverCloses(1008);
    await pumpEventQueue();
    expect(h.connection.state, LiveState.stopped);

    h.connection.start();
    await pumpEventQueue();

    expect(h.channels, hasLength(2));
    expect(h.connection.stopReason, isNull);
  });

  test('starting twice does not open a second connection', () async {
    final h = Harness();

    h.connection.start();
    h.connection.start();
    await pumpEventQueue();

    expect(h.channels, hasLength(1));
  });

  test('send works only while connected', () async {
    final h = Harness();

    expect(h.connection.send({'type': 'ping'}), isFalse);

    await h.connect();
    expect(h.connection.send({'type': 'ops', 'payload': {}}), isTrue);
    expect(h.channel.sent.single, jsonEncode({'type': 'ops', 'payload': {}}));

    h.channel.serverCloses(1012);
    await pumpEventQueue();
    expect(h.connection.send({'type': 'ping'}), isFalse);
  });

  test('backoff is 1, 2, 4, 8 and then 15 seconds', () {
    expect(
      [for (var i = 0; i < 7; i++) backoffFor(i).inSeconds],
      [1, 2, 4, 8, 15, 15, 15],
    );
  });

  test('only 1008 and 4001 stop the reconnecting', () {
    expect(stopReasonForCloseCode(1008), LiveStopReason.refused);
    expect(stopReasonForCloseCode(4001), LiveStopReason.replaced);

    for (final code in [1000, 1001, 1006, 1011, 1012, 1013, null]) {
      expect(stopReasonForCloseCode(code), isNull, reason: 'code $code');
    }
  });
}
