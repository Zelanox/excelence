import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/live/live_messages.dart';

LiveMessage? parse(Object? message) => LiveMessage.tryParse(jsonEncode(message));

void main() {
  test('reads a catch_up with the batches it carries', () {
    final message = parse({
      'type': 'catch_up',
      'revision': 3,
      'batches': [
        {'revision': 2, 'client_id': 'a'},
        {'revision': 3, 'client_id': 'b'},
      ],
    });

    expect(message, isA<CatchUpMessage>());
    final catchUp = message as CatchUpMessage;
    expect(catchUp.revision, 3);
    expect(catchUp.batches.map((b) => b['revision']), [2, 3]);
  });

  test('a catch_up without batches is an empty catch-up', () {
    final catchUp = parse({'type': 'catch_up', 'revision': 0}) as CatchUpMessage;

    expect(catchUp.batches, isEmpty);
  });

  test('reads a resync and knows when the server restarted', () {
    final behind = parse({'type': 'resync', 'revision': 9, 'reason': 'BEHIND'})
        as ResyncMessage;
    final restarted = parse(
      {'type': 'resync', 'revision': 0, 'reason': 'AHEAD_OF_SERVER'},
    ) as ResyncMessage;

    expect(behind.revision, 9);
    expect(behind.serverRestarted, isFalse);
    expect(restarted.serverRestarted, isTrue);
  });

  test('reads a batch and its sender', () {
    final message = parse({
      'type': 'batch',
      'batch': {
        'revision': 5,
        'kind': 'ops',
        'client_id': 'client-alice-0001',
        'client_batch_id': 'b1',
        'ops': [],
      },
    }) as BatchMessage;

    expect(message.revision, 5);
    expect(message.clientId, 'client-alice-0001');
    expect(message.clientBatchId, 'b1');
  });

  test('reads presence, in the order given, names in any script', () {
    final presence = parse({
      'type': 'presence',
      'clients': [
        {'id': 'client-alice-0001', 'name': 'Alice'},
        {'id': 'client-salma-0002', 'name': 'سلمى'},
      ],
    }) as PresenceMessage;

    expect(presence.people, const [
      LivePerson(id: 'client-alice-0001', name: 'Alice'),
      LivePerson(id: 'client-salma-0002', name: 'سلمى'),
    ]);
  });

  test('presence entries without an id are skipped', () {
    final presence = parse({
      'type': 'presence',
      'clients': [
        {'name': 'nobody'},
        {'id': 'client-bob-00002', 'name': 'Bob'},
      ],
    }) as PresenceMessage;

    expect(presence.people.map((p) => p.name), ['Bob']);
  });

  test('reads a result', () {
    final accepted = parse({
      'type': 'result',
      'accepted': true,
      'client_batch_id': 'b1',
      'revision': 4,
    }) as ResultMessage;
    final refused = parse({
      'type': 'result',
      'accepted': false,
      'client_batch_id': 'b2',
      'code': 'STALE_REFERENCE',
    }) as ResultMessage;

    expect(accepted.accepted, isTrue);
    expect(accepted.clientBatchId, 'b1');
    expect(refused.accepted, isFalse);
    expect(refused.body['code'], 'STALE_REFERENCE');
  });

  test('reads an error and a pong', () {
    final error = parse({
      'type': 'error',
      'code': 'SESSION_NOT_OPEN',
      'message': 'Open the document again.',
    }) as ErrorMessage;

    expect(error.code, 'SESSION_NOT_OPEN');
    expect(error.message, 'Open the document again.');
    expect(parse({'type': 'pong'}), isA<PongMessage>());
  });

  test('anything it does not understand is skipped, not thrown', () {
    expect(LiveMessage.tryParse('not json'), isNull);
    expect(LiveMessage.tryParse('[1, 2]'), isNull);
    expect(LiveMessage.tryParse('5'), isNull);
    expect(LiveMessage.tryParse('null'), isNull);
    expect(parse({'no_type': 1}), isNull);
    expect(parse({'type': 'something_new'}), isNull);
    expect(parse({'type': 'catch_up'}), isNull);
    expect(parse({'type': 'catch_up', 'revision': 'three'}), isNull);
    expect(parse({'type': 'resync'}), isNull);
    expect(parse({'type': 'batch'}), isNull);
    expect(parse({'type': 'batch', 'batch': {'kind': 'ops'}}), isNull);
  });
}
