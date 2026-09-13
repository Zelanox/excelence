import 'package:flutter/foundation.dart';

import '../models/selection_model.dart';
import '../models/cell_position.dart';
import '../presentation/widgets/viewport/hit_tester.dart';

class SelectionController extends ChangeNotifier {
  SelectionModel _selection = const SelectionModel();
  final HitTester _hitTester = const HitTester();

  SelectionModel get selection => _selection;

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
    double scrollX = 0,
    double scrollY = 0,
  }) {
    final CellPosition position = _hitTester.fromPixel(
      x: x,
      y: y,
      scrollX: scrollX,
      scrollY: scrollY,
    );

    selectCell(
      position.row,
      position.column,
    );
  }

  void moveLeft({
    required int newRow,
    required int newColumn,
  })
  {
    selectCell(
    newRow,
    newColumn,
    );
  }

  void moveRight({
  required int newRow,
    required int newColumn,
  })
  {
    selectCell(
    newRow,
    newColumn,
    );
  }

  void moveUp({
    required int newRow,
    required int newColumn,
  })
  {
    selectCell(
    newRow,
    newColumn,
    );
  }

  void moveDown({
    required int newRow,
    required int newColumn,
  })
  {
    selectCell(
    newRow,
    newColumn,
    );
  }

}