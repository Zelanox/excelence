import 'package:flutter/material.dart';

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

  Rect getVisibleArea(Size viewportSize) {
    return Rect.fromLTWH(
      viewport.scrollX,
      viewport.scrollY,
      viewportSize.width,
      viewportSize.height,
    );
  }

  void selectCell(int row, int column) {
    if (_selection.startRow == row &&
        _selection.startColumn == column) {
      return;
    }

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

  void moveLeft() {
    final row = _selection.startRow;
    final column = (_selection.startColumn - 1).clamp(0, 25);

    selectCell(row, column);
  }

  void moveRight() {
    final row = _selection.startRow;
    final column = (_selection.startColumn + 1).clamp(0, 25);

    selectCell(row, column);
  }

  void moveUp() {
    final row = (_selection.startRow - 1).clamp(0, 99);
    final column = _selection.startColumn;

    selectCell(row, column);
  }

  void moveDown() {
    final row = (_selection.startRow + 1).clamp(0, 99);
    final column = _selection.startColumn;

    selectCell(row, column);
  }

  void ensureVisible({
    required int row,
    required int column,
    required Size viewportSize,
  }) {
    const cellWidth = 80.0;
    const cellHeight = 28.0;

    double newScrollX = viewport.scrollX;
    double newScrollY = viewport.scrollY;

    final left = column * cellWidth;
    final right = left + cellWidth;

    final top = row * cellHeight;
    final bottom = top + cellHeight;

    if (left < viewport.scrollX) {
      newScrollX = left;
    } else if (right > viewport.scrollX + viewportSize.width) {
      newScrollX = right - viewportSize.width;
    }

    if (top < viewport.scrollY) {
      newScrollY = top;
    } else if (bottom > viewport.scrollY + viewportSize.height) {
      newScrollY = bottom - viewportSize.height;
    }

    setScroll(
      x: newScrollX,
      y: newScrollY,
    );
  }

}