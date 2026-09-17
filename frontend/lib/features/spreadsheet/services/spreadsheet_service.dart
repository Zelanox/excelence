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

  Future<void> createDocument() async {}

  Future<void> saveDocument() async {}

  Future<void> closeDocument() async {}

  Future<void> reloadDocument() async {}

  Future<void> search(String query) async {}

  Future<void> clearSearch() async {}

  Future<void> sort() async {}

  Future<void> clearSort() async {}

  Future<void> editCell() async {}

  /// Inserts a new row at [index] (zero-based). If [index] is omitted,
  /// the backend appends the row at the end.
  Future<SpreadsheetData> insertRow({int? index}) {
    return _postEdit(
      '/spreadsheet/rows/insert',
      body: {
        if (index != null) 'index': index,
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
        if (index != null) 'index': index,
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

  Future<void> addSheet() async {}

  Future<void> deleteSheet() async {}

  Future<void> renameSheet() async {}

  Future<void> setActiveSheet() async {}
}