import 'dart:async';

import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/spreadsheet/models/file_action_result.dart';
import 'package:frontend/features/spreadsheet/services/spreadsheet_service.dart';

/// A scripted stand-in for the server-facing service, shared by the File
/// menu tests. Every call it receives is logged in [calls] so tests can
/// check what happened and in which order.

class FakeService extends SpreadsheetService {
  FakeService() : super(ApiClient(baseUrl: 'http://localhost'));

  final List<String> calls = [];

  FileActionResult saveAsResult = const FileActionResult.success(name: 'copy.xlsx');
  FileActionResult renameResult = const FileActionResult.success(name: 'new.xlsx');
  FileActionResult deleteResult = const FileActionResult.success(name: 'book.xlsx');

  /// Opening these names fails with the given error.
  final Map<String, Object> openErrors = {};

  Object? saveError;

  /// When set, renameOpen waits for it (to test two actions overlapping).
  Completer<void>? renameGate;

  /// When set, openDocument waits for it (to test the loading state).
  Completer<void>? openGate;

  @override
  Future<void> openDocument(String filename) async {
    calls.add('open $filename');
    await openGate?.future;
    final error = openErrors[filename];
    if (error != null) throw error;
  }

  @override
  Future<void> closeDocument() async => calls.add('close');

  @override
  Future<SheetsData> sheets() async {
    calls.add('sheets');
    return SheetsData(sheetNames: ['Sheet1'], currentSheet: 'Sheet1');
  }

  @override
  Future<SpreadsheetData> loadData() async {
    calls.add('data');
    return SpreadsheetData(
      headers: ['A'],
      rows: [
        {'A': '1'},
      ],
      rowCount: 1,
      columnCount: 1,
      sheetId: 's1',
      rowIds: ['r1'],
      columnIds: ['c1'],
    );
  }

  @override
  Future<void> saveDocument({bool auto = false}) async {
    calls.add(auto ? 'save auto' : 'save');
    final error = saveError;
    if (error != null) throw error;
  }

  @override
  Future<FileActionResult> saveAs(String newName) async {
    calls.add('saveAs $newName');
    return saveAsResult;
  }

  @override
  Future<FileActionResult> renameOpen(String newName) async {
    calls.add('rename $newName');
    await renameGate?.future;
    return renameResult;
  }

  @override
  Future<FileActionResult> deleteOpen() async {
    calls.add('delete');
    return deleteResult;
  }
}
