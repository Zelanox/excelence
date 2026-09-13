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

  // Bounds of the currently loaded sheet. These default to the old
  // mock-data size (100 rows x 26 columns) so nothing breaks before a
  // real document has loaded; setSheetBounds() should be called with the
  // real dimensions as soon as a document/sheet is loaded or switched.
  int _maxRow = 99;
  int _maxColumn = 25;

  ViewportModel get viewport => _viewport;
  SelectionModel get selection => _selection;
  
  bool get isEditing => _isEditing;
  bool get replaceInitialValue => _replaceInitialValue;
  String? get initialEditValue => _initialEditValue;

  /// Updates the valid row/column range for movement and selection.
  ///
  /// [rowCount] and [columnCount] are the sheet's actual size (e.g. 3 rows,
  /// 3 columns for a freshly loaded 3x3 workbook). Call this whenever a
  /// document is loaded or the active sheet changes, so keyboard
  /// navigation can never move the selection past real data.
  void setSheetBounds({
    required int rowCount,
    required int columnCount,
  }) {
    _maxRow = (rowCount - 1).clamp(0, rowCount <= 0 ? 0 : rowCount - 1);
    _maxColumn = (columnCount - 1).clamp(0, columnCount <= 0 ? 0 : columnCount - 1);

    // Clamp any existing selection into the new bounds so switching to a
    // smaller sheet can't leave a stale out-of-range selection behind.
    final clampedStartRow = _selection.startRow.clamp(0, _maxRow);
    final clampedEndRow = _selection.endRow.clamp(0, _maxRow);
    final clampedStartColumn = _selection.startColumn.clamp(0, _maxColumn);
    final clampedEndColumn = _selection.endColumn.clamp(0, _maxColumn);

    _selection = SelectionModel(
      startRow: clampedStartRow,
      endRow: clampedEndRow,
      startColumn: clampedStartColumn,
      endColumn: clampedEndColumn,
    );

    notifyListeners();
  }

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
    final column = (_selection.endColumn - 1).clamp(0, _maxColumn);

    selectCell(row, column);
  }

  void moveRight() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = (_selection.endColumn + 1).clamp(0, _maxColumn);

    selectCell(row, column);
  }

  void moveUp() {
    _stopEditingWithoutNotify();

    final row = (_selection.endRow - 1).clamp(0, _maxRow);
    final column = _selection.endColumn;

    selectCell(row, column);
  }

  void moveDown() {
    _stopEditingWithoutNotify();

    final row = (_selection.endRow + 1).clamp(0, _maxRow);
    final column = _selection.endColumn;

    selectCell(row, column);
  }

  void extendSelectionLeft() {
    _stopEditingWithoutNotify();

    final row = _selection.endRow;
    final column = (_selection.endColumn - 1).clamp(0, _maxColumn); 

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
    final column = (_selection.endColumn + 1).clamp(0, _maxColumn);

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

    final row = (_selection.endRow - 1).clamp(0, _maxRow);
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

    final row = (_selection.endRow + 1).clamp(0, _maxRow);
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

    if (column < _maxColumn) {
      selectCell(row, column + 1);
      return;
    }

    // Move to the first column of the next row.
    if (row < _maxRow) {
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
      selectCell(row - 1, _maxColumn);
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