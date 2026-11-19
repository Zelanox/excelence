/// The result of checking a document name typed by the user.
class DocumentNameCheck {
  const DocumentNameCheck._(this.name, this.error);

  /// The cleaned-up name (trimmed, `.xlsx` added) when it is acceptable.
  final String? name;

  /// A message for the user when it is not.
  final String? error;

  bool get ok => error == null;
}

const _extension = '.xlsx';
const _otherExtensions = ['.xls', '.xlsm', '.csv', '.ods'];

/// Checks a name for a new document (Save as, Rename) before asking the
/// server, which checks again and has the last word.
///
/// A name may include folders separated by `/` (`reports/Budget`). `.xlsx`
/// is added when missing. [current] is the name of the open document: using
/// it again is refused.
DocumentNameCheck checkDocumentName(String input, {String? current}) {
  DocumentNameCheck fail(String message) => DocumentNameCheck._(null, message);

  final text = input.trim();

  if (text.isEmpty) {
    return fail('Enter a name for the document.');
  }

  for (final unit in text.runes) {
    if (unit < 32) {
      return fail('The name contains a character that cannot be used.');
    }
  }

  for (final character in const ['\\', ':', '*', '?', '"', '<', '>', '|']) {
    if (text.contains(character)) {
      return fail('A name cannot contain \\ : * ? " < > |');
    }
  }

  final lower = text.toLowerCase();

  for (final other in _otherExtensions) {
    if (lower.endsWith(other)) {
      return fail('Only .xlsx documents are supported. Leave the extension off.');
    }
  }

  final name = lower.endsWith(_extension) ? text : '$text$_extension';
  final segments = name.split('/');

  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      return fail(
        'Use a name like Budget or reports/Budget, without ".." and '
        'without a "/" at the start or end.',
      );
    }

    if (segment != segment.trim()) {
      return fail('A name cannot start or end with a space.');
    }
  }

  if (segments.last.toLowerCase() == _extension) {
    return fail('Enter a name before .xlsx.');
  }

  if (current != null && name.toLowerCase() == current.trim().toLowerCase()) {
    return fail('That is already the name of this document.');
  }

  return DocumentNameCheck._(name, null);
}

/// [name] without its `.xlsx` ending (a name without it is returned as is).
String documentNameWithoutExtension(String name) {
  return name.toLowerCase().endsWith(_extension)
      ? name.substring(0, name.length - _extension.length)
      : name;
}
