import 'dart:async';

/// Turns whatever went wrong into one sentence for the user. The technical
/// detail stays in the log (the controller prints it); a message the SERVER
/// wrote for the user (a refusal such as "A document named X already
/// exists") is passed through.
///
/// [action] completes "Could not ...", e.g. `save the document`.
String describeFileError(Object error, String action) {
  var text = error.toString();

  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }

  final cannotReach = error is TimeoutException ||
      text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Connection refused') ||
      text.contains('Failed host lookup');

  if (cannotReach) {
    return "Can't reach the server. Check the connection and try again.";
  }

  // "Failed to open document: 400 {...}" is the app's own wording for an
  // HTTP error: technical, not for the user.
  final technical = RegExp(r'^Failed to [^:]+: \d{3}');

  if (text.trim().isEmpty || technical.hasMatch(text)) {
    return 'Could not $action. Check that the server is running and try again.';
  }

  return text;
}
