import 'package:flutter/foundation.dart';

import '../models/cell_model.dart';
import '../models/row_model.dart';
import '../models/sheet_model.dart';
import '../models/spreadsheet_model.dart';
import '../models/selection_model.dart';
import '../models/viewport_model.dart';

import '../services/spreadsheet_service.dart';

class SpreadsheetController extends ChangeNotifier {
  SpreadsheetController(this._service);

  final SpreadsheetService _service;

  SpreadsheetModel? _spreadsheet;
  SelectionModel _selection = const SelectionModel();
  ViewportModel _viewport = const ViewportModel();

  SpreadsheetModel? get spreadsheet => _spreadsheet;
  SelectionModel get selection => _selection;
  ViewportModel get viewport => _viewport;

  void loadMockData() {
    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: 0,
      sheets: [
        SheetModel(
          name: "Sheet1",
          rows: List.generate(
            100,
            (r) => RowModel(
              index: r,
              cells: List.generate(
                26,
                (c) => CellModel(
                  row: r,
                  column: c,
                  value: "",
                ),
              ),
            ),
          ),
        ),
      ],
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

  void setScroll({
    required double x,
    required double y,
  }) {
    _viewport = ViewportModel(
      scrollX: x,
      scrollY: y,
      zoom: _viewport.zoom,
    );

    notifyListeners();
  }

  void setZoom(double zoom) {
    _viewport = ViewportModel(
      scrollX: _viewport.scrollX,
      scrollY: _viewport.scrollY,
      zoom: zoom,
    );

    notifyListeners();
  }
}