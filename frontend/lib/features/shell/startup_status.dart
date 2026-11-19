import 'package:flutter/foundation.dart';

/// Whether the app has finished trying to open its first document, and why
/// it has none if that failed. Until it is done the grid shows a spinner;
/// after that, no document means the "No document open" screen instead of a
/// spinner that never ends.
class StartupStatus extends ChangeNotifier {
  bool _done = false;
  String? _problem;

  bool get done => _done;

  /// Why nothing could be opened at startup, or null.
  String? get problem => _problem;

  void begin() {
    _done = false;
    _problem = null;
    notifyListeners();
  }

  void finish({String? problem}) {
    _done = true;
    _problem = problem;
    notifyListeners();
  }

  /// Forget an old problem once a document is open.
  void clearProblem() {
    if (_problem == null) {
      return;
    }

    _problem = null;
    notifyListeners();
  }
}
