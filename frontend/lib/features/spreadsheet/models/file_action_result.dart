/// The outcome of a File menu action (Save as, Rename, Delete, Close).
///
/// Expected problems - a name that is taken, other people in the document,
/// no connection - are returned here with a message that can be shown to the
/// user as it is. They are never thrown, and never raw server text.
class FileActionResult {
  const FileActionResult.success({this.name = ''})
      : ok = true,
        message = '',
        saveFailed = false;

  const FileActionResult.failure(this.message, {this.saveFailed = false})
      : ok = false,
        name = '';

  final bool ok;

  /// Safe to show to the user. Empty when [ok].
  final String message;

  /// The name the server settled on (the copy, or the new name), if any.
  final String name;

  /// True when closing was stopped because the latest changes could not be
  /// saved: the caller can offer Retry / Close anyway / Cancel.
  final bool saveFailed;
}
