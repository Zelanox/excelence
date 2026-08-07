import 'package:flutter/foundation.dart';

import '../models/viewport_model.dart';

class ViewportController extends ChangeNotifier {
  ViewportModel _viewport = const ViewportModel();

  ViewportModel get viewport => _viewport;

  void setScroll({
    required double x,
    required double y,
  }) {
    _viewport = _viewport.copyWith(
      scrollX: x,
      scrollY: y,
    );

    notifyListeners();
  }

  void setZoom(double zoom) {
    _viewport = _viewport.copyWith(
      zoom: zoom,
    );

    notifyListeners();
  }
}