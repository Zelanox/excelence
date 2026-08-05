class Endpoints {
  Endpoints._();

  static const documents = "/documents";
  static const spreadsheet = "/spreadsheet";

  static const openDocument = "/documents/open";
  static const saveDocument = "/documents/save";
  static const reloadDocument = "/documents/reload";
  static const closeDocument = "/documents/close";

  static const spreadsheetData = "/spreadsheet/data";
  static const spreadsheetStatus = "/spreadsheet/status";
  static const spreadsheetHeaders = "/spreadsheet/headers";
  static const spreadsheetSheets = "/spreadsheet/sheets";

  static const search = "/spreadsheet/search";
  static const sort = "/spreadsheet/sort";
  static const editCell = "/spreadsheet/edit-cell";
}