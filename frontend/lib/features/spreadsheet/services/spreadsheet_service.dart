import 'dart:convert';

import '../../../core/api/api_client.dart';

class SpreadsheetData {
  SpreadsheetData({
    required this.headers,
    required this.rows,
    required this.rowCount,
    required this.columnCount,
  });

  final List<String> headers;
  final List<Map<String, dynamic>> rows;
  final int rowCount;
  final int columnCount;

  factory SpreadsheetData.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'] as List<dynamic>? ?? [];
    final rawRows = json['rows'] as List<dynamic>? ?? [];

    return SpreadsheetData(
      headers: rawHeaders.map((header) => header.toString()).toList(),
      rows: rawRows
          .whereType<Map<String, dynamic>>()
          .toList(),
      rowCount: json['row_count'] as int? ?? 0,
      columnCount: json['column_count'] as int? ?? 0,
    );
  }
}

/// The response shape for every sheet-management endpoint (switch, add,
/// delete, rename) - deliberately lighter than [SpreadsheetData]. These
/// endpoints only report which worksheets exist and which is now active;
/// they never include grid data (headers/rows), so switching sheets
/// always needs a separate loadData() call to fetch the newly-active
/// sheet's actual content.
class SheetsData {
  SheetsData({
    required this.sheetNames,
    required this.currentSheet,
  });

  final List<String> sheetNames;
  final String currentSheet;

  factory SheetsData.fromJson(Map<String, dynamic> json) {
    final rawSheets = json['sheets'] as List<dynamic>? ?? [];

    return SheetsData(
      sheetNames: rawSheets.map((name) => name.toString()).toList(),
      currentSheet: json['current_sheet']?.toString() ?? '',
    );
  }
}

/// One level of the server-side documents tree, as returned by
/// GET /documents/browse - the subfolders and .xlsx files sitting
/// directly inside [folder] (not recursive). Powers the file-explorer
/// dialog's navigation; [folder] echoes back the path that was browsed
/// so the dialog can update its breadcrumb after a navigation call.
class FolderEntries {
  FolderEntries({
    required this.folder,
    required this.folders,
    required this.documents,
  });

  final String folder;
  final List<String> folders;
  final List<String> documents;

  factory FolderEntries.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'] as List<dynamic>? ?? [];
    final rawDocuments = json['documents'] as List<dynamic>? ?? [];

    return FolderEntries(
      folder: json['folder']?.toString() ?? '',
      folders: rawFolders.map((name) => name.toString()).toList(),
      documents: rawDocuments.map((name) => name.toString()).toList(),
    );
  }
}

class SpreadsheetService {
  SpreadsheetService(this._api);

  final ApiClient _api;

  Future<void> openDocument(String filename) async {
    final response = await _api.post(
      '/documents/open',
      body: {
        'filename': filename,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to open document: '
        '${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : 'Failed to open document.',
      );
    }
  }

  Future<void> createDocument(String filename) async {
    final response = await _api.post(
      '/documents/create',
      body: {
        'filename': filename,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to create document: '
        '${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : 'Failed to create document.',
      );
    }
  }

  /// Lists the subfolders and .xlsx files directly inside [folder] (a
  /// path relative to the backend's documents root; empty string means
  /// the root itself) - powers the file-explorer dialog's navigation.
  Future<FolderEntries> browseFolder(String folder) async {
    final response = await _api.get(
      '/documents/browse?path=${Uri.encodeQueryComponent(folder)}',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to browse folder: '
        '${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : 'Failed to browse folder.',
      );
    }

    return FolderEntries.fromJson(json);
  }

  Future<SpreadsheetData> loadData() async {
    final response = await _api.get('/spreadsheet/data');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to load spreadsheet data: '
        '${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : 'Failed to load spreadsheet data.',
      );
    }

    return SpreadsheetData.fromJson(json);
  }

  /// Fetches the workbook's available worksheet names and which one is
  /// currently active. Read-only - unlike setActiveSheet/addSheet/etc,
  /// this never changes anything server-side.
  Future<SheetsData> sheets() async {
    final response = await _api.get('/spreadsheet/sheets');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to load sheet list: '
        '${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : 'Failed to load sheet list.',
      );
    }

    return SheetsData.fromJson(json);
  }

  /// Shared POST + response handling for the row/column edit endpoints,
  /// which all return the same SpreadsheetEditResponse shape (success,
  /// message, headers, rows, row_count, column_count) after applying
  /// their change.
  Future<SpreadsheetData> _postEdit(
    String endpoint, {
    required Map<String, dynamic> body,
    required String failureMessage,
  }) async {
    final response = await _api.post(endpoint, body: body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '$failureMessage: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : failureMessage,
      );
    }

    return SpreadsheetData.fromJson(json);
  }

  /// Shared POST + response handling for the sheet-management endpoints
  /// (switch/add/delete/rename), which all return the same lighter
  /// SheetsData shape (success, message, sheets, current_sheet) - no grid
  /// data, unlike _postEdit's SpreadsheetEditResponse.
  Future<SheetsData> _postSheets(
    String endpoint, {
    required Map<String, dynamic> body,
    required String failureMessage,
  }) async {
    final response = await _api.post(endpoint, body: body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '$failureMessage: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : failureMessage,
      );
    }

    return SheetsData.fromJson(json);
  }

  Future<void> saveDocument() async {
    final response = await _api.post('/documents/save');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to save document: '
        '${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception(
        json['message']?.toString().isNotEmpty == true
            ? json['message'].toString()
            : 'Failed to save document.',
      );
    }
  }

  Future<void> closeDocument() async {}

  Future<void> reloadDocument() async {}

  /// Filters the active worksheet's visible rows to those matching
  /// [query]. Row-filtering search, not cell highlighting - matching rows
  /// stay, everything else drops out of the response until cleared.
  Future<SpreadsheetData> search(String query) {
    return _postEdit(
      '/spreadsheet/search',
      body: {'text': query},
      failureMessage: 'Failed to search',
    );
  }

  /// Clears the active search filter, restoring every row.
  Future<SpreadsheetData> clearSearch() {
    return _postEdit(
      '/spreadsheet/search/clear',
      body: const {},
      failureMessage: 'Failed to clear search',
    );
  }

  /// Sorts the active worksheet's visible rows by a single column - the
  /// backend supports multi-level sort (a list of {column, ascending}
  /// rules), but the header-click UI only ever drives one rule at a time,
  /// so this wraps that as a single-rule list rather than exposing the
  /// full multi-level shape to callers that don't need it.
  Future<SpreadsheetData> sort({
    required String column,
    required bool ascending,
  }) {
    return _postEdit(
      '/spreadsheet/sort',
      body: {
        'rules': [
          {'column': column, 'ascending': ascending},
        ],
      },
      failureMessage: 'Failed to sort',
    );
  }

  /// Clears the active sort, restoring the sheet's natural row order.
  Future<SpreadsheetData> clearSort() {
    return _postEdit(
      '/spreadsheet/sort/clear',
      body: const {},
      failureMessage: 'Failed to clear sort',
    );
  }

  /// Persists a single cell edit to the backend. The response's fresh
  /// grid data is intentionally discarded here (see
  /// [SpreadsheetController._persistCellEdits]) - callers only care
  /// whether the save succeeded, not the echoed sheet snapshot.
  Future<void> editCell({
    required int row,
    required int column,
    required String value,
  }) {
    return _postEdit(
      '/spreadsheet/edit-cell',
      body: {
        'row': row,
        'column': column,
        'value': value,
      },
      failureMessage: 'Failed to save cell edit',
    );
  }

  /// Inserts a new row at [index] (zero-based). If [index] is omitted,
  /// the backend appends the row at the end.
  Future<SpreadsheetData> insertRow({int? index}) {
    return _postEdit(
      '/spreadsheet/rows/insert',
      body: {
        'index': ?index,
      },
      failureMessage: 'Failed to insert row',
    );
  }

  /// Deletes the row at [index] (zero-based).
  Future<SpreadsheetData> deleteRow({required int index}) {
    return _postEdit(
      '/spreadsheet/rows/delete',
      body: {'index': index},
      failureMessage: 'Failed to delete row',
    );
  }

  /// Inserts a new column named [name] at [index] (zero-based). If
  /// [index] is omitted, the backend appends the column at the end.
  Future<SpreadsheetData> insertColumn({
    required String name,
    int? index,
  }) {
    return _postEdit(
      '/spreadsheet/columns/insert',
      body: {
        'name': name,
        'index': ?index,
      },
      failureMessage: 'Failed to insert column',
    );
  }

  /// Deletes the column named [name]. The backend identifies columns by
  /// their header name, not by letter/index.
  Future<SpreadsheetData> deleteColumn({required String name}) {
    return _postEdit(
      '/spreadsheet/columns/delete',
      body: {'name': name},
      failureMessage: 'Failed to delete column',
    );
  }

  /// Renames the column currently named [oldName] to [newName]. The
  /// backend rejects this (success: false) if [oldName] doesn't exist, if
  /// [newName] is blank, or if [newName] collides with another existing
  /// header.
  Future<SpreadsheetData> renameColumn({
    required String oldName,
    required String newName,
  }) {
    return _postEdit(
      '/spreadsheet/columns/rename',
      body: {'old_name': oldName, 'new_name': newName},
      failureMessage: 'Failed to rename column',
    );
  }

  /// Switches the active worksheet to [sheetName]. Callers must follow
  /// this with loadData() to fetch the newly-active sheet's actual grid
  /// content - this call alone only updates which sheet is active.
  Future<SheetsData> setActiveSheet(String sheetName) {
    return _postSheets(
      '/spreadsheet/sheet',
      body: {'sheet_name': sheetName},
      failureMessage: 'Failed to switch sheet',
    );
  }

  /// Creates a new worksheet named [name] and makes it active. Like
  /// [setActiveSheet], callers must follow this with loadData() to fetch
  /// the new (empty) sheet's grid content.
  Future<SheetsData> addSheet(String name) {
    return _postSheets(
      '/spreadsheet/sheets/add',
      body: {'name': name},
      failureMessage: 'Failed to add sheet',
    );
  }

  /// Deletes the worksheet named [name]. The backend refuses (success:
  /// false) to delete the last remaining sheet in a workbook - a workbook
  /// must always have at least one sheet.
  Future<SheetsData> deleteSheet(String name) {
    return _postSheets(
      '/spreadsheet/sheets/delete',
      body: {'name': name},
      failureMessage: 'Failed to delete sheet',
    );
  }

  /// Renames the worksheet currently named [oldName] to [newName].
  /// Renaming does not change which sheet is active.
  Future<SheetsData> renameSheet({
    required String oldName,
    required String newName,
  }) {
    return _postSheets(
      '/spreadsheet/sheets/rename',
      body: {'old_name': oldName, 'new_name': newName},
      failureMessage: 'Failed to rename sheet',
    );
  }
}