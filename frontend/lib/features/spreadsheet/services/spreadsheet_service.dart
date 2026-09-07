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

  Future<void> createDocument() async {}

  Future<void> saveDocument() async {}

  Future<void> closeDocument() async {}

  Future<void> reloadDocument() async {}

  Future<void> search(String query) async {}

  Future<void> clearSearch() async {}

  Future<void> sort() async {}

  Future<void> clearSort() async {}

  Future<void> editCell() async {}

  Future<void> insertRow() async {}

  Future<void> deleteRow() async {}

  Future<void> insertColumn() async {}

  Future<void> deleteColumn() async {}

  Future<void> addSheet() async {}

  Future<void> deleteSheet() async {}

  Future<void> renameSheet() async {}

  Future<void> setActiveSheet() async {}
}