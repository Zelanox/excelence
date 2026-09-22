import 'package:shared_preferences/shared_preferences.dart';

/// Persists small pieces of app state across restarts using the
/// platform's native key-value store (localStorage on web, a plist/
/// registry-equivalent on desktop). Currently only used for "last
/// opened document", but kept as its own small wrapper (rather than
/// calling SharedPreferencesAsync directly from SpreadsheetController)
/// so the controller doesn't need to know which storage mechanism
/// backs this - if that ever needs to change, only this file does.
class AppPreferences {
  const AppPreferences();

  static const _lastOpenedDocumentKey = 'last_opened_document';

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// The relative path (e.g. "reports/q1.xlsx") of the last document
  /// successfully opened or created, or null if none has been recorded
  /// yet (first run, or the value was cleared).
  Future<String?> getLastOpenedDocument() {
    return _prefs.getString(_lastOpenedDocumentKey);
  }

  /// Records [filename] as the most recently opened document. Called
  /// after a document successfully opens/loads - not on failure, since
  /// a failed open shouldn't become "the" document to retry on next
  /// launch.
  Future<void> setLastOpenedDocument(String filename) {
    return _prefs.setString(_lastOpenedDocumentKey, filename);
  }
}