import 'package:flutter/material.dart';

import '../models/viewport_model.dart';
import '../presentation/widgets/viewport/hit_tester.dart';
import '../models/cell_position.dart';
import '../models/selection_model.dart';
import '../models/visible_range_model.dart';


class ViewportController extends ChangeNotifier {


  ViewportModel _viewport = const ViewportModel();
  SelectionModel _selection = const SelectionModel();
  
  bool _isEditing = false;
  bool _replaceInitialValue = false;
  String? _initialEditValue;
  
  final HitTester _hitTester = const HitTester();

  ViewportModel get viewport => _viewport;
  SelectionModel get selection => _selection;
  
  bool get isEditing => _isEditing;
  bool get replaceInitialValue => _replaceInitialValue;
  String? get initialEditValue => _initialEditValue;

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
  
  CellPosition positionFromPixel({
    required double x,
    required double y,
  }) {
    return _hitTester.fromPixel(
      x: x,
      y: y,
      scrollX: viewport.scrollX,
      scrollY: viewport.scrollY,
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
      scrollX: viewport.scrollX,
      scrollY: viewport.scrollY,
    );

    selectCell(
      position.row,
      position.column,
    );
  }

  void startSelectionFromPixel({
    required double x,
    required double y,
  }) {
    final CellPosition position = _hitTester.fromPixel(
      x: x,
      y: y,
      scrollX: viewport.scrollX,
      scrollY: viewport.scrollY,
    );

    _selection = SelectionModel(
      startRow: position.row,
      endRow: position.row,
      startColumn: position.column,
      endColumn: position.column,
    );

    notifyListeners();
  }

  void updateSelectionFromPixel({
    required double x,
    required double y,
  }) {
    final CellPosition position = _hitTester.fromPixel(
      x: x,
      y: y,
      scrollX: viewport.scrollX,
      scrollY: viewport.scrollY,
    );

    _selection = SelectionModel(
      startRow: _selection.startRow,
      startColumn: _selection.startColumn,
      endRow: position.row,
      endColumn: position.column,
    );

    notifyListeners();
  }

  void moveLeft() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = (_selection.endColumn - 1).clamp(0, 25);

    selectCell(row, column);
  }

  void moveRight() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = (_selection.endColumn + 1).clamp(0, 25);

    selectCell(row, column);
  }

  void moveUp() {
    _stopEditingWithoutNotify();

    final row = (_selection.endRow - 1).clamp(0, 99);
    final column = _selection.endColumn;

    selectCell(row, column);
  }

  void moveDown() {
    _stopEditingWithoutNotify();

    final row = (_selection.endRow + 1).clamp(0, 99);
    final column = _selection.endColumn;

    selectCell(row, column);
  }

  void extendSelectionLeft() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = (_selection.endColumn - 1).clamp(0, 25); 

    _selection = SelectionModel(
      startRow: _selection.startRow,
      startColumn: _selection.startColumn,
      endRow: row,
      endColumn: column,
    );

    notifyListeners();
  }

  void extendSelectionRight() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = (_selection.endColumn + 1).clamp(0, 25);

    _selection = SelectionModel(
      startRow: _selection.startRow,
      startColumn: _selection.startColumn,
      endRow: row,
      endColumn: column,
    );

    notifyListeners();
  }

  void extendSelectionUp() {
    _stopEditingWithoutNotify();

    final row = (_selection.endRow - 1).clamp(0, 99);
    final column = _selection.endColumn;

    _selection = SelectionModel(
      startRow: _selection.startRow,
      startColumn: _selection.startColumn,
      endRow: row,
      endColumn: column,
    );

    notifyListeners();
  }

  void extendSelectionDown() {
    _stopEditingWithoutNotify();

    final row = (_selection.endRow + 1).clamp(0, 99);
    final column = _selection.endColumn;

    _selection = SelectionModel(
      startRow: _selection.startRow,
      startColumn: _selection.startColumn,
      endRow: row,
      endColumn: column,
    );

    notifyListeners();
  }

  void moveNext() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = _selection.endColumn;

    if (column < 25) {
      selectCell(row, column + 1);
      return;
    }

    // Move to the first column of the next row.
    if (row < 99) {
      selectCell(row + 1, 0);
    }
  }

  void movePrevious() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = _selection.endColumn;

    if (column > 0) {
      selectCell(row, column - 1);
      return;
    }

    // Move to the last column of the previous row.
    if (row > 0) {
      selectCell(row - 1, 25);
    }
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

    if (newScrollX != viewport.scrollX ||
      newScrollY != viewport.scrollY) {
      setScroll(
        x: newScrollX,
        y: newScrollY,
      );
    }
  }

  VisibleRangeModel getVisibleRange({
    required Size viewportSize,
    required int totalRows,
    required int totalColumns,
  }) {
    const double cellWidth = 80.0;
    const double cellHeight = 28.0;

    final scrollX = viewport.scrollX;
    final scrollY = viewport.scrollY;

    final zoom = viewport.zoom;

    final scaledCellWidth = cellWidth * zoom;
    final scaledCellHeight = cellHeight * zoom;

    final firstColumn =
        (scrollX / scaledCellWidth).floor().clamp(
          0,
          totalColumns - 1,
        );

    final firstRow =
        (scrollY / scaledCellHeight).floor().clamp(
          0,
          totalRows - 1,
        );

    final visibleColumns =
        (viewportSize.width / scaledCellWidth).ceil() + 1;

    final visibleRows =
        (viewportSize.height / scaledCellHeight).ceil() + 1;

    final lastColumn =
        (firstColumn + visibleColumns - 1).clamp(
          0,
          totalColumns - 1,
        );

    final lastRow =
        (firstRow + visibleRows - 1).clamp(
          0,
          totalRows - 1,
        );

    return VisibleRangeModel(
      firstRow: firstRow,
      lastRow: lastRow,
      firstColumn: firstColumn,
      lastColumn: lastColumn,
    );
  }

  void startEditing({
    bool replaceInitialValue = false,
    String? initialValue,
  }) {
    _isEditing = true;
    _replaceInitialValue = replaceInitialValue;
    _initialEditValue = initialValue;

    notifyListeners();
  }

  void stopEditing() {
    _isEditing = false;
    _replaceInitialValue = false;
    _initialEditValue = null;

    notifyListeners();
  }

  void _stopEditingWithoutNotify() {
    _isEditing = false;
  }

}