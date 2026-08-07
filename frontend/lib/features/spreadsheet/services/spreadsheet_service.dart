import '../../../core/api/api_client.dart';

class SpreadsheetService {
  SpreadsheetService(this._api);

  final ApiClient _api;

  Future<void> openDocument() async {}

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