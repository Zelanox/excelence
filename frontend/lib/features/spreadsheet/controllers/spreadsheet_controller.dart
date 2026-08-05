import '../services/spreadsheet_service.dart';

class SpreadsheetController {
  SpreadsheetController(this._service);

  final SpreadsheetService _service;

  Future<void> loadSpreadsheet() {
    return _service.loadSpreadsheet();
  }

  Future<void> saveSpreadsheet() {
    return _service.saveSpreadsheet();
  }

  Future<void> search(String query) {
    return _service.search(query);
  }

  Future<void> sort() {
    return _service.sort();
  }

  Future<void> editCell() {
    return _service.editCell();
  }
}