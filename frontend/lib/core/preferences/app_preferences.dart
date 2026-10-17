import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Persists small pieces of app state across restarts: the last opened
/// document and user preferences.
///
/// The source of truth is the BACKEND (see `/app-state`), not the browser.
/// On web, SharedPreferences is browser localStorage, which belongs to one
/// ORIGIN (host + port) - and `flutter run -d chrome` serves the app on a
/// new random port every launch, so localStorage looks empty each time and
/// nothing "stuck". The backend is the same process, reading the same
/// folder, every time.
///
/// Local storage is kept as a fallback for when the backend can't be
/// reached (and to carry over values saved before this moved), so a
/// backend that is slow to start degrades to the old behavior rather than
/// to nothing.
///
/// This stays one small wrapper so callers don't need to know any of that:
/// they just call `const AppPreferences()`.
class AppPreferences {
  const AppPreferences();

  static const _lastOpenedDocumentKey = 'last_opened_document';
  static const _autoSearchAfterAddRowKey = 'auto_search_after_add_row';

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static ApiClient? _backend;

  /// Points preferences at the backend. Called once at startup (by the
  /// shell, which owns the ApiClient); until then everything uses local
  /// storage only.
  static void useBackend(ApiClient client) {
    _backend = client;
  }

  /// Runs a read against local storage, treating ANY failure as "nothing
  /// stored". Local storage is only a fallback and a convenience: if the
  /// platform has no implementation (as in widget tests), or the browser
  /// blocks storage, startup must carry on rather than crash.
  Future<T?> _read<T>(Future<T?> Function(SharedPreferencesAsync prefs) read) async {
    try {
      return await read(_prefs);
    } catch (error) {
      debugPrint('[AppPreferences] local storage unavailable: $error');
      return null;
    }
  }

  /// The write counterpart of [_read]: failing to REMEMBER something must
  /// never break the action that triggered it.
  Future<void> _write(Future<void> Function(SharedPreferencesAsync prefs) write) async {
    try {
      await write(_prefs);
    } catch (error) {
      debugPrint('[AppPreferences] could not save to local storage: $error');
    }
  }

  /// The backend's saved state, or null if it can't be reached - callers
  /// then fall back to local storage. A reachable backend that simply has
  /// no value returns a map without the key (not null).
  Future<Map<String, dynamic>?> _readBackendState() async {
    final backend = _backend;

    if (backend == null) {
      return null;
    }

    try {
      final response = await backend.get('/app-state');

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBackendPreference(String key, Object? value) async {
    try {
      await _backend?.post(
        '/app-state/preferences',
        body: {'key': key, 'value': value},
      );
    } catch (_) {
      // Best effort: the local copy was written first, and a preference
      // that fails to save must never break the action that changed it.
    }
  }

  /// The relative path (e.g. "reports/q1.xlsx") of the last document
  /// successfully opened or created, or null if there isn't a usable one
  /// (first run, or the file has since been deleted).
  ///
  /// The backend records this itself whenever it opens or creates a
  /// document, and only reports it if the file still exists.
  Future<String?> getLastOpenedDocument() async {
    final state = await _readBackendState();
    final remembered = state?['last_document'];

    if (remembered is String && remembered.isNotEmpty) {
      return remembered;
    }

    return _read<String>((prefs) => prefs.getString(_lastOpenedDocumentKey));
  }

  /// Whether adding a row from the status bar should then filter the
  /// sheet by the typed value, so the new row is easy to find and fill in.
  /// On by default. A per-user preference (it's how the user likes to
  /// work, not a property of any one document), so it lives here rather
  /// than in the document.
  Future<bool> getAutoSearchAfterAddRow() async {
    final state = await _readBackendState();
    final preferences = state?['preferences'];

    if (preferences is Map && preferences[_autoSearchAfterAddRowKey] is bool) {
      return preferences[_autoSearchAfterAddRowKey] as bool;
    }

    return (await _read<bool>((prefs) => prefs.getBool(_autoSearchAfterAddRowKey))) ?? true;
  }

  Future<void> setAutoSearchAfterAddRow(bool enabled) async {
    await _write((prefs) => prefs.setBool(_autoSearchAfterAddRowKey, enabled));
    await _writeBackendPreference(_autoSearchAfterAddRowKey, enabled);
  }

  /// Records [filename] as the most recently opened document, in LOCAL
  /// storage only - the backend already records this itself when it opens
  /// the file. Called after a document successfully opens/loads, not on
  /// failure, since a failed open shouldn't become "the" document to
  /// retry on next launch.
  Future<void> setLastOpenedDocument(String filename) {
    return _write((prefs) => prefs.setString(_lastOpenedDocumentKey, filename));
  }
}
