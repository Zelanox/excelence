import 'package:flutter/foundation.dart';

import '../models/viewport_model.dart';
import '../presentation/widgets/viewport/hit_tester.dart';
import '../models/cell_position.dart';
import '../models/selection_model.dart';


class ViewportController extends ChangeNotifier {


  ViewportModel _viewport = const ViewportModel();
  SelectionModel _selection = const SelectionModel();
  final HitTester _hitTester = const HitTester();

  ViewportModel get viewport => _viewport;
  SelectionModel get selection => _selection;

  void updateViewport(ViewportModel newViewport) {
    _viewport = newViewport;
    notifyListeners();
  }

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

  void selectCell(int row, int column) {
    _selection = SelectionModel(
      startRow: row,
      endRow: row,
      startColumn: column,
      endColumn: column,
    );

    notifyListeners();
  }

  void selectFromPixel({
    required double x,
    required double y,
  }) {
    final CellPosition position = _hitTester.fromPixel(
      x: x,
      y: y,
    );

    selectCell(
      position.row,
      position.column,
    );
  }
}