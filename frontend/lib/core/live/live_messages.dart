import 'dart:convert';

/// One person connected to the document, as listed by a `presence` message.
class LivePerson {
  const LivePerson({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is LivePerson && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'LivePerson($id, $name)';
}

/// What the server sends over the live connection (`/spreadsheet/live`).
/// The messages are described in docs/COLLABORATION.md.
sealed class LiveMessage {
  const LiveMessage();

  /// Reads one text message from the server. Returns null for anything that
  /// is not a message this client understands (not JSON, no or unknown
  /// `type`, a required field missing): such a message is skipped, so a newer
  /// server can add message types without breaking an older client.
  static LiveMessage? tryParse(String text) {
    final Object? decoded;

    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    switch (decoded['type']) {
      case 'catch_up':
        {
          final revision = decoded['revision'];

          if (revision is! int) {
            return null;
          }

          return CatchUpMessage(
            revision: revision,
            batches: _maps(decoded['batches']),
          );
        }

      case 'resync':
        {
          final revision = decoded['revision'];

          if (revision is! int) {
            return null;
          }

          return ResyncMessage(
            revision: revision,
            reason: decoded['reason']?.toString() ?? '',
          );
        }

      case 'batch':
        {
          final batch = decoded['batch'];

          if (batch is! Map<String, dynamic> || batch['revision'] is! int) {
            return null;
          }

          return BatchMessage(batch: batch);
        }

      case 'presence':
        return PresenceMessage(
          people: [
            for (final entry in _maps(decoded['clients']))
              if (entry['id'] is String)
                LivePerson(
                  id: entry['id'] as String,
                  name: entry['name']?.toString() ?? '',
                ),
          ],
        );

      case 'result':
        return ResultMessage(body: decoded);

      case 'error':
        return ErrorMessage(
          code: decoded['code']?.toString() ?? '',
          message: decoded['message']?.toString() ?? '',
        );

      case 'pong':
        return const PongMessage();

      default:
        return null;
    }
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List<dynamic>) {
      return const [];
    }

    return [
      for (final item in value)
        if (item is Map<String, dynamic>) item,
    ];
  }
}

/// What the client missed since the revision it connected with (maybe
/// nothing). [revision] is the server's newest revision.
class CatchUpMessage extends LiveMessage {
  const CatchUpMessage({required this.revision, required this.batches});

  final int revision;
  final List<Map<String, dynamic>> batches;
}

/// The whole document must be loaded again. [reason] is `BEHIND`,
/// `AHEAD_OF_SERVER` or `CHANGED`.
class ResyncMessage extends LiveMessage {
  const ResyncMessage({required this.revision, required this.reason});

  final int revision;
  final String reason;

  /// The client had seen a revision this server never reached, which means
  /// the server was restarted: the client's revision numbers are meaningless.
  bool get serverRestarted => reason == 'AHEAD_OF_SERVER';
}

/// One new change (from anyone, this client included).
class BatchMessage extends LiveMessage {
  const BatchMessage({required this.batch});

  /// The log entry: revision, kind, client_id, client_batch_id, sheet_id, ops.
  final Map<String, dynamic> batch;

  int get revision => batch['revision'] as int;

  String get clientId => batch['client_id']?.toString() ?? '';

  String get clientBatchId => batch['client_batch_id']?.toString() ?? '';
}

/// Who is connected now, oldest connection first.
class PresenceMessage extends LiveMessage {
  const PresenceMessage({required this.people});

  final List<LivePerson> people;
}

/// The answer to a batch this client sent.
class ResultMessage extends LiveMessage {
  const ResultMessage({required this.body});

  /// Everything the server sent (`accepted`, `client_batch_id`, `revision`,
  /// `duplicate`, `dropped`, or `code`/`message` when refused).
  final Map<String, dynamic> body;

  bool get accepted => body['accepted'] == true;

  String get clientBatchId => body['client_batch_id']?.toString() ?? '';
}

/// A problem the server reports, such as `SESSION_NOT_OPEN`.
class ErrorMessage extends LiveMessage {
  const ErrorMessage({required this.code, required this.message});

  final String code;
  final String message;
}

/// The answer to a ping.
class PongMessage extends LiveMessage {
  const PongMessage();
}
