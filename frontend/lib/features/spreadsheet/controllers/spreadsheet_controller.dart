import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/preferences/app_preferences.dart';
import '../models/cell_model.dart';
import '../models/row_model.dart';
import '../models/sheet_model.dart';
import '../models/spreadsheet_model.dart';
import '../models/selection_model.dart';
import '../models/sheet_appearance.dart';
import '../models/sheet_view.dart';
import '../models/text_style_spec.dart';

import '../services/spreadsheet_service.dart';
import '../services/formula_engine.dart';
import '../services/formula_dependency_graph.dart';

class SpreadsheetController extends ChangeNotifier {
  SpreadsheetController(
    this._service, {
    AppPreferences preferences = const AppPreferences(),
  }) : _preferences = preferences;

  final SpreadsheetService _service;
  final AppPreferences _preferences;
  final FormulaEngine _formulaEngine = const FormulaEngine();

  SpreadsheetModel? _spreadsheet;
  final List<SpreadsheetModel> _undoStack = [];
  final List<SpreadsheetModel> _redoStack = [];

  // Tracks cell-edit/paste saves that have been fired at the backend but
  // haven't landed yet (see _persistCellEdits). Anything that's about to
  // replace the sheet with a fresh full-sheet response from the backend
  // (insert/delete row or column, search, sort, switch sheet) must wait
  // for these first via _flushPendingSaves() - otherwise a save that's
  // still in flight can land AFTER that refresh applies, and the refresh
  // itself reflects the backend's still-unedited state, silently
  // reverting the user's just-made edit. This is what "my edit
  // disappeared after I did something else" looks like from the outside.
  final Set<Future<void>> _pendingSaves = {};

  /// Waits for every in-flight cell-edit/paste save to finish before
  /// proceeding. Call this before any operation that's about to fetch a
  /// fresh full-sheet snapshot from the backend and replace the local
  /// model with it.
  Future<void> _flushPendingSaves() async {
    if (_pendingSaves.isEmpty) {
      return;
    }
    // Copy first - awaiting can let new saves be added to _pendingSaves
    // while this wait is in progress, and iterating the live set while
    // it mutates is unsafe.
    await Future.wait(List<Future<void>>.of(_pendingSaves));
  }

  SpreadsheetModel? get spreadsheet => _spreadsheet;

  // This client's view of the active sheet - the search filter and the
  // single-column sort - lives on the sheet itself (see SheetView), so it is
  // per sheet and is never shared with, or saved for, anyone else. These
  // getters let GridColumnHeader show its sort indicator and the search bar
  // show its text without each keeping a separate source of truth.

  /// The column the active sheet is sorted by, or null. A sort on a column
  /// that has since been deleted or renamed counts as no sort.
  String? get sortedColumn {
    final sheet = _spreadsheet?.activeSheet;
    final column = sheet?.view.sortColumn;

    return column != null && sheet!.headers.contains(column) ? column : null;
  }

  bool get sortAscending => _spreadsheet?.activeSheet.view.sortAscending ?? true;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Whether a background save (any fire-and-forget persist added to
  /// _pendingSaves - column width, RTL, cell edits, etc.) is currently
  /// in flight. Exposed for the status bar's "Saving..." / "Ready"
  /// indicator; _pendingSaves itself stays private since callers should
  /// only ever need to know THAT something is pending, never the
  /// individual futures in it.
  bool get isSaving => _pendingSaves.isNotEmpty;

  // ============================================================
  // Ordered backend writes + autosave
  // ============================================================

  // Every backend write that changes the document (cell edits, formatting,
  // undo/redo, autosave itself) runs through ONE queue, strictly in the
  // order the user made them. Without it the requests race: a quick
  // "edit, then Ctrl+Z" could reach the server undo-first, and an
  // autosave could be written before the edits it was meant to include.
  Future<void> _writeQueueTail = Future<void>.value();

  Timer? _autosaveTimer;
  bool _hasUnsavedChanges = false;

  /// The text of the active search filter ('' when none). It is part of
  /// the sheet's view rather than only the search bar's text field, so a
  /// search started from elsewhere - e.g. after adding a row - shows up in
  /// the search box too.
  String get searchQuery => _spreadsheet?.activeSheet.view.searchQuery ?? '';

  /// True while the open document has changes that haven't been written
  /// to disk yet (they're about to be, by autosave).
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  /// How long after the last change autosave waits - long enough that a
  /// burst of typing becomes one save, short enough to lose almost
  /// nothing if the tab is closed.
  static const Duration _autosaveDelay = Duration(milliseconds: 1500);

  /// How long to wait before retrying after an autosave fails (e.g. the
  /// backend was briefly unreachable).
  static const Duration _autosaveRetryDelay = Duration(seconds: 10);

  /// Runs [job] after every earlier queued write has finished.
  ///
  /// A failure is reported through [lastSaveError]. For a write that
  /// changes the document ([resyncOnFailure], the default) the local grid
  /// and the backend may now disagree - the backend rejected something
  /// the grid already shows - so the grid is reloaded from the backend
  /// and local undo history is dropped, rather than leaving the user
  /// looking at changes that were never saved.
  void _enqueueBackendWrite({
    required String errorPrefix,
    required Future<void> Function() job,
    bool markDirty = true,
    bool resyncOnFailure = true,
    VoidCallback? onFailure,
  }) {
    late final Future<void> save;
    save = _writeQueueTail.then((_) => job()).then((_) {}, onError: (Object error) {
      debugPrint('[SpreadsheetController] $errorPrefix: $error');
      _lastSaveError = '$errorPrefix: $error';
      notifyListeners();
      onFailure?.call();

      if (resyncOnFailure) {
        unawaited(_resyncFromBackend());
      }
    }).whenComplete(() {
      _pendingSaves.remove(save);
    });

    _writeQueueTail = save;
    _pendingSaves.add(save);

    if (markDirty) {
      _markDirty();
    }
  }

  /// Notes that the document changed and (re)starts the autosave timer.
  void _markDirty() {
    _hasUnsavedChanges = true;
    _scheduleAutosave(_autosaveDelay);
  }

  void _scheduleAutosave(Duration delay) {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(delay, _runAutosave);
  }

  /// Writes the document to disk now, queued behind every pending edit.
  void _runAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    if (!_hasUnsavedChanges || _spreadsheet == null) {
      return;
    }

    // Cleared BEFORE the save so a change made while it's in flight sets
    // the flag again and gets its own save afterwards.
    _hasUnsavedChanges = false;
    notifyListeners();

    _enqueueBackendWrite(
      errorPrefix: 'Autosave failed',
      markDirty: false,
      resyncOnFailure: false,
      onFailure: () {
        _hasUnsavedChanges = true;
        _scheduleAutosave(_autosaveRetryDelay);
      },
      job: () async {
        await _service.saveDocument();
      },
    );
  }

  /// Saves any unsaved changes immediately instead of waiting for the
  /// autosave timer, and waits for every pending write to finish. Called
  /// when the app loses focus / is being hidden, and before another
  /// document is opened (which would otherwise discard the changes).
  Future<void> flushPendingChanges() async {
    _runAutosave();
    await _flushPendingSaves();
  }

  /// Reloads the active sheet from the backend after a write failed, so
  /// the grid shows what is really saved. Best effort: if the backend
  /// can't be reached the grid is left as it is.
  Future<void> _resyncFromBackend() async {
    if (_spreadsheet == null) {
      return;
    }

    try {
      // Let everything already queued settle first - it may be about to
      // change what the backend holds.
      await _flushPendingSaves();
      final data = await _service.loadData();
      _replaceActiveSheet(data);
      _undoStack.clear();
      _redoStack.clear();
      notifyListeners();
    } catch (error) {
      debugPrint('[SpreadsheetController] Resync failed: $error');
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // Backend data
  // ============================================================

  Future<void> loadDocument(String filename) async {
    try {
      // Opening replaces the backend's current document, so anything not
      // yet written to disk would be lost - save it first.
      await flushPendingChanges();

      // Leave the document we were in (if any) before joining another, so
      // the server can release it once nobody is left. Opening the SAME
      // document again therefore reloads it from disk, as it always did.
      await _service.closeDocument();

      // 1. Ask the backend to open the workbook.
      await _service.openDocument(filename);

      // 2. Retrieve the real worksheet list and active sheet name -
      // previously this was hardcoded to 'Sheet1' locally, which only
      // happened to work because every test workbook so far had exactly
      // one sheet named that.
      final sheetsData = await _service.sheets();

      // 3. Retrieve the active sheet's grid data.
      final data = await _service.loadData();

      // 4. Convert API data into our Flutter spreadsheet model.
      _spreadsheet = SpreadsheetModel(
        activeSheetIndex: 0,
        sheets: [
          _sheetFromApiData(name: sheetsData.currentSheet, data: data),
        ],
        availableSheetNames: sheetsData.sheetNames,
      );

      // A newly loaded workbook has no local undo/redo history, and
      // nothing unsaved.
      _undoStack.clear();
      _redoStack.clear();
      _autosaveTimer?.cancel();
      _hasUnsavedChanges = false;

      // Remember this as the document to reopen automatically next
      // launch. Fire-and-forget: a failure to persist this shouldn't
      // block the document that DID successfully load from displaying,
      // and there's nothing actionable for the user to do about it.
      unawaited(_preferences.setLastOpenedDocument(filename));

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        '[SpreadsheetController.loadDocument] Error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      rethrow;
    }
  }

  /// Creates a new workbook at [filename] (relative to the backend's
  /// documents root) on the server, then loads it the same way
  /// loadDocument does - a freshly created workbook still needs its
  /// (seeded, 1x1) grid data and sheet list fetched, it isn't returned
  /// inline by the create call itself.
  Future<void> newDocument(String filename) async {
    try {
      // Creating replaces the backend's current document - save any
      // unsaved changes in it first (loadDocument's own flush would come
      // too late, after the create).
      await flushPendingChanges();
      await _service.createDocument(filename);
      await loadDocument(filename);
    } catch (error, stackTrace) {
      debugPrint(
        '[SpreadsheetController.newDocument] Error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      rethrow;
    }
  }

  /// Persists the active workbook to disk. Doesn't touch the local grid
  /// model - the backend saves exactly what it already has in memory
  /// (which is already kept current by every edit/insert/delete this
  /// controller makes), so there's nothing here to re-fetch or
  /// re-render. Failures propagate to the caller to surface to the user;
  /// _lastSaveError isn't used here since that's reserved for the
  /// fire-and-forget cell-edit path (_persistCellEdits), not an
  /// explicit, awaited user action like Save.
  Future<void> saveDocument() async {
    try {
      // Edits are sent to the backend in the background; make sure they
      // have all landed before asking it to write the file.
      await _flushPendingSaves();
      _autosaveTimer?.cancel();
      _hasUnsavedChanges = false;
      await _service.saveDocument();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        '[SpreadsheetController.saveDocument] Error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      rethrow;
    }
  }

  /// Uploads [bytes] (an already-complete .xlsx picked from the user's
  /// device) to the backend's documents root under [filename]. Doesn't
  /// open it as the active document or touch _spreadsheet/notify
  /// listeners - the file explorer dialog calls this purely to get the
  /// bytes onto the server, then re-browses its current folder to show
  /// the newly uploaded file (which always lands at the root, so a
  /// re-browse only shows it immediately if the dialog is already
  /// looking at the root).
  Future<void> uploadDocument(String filename, List<int> bytes) async {
    try {
      await _service.uploadDocument(filename, bytes);
    } catch (error, stackTrace) {
      debugPrint(
        '[SpreadsheetController.uploadDocument] Error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      rethrow;
    }
  }

  /// Lists the subfolders and .xlsx files directly inside [folder] (a
  /// path relative to the backend's documents root; empty string means
  /// the root) - read-only, purely for the file-explorer dialog to
  /// render a folder's contents. Doesn't touch _spreadsheet or notify
  /// listeners, since browsing available files has nothing to do with
  /// the currently-open document.
  Future<FolderEntries> browseFolder(String folder) {
    return _service.browseFolder(folder);
  }

  /// Converts a raw API [SpreadsheetData] response into a [SheetModel] of
  /// canonical rows with no view applied. Shared by loadDocument and every
  /// row/column mutation (insert/delete), since each of those endpoints
  /// returns the same shape - the sheet's full refreshed data - after
  /// applying its change.
  SheetModel _sheetFromApiData({
    required String name,
    required SpreadsheetData data,
  }) {
    final rows = <RowModel>[];

    // Per-cell style overrides, looked up by (row, column) as cells are
    // built below.
    final stylesByCell = <(int, int), TextStyleSpec>{
      for (final entry in data.cellStyles)
        (entry.row, entry.column): entry.style,
    };

    for (int rowIndex = 0; rowIndex < data.rows.length; rowIndex++) {
      final apiRow = data.rows[rowIndex];

      final cells = <CellModel>[];

      for (int columnIndex = 0;
          columnIndex < data.headers.length;
          columnIndex++) {
        final header = data.headers[columnIndex];

        final rawValue = apiRow[header];
        final text = rawValue?.toString() ?? '';

        // The server stores a cell's INPUT as typed, so a formula arrives as
        // its text ("=A1+A2"). It becomes a formula cell here, and its
        // value is filled in below once every cell exists (a formula can
        // refer to cells further down or to other formulas).
        final isFormula = _isFormula(text);

        cells.add(
          CellModel(
            row: rowIndex,
            column: columnIndex,
            value: isFormula ? '' : text,
            formula: isFormula ? text : null,
            style: stylesByCell[(rowIndex, columnIndex)] ??
                TextStyleSpec.empty,
          ),
        );
      }

      rows.add(
        RowModel(
          index: rowIndex,
          cells: cells,
        ),
      );
    }

    // The backend returns the CANONICAL data (it no longer sorts or
    // filters for this client), so these rows are the sheet's allRows and
    // row r of the response is row r of the data. The caller applies this
    // client's view (see _replaceActiveSheet).
    return _evaluateLoadedFormulas(
      SheetModel(
        name: name,
        allRows: rows,
        headers: data.headers,
        columnWidths: data.columnWidths,
        isRtl: data.isRtl,
        textDefaults: data.textDefaults,
        appearance: data.appearance,
      ),
    );
  }

  /// Fills in the value of every formula cell of a freshly loaded [sheet].
  ///
  /// Formulas are stored as text and never as results, so after every load
  /// (and every refresh from the server) each client works the results out
  /// for itself with the same engine - which is what makes everyone see the
  /// same numbers. The engine resolves a formula's references recursively,
  /// so the order the cells are evaluated in doesn't matter.
  SheetModel _evaluateLoadedFormulas(SheetModel sheet) {
    final probe = SpreadsheetModel(
      activeSheetIndex: 0,
      sheets: [sheet],
      availableSheetNames: [sheet.name],
    );

    final replacements = <int, RowModel>{};

    for (final row in sheet.allRows) {
      List<CellModel>? updatedCells;

      for (int column = 0; column < row.cells.length; column++) {
        final cell = row.cells[column];
        final formula = cell.formula;

        if (formula == null) {
          continue;
        }

        updatedCells ??= List<CellModel>.from(row.cells);
        updatedCells[column] = cell.copyWith(
          value: _formulaEngine.evaluate(formula, probe),
        );
      }

      if (updatedCells != null) {
        replacements[row.index] = RowModel(index: row.index, cells: updatedCells);
      }
    }

    return sheet.withSourceRows(replacements);
  }

  // ============================================================
  // Sheets
  // ============================================================

  /// Switches to the worksheet named [sheetName] and loads its data.
  /// Clears undo/redo history, same as loadDocument - the stack holds
  /// snapshots scoped to whichever sheet was active when each snapshot
  /// was taken, so carrying it across a sheet switch would let undo
  /// restore a different sheet's data under the new sheet's identity.
  Future<void> switchSheet(String sheetName) async {
    if (_spreadsheet?.activeSheet.name == sheetName) {
      return;
    }

    try {
      await _flushPendingSaves();
      final sheetsData = await _service.setActiveSheet(sheetName);
      final data = await _service.loadData();

      _spreadsheet = SpreadsheetModel(
        activeSheetIndex: 0,
        sheets: [
          _sheetFromApiData(name: sheetsData.currentSheet, data: data),
        ],
        availableSheetNames: sheetsData.sheetNames,
      );

      // A freshly loaded sheet starts with no search or sort.
      _undoStack.clear();
      _redoStack.clear();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.switchSheet] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Creates a new worksheet named [name] and switches to it. Like
  /// [switchSheet], this clears undo/redo history and any active sort.
  Future<void> addSheet(String name) async {
    try {
      await _flushPendingSaves();
      final sheetsData = await _service.addSheet(name);
      _markDirty();
      final data = await _service.loadData();

      _spreadsheet = SpreadsheetModel(
        activeSheetIndex: 0,
        sheets: [
          _sheetFromApiData(name: sheetsData.currentSheet, data: data),
        ],
        availableSheetNames: sheetsData.sheetNames,
      );

      // A freshly loaded sheet starts with no search or sort.
      _undoStack.clear();
      _redoStack.clear();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.addSheet] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Deletes the worksheet named [name]. The backend refuses to delete a
  /// workbook's last remaining sheet (the call fails rather than leaving
  /// zero sheets); this surfaces that failure as a thrown exception, same
  /// as every other mutation here.
  ///
  /// If the deleted sheet was the active one, the backend has already
  /// switched to a remaining sheet - this fetches THAT sheet's data
  /// rather than assuming which one it landed on.
  Future<void> deleteSheet(String name) async {
    try {
      await _flushPendingSaves();
      final sheetsData = await _service.deleteSheet(name);
      _markDirty();
      final data = await _service.loadData();

      _spreadsheet = SpreadsheetModel(
        activeSheetIndex: 0,
        sheets: [
          _sheetFromApiData(name: sheetsData.currentSheet, data: data),
        ],
        availableSheetNames: sheetsData.sheetNames,
      );

      // A freshly loaded sheet starts with no search or sort.
      _undoStack.clear();
      _redoStack.clear();

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.deleteSheet] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Renames the worksheet currently named [oldName] to [newName].
  /// Renaming doesn't change which sheet is active or its data, so this
  /// only needs to refresh the sheet name/tab list - no data reload, no
  /// undo/redo reset.
  Future<void> renameSheet({
    required String oldName,
    required String newName,
  }) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    try {
      final sheetsData = await _service.renameSheet(
        oldName: oldName,
        newName: newName,
      );
      _markDirty();

      final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
      final activeSheet = currentSpreadsheet.sheets[activeSheetIndex];

      final renamedActiveSheet = activeSheet.name == oldName
          ? activeSheet.copyWith(name: sheetsData.currentSheet)
          : activeSheet;

      final updatedSheets = List<SheetModel>.of(currentSpreadsheet.sheets);
      updatedSheets[activeSheetIndex] = renamedActiveSheet;

      _spreadsheet = SpreadsheetModel(
        activeSheetIndex: activeSheetIndex,
        sheets: updatedSheets,
        availableSheetNames: sheetsData.sheetNames,
      );

      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.renameSheet] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============================================================
  // Rows and columns
  // ============================================================

  /// Inserts a new row at [index] (zero-based), pushing existing rows at
  /// and after that index down by one. Refreshes the active sheet from
  /// the backend's response rather than reconstructing it locally, since
  /// the backend is the source of truth for how the insertion actually
  /// landed (e.g. formula adjustments it may perform).
  ///
  /// [index] is a row of the grid as SHOWN; the server is told the real
  /// (canonical) row it stands for. A row number one past the last shown
  /// row means "at the end of the data".
  Future<void> insertRow({required int index}) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    final sheet = currentSpreadsheet.activeSheet;
    final canonicalIndex = index >= 0 && index < sheet.rows.length
        ? sheet.sourceRowOf(index)
        : (index == sheet.rows.length ? sheet.allRows.length : index);

    _recordHistoryPoint();

    try {
      await _flushPendingSaves();
      final data = await _service.insertRow(index: canonicalIndex);
      _markDirty();
      _replaceActiveSheet(data);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.insertRow] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Undo the speculative history point since nothing actually
      // changed - there's no new state to redo back to.
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      rethrow;
    }
  }

  /// Adds a row at the end of the data with [value] in its first column
  /// (empty [value]: a blank row), as one undoable step.
  ///
  /// This is a single backend operation rather than "insert a row, then
  /// edit the last row": with a sort or filter active the new row is not
  /// necessarily the last VISIBLE row (an empty row can sort anywhere, and
  /// a filter can hide it), so it could not be addressed by row number
  /// afterwards. The grid is refreshed from the backend's response, so the
  /// current sort/filter stays applied.
  Future<void> appendRowWithFirstColumnValue(String value) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    _recordHistoryPoint();

    try {
      await _flushPendingSaves();
      final data = await _service.appendRow(value);
      _markDirty();
      _replaceActiveSheet(data);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.appendRow] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      rethrow;
    }
  }

  /// Deletes the row at [index], a row of the grid as SHOWN (zero-based).
  /// The server is told which real (canonical) row that is, so with a sort
  /// or filter in place the row on screen is the one that goes.
  Future<void> deleteRow({required int index}) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    final sheet = currentSpreadsheet.activeSheet;
    final canonicalIndex = index >= 0 && index < sheet.rows.length
        ? sheet.sourceRowOf(index)
        : index;

    _recordHistoryPoint();

    try {
      await _flushPendingSaves();
      final data = await _service.deleteRow(index: canonicalIndex);
      _markDirty();
      _replaceActiveSheet(data);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.deleteRow] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      rethrow;
    }
  }

  /// Inserts a new column named [name] at [index] (zero-based).
  Future<void> insertColumn({required String name, required int index}) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    _recordHistoryPoint();

    try {
      await _flushPendingSaves();
      final data = await _service.insertColumn(name: name, index: index);
      _markDirty();
      _replaceActiveSheet(data);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.insertColumn] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      rethrow;
    }
  }

  /// Deletes the column named [name]. The backend identifies columns by
  /// header name, not by letter/index - callers should look up the
  /// current header name for the column they mean to delete (see
  /// SheetModel.headers) before calling this.
  Future<void> deleteColumn({required String name}) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    _recordHistoryPoint();

    try {
      await _flushPendingSaves();
      final data = await _service.deleteColumn(name: name);
      _markDirty();
      _replaceActiveSheet(data);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.deleteColumn] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      rethrow;
    }
  }

  /// Renames the column currently named [oldName] to [newName]. Like the
  /// other row/column mutations, this refreshes the active sheet from the
  /// backend's response rather than reconstructing it locally.
  Future<void> renameColumn({
    required String oldName,
    required String newName,
  }) async {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    _recordHistoryPoint();

    try {
      await _flushPendingSaves();
      final data = await _service.renameColumn(
        oldName: oldName,
        newName: newName,
      );
      _markDirty();
      _replaceActiveSheet(data);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[SpreadsheetController.renameColumn] Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      rethrow;
    }
  }

  /// Applies width [width] to column [name] in local state only, with no
  /// backend call - used while a resize drag is in progress so the
  /// column visibly follows the pointer every frame without firing a
  /// network request per frame. Call [setColumnWidth] once, from the
  /// drag's end, to actually persist the final width.
  void setColumnWidthLocal({required String name, required double width}) {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final activeSheet = currentSpreadsheet.sheets[activeSheetIndex];

    if (!activeSheet.headers.contains(name)) {
      return;
    }

    final updatedWidths = Map<String, double>.from(activeSheet.columnWidths);
    updatedWidths[name] = width;

    final updatedSheet = activeSheet.copyWith(columnWidths: updatedWidths);

    final updatedSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    updatedSheets[activeSheetIndex] = updatedSheet;

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: activeSheetIndex,
      sheets: updatedSheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    notifyListeners();
  }

  /// Sets column [name]'s display width to [width] and persists it to
  /// the backend in the background - call once, when a resize gesture
  /// ends (not on every drag-move frame; use [setColumnWidthLocal] for
  /// that). Applies the same local update setColumnWidthLocal does, so
  /// it's also safe to call directly for a non-drag resize (e.g. a
  /// future "fit to content" action) without calling both.
  ///
  /// Deliberately fire-and-forget like [_persistCellEdits], unlike
  /// renameColumn/deleteColumn/etc: a resize is a drag gesture the user
  /// expects to feel instant, and unlike those structural edits there's
  /// no local reconstruction risk here - the width map is the only thing
  /// changing, nothing about row/cell data is derived from it. Also
  /// unlike those edits, this does NOT call _recordHistoryPoint - a
  /// column width is view/layout state, not a document edit the user
  /// should be able to Ctrl+Z, the same reasoning [search]/[sort] use.
  /// On a persistence failure, the local width is left as-is (reverting
  /// it would undo a gesture the user already completed and moved on
  /// from) and the failure is surfaced the same way [_persistCellEdits]
  /// does, via [lastSaveError].
  void setColumnWidth({required String name, required double width}) {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    if (!currentSpreadsheet.activeSheet.headers.contains(name)) {
      return;
    }

    setColumnWidthLocal(name: name, width: width);

    late final Future<void> save;
    save = _service
        .setColumnWidth(name: name, width: width)
        .then((_) {}, onError: (Object error) {
      debugPrint('[SpreadsheetController.setColumnWidth] Save failed: $error');
      _lastSaveError = 'Failed to save column width: $error';
      notifyListeners();
    }).whenComplete(() {
      _pendingSaves.remove(save);
    });

    _pendingSaves.add(save);
    _markDirty();
  }

  /// Sets the active sheet's right-to-left direction, applied locally
  /// immediately and persisted to the backend in the background - same
  /// shape as [setColumnWidth]: optimistic, fire-and-forget, no
  /// [_recordHistoryPoint] entry (a direction toggle is view/layout
  /// state, not a document edit the user should be able to Ctrl+Z, the
  /// same reasoning search/sort/setColumnWidth use). On a persistence
  /// failure the local flag is left as-is and the failure surfaces via
  /// [lastSaveError], same as setColumnWidth.
  void setRtl(bool rtl) {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final activeSheet = currentSpreadsheet.sheets[activeSheetIndex];

    final updatedSheet = activeSheet.copyWith(isRtl: rtl);

    final updatedSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    updatedSheets[activeSheetIndex] = updatedSheet;

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: activeSheetIndex,
      sheets: updatedSheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    notifyListeners();

    late final Future<void> save;
    save = _service.setRtl(rtl: rtl).then((_) {}, onError: (Object error) {
      debugPrint('[SpreadsheetController.setRtl] Save failed: $error');
      _lastSaveError = 'Failed to save sheet direction: $error';
      notifyListeners();
    }).whenComplete(() {
      _pendingSaves.remove(save);
    });

    _pendingSaves.add(save);
    _markDirty();
  }

  // ============================================================
  // Text styles
  // ============================================================

  /// The style the cell at ([row], [column]) is actually drawn with: its
  /// own overrides merged over the sheet's default text style. Fields
  /// still unset fall through to the grid's built-in text style.
  TextStyleSpec effectiveTextStyleAt(int row, int column) {
    final sheet = _spreadsheet?.activeSheet;

    if (sheet == null || row < 0 || row >= sheet.rows.length) {
      return TextStyleSpec.empty;
    }

    final cells = sheet.rows[row].cells;

    if (column < 0 || column >= cells.length) {
      return sheet.textDefaults;
    }

    return cells[column].style.mergedOver(sheet.textDefaults);
  }

  /// Applies [set] (fields to set) and [reset] (fields to return to
  /// "inherit from the sheet default") to every cell in the rectangle
  /// from ([startRow], [startColumn]) to ([endRow], [endColumn]), in any
  /// corner order, clamped to the sheet.
  ///
  /// Updates locally first, then persists fire-and-forget like
  /// [_persistCellEdits] (failures surface via [lastSaveError]). Unlike
  /// RTL or column width this DOES record an undo point, since it is a
  /// document edit - but note that, as with cell edits, undo/redo only
  /// rewinds the local model; it does not re-persist.
  void applyTextStyle({
    required int startRow,
    required int startColumn,
    required int endRow,
    required int endColumn,
    TextStyleSpec set = TextStyleSpec.empty,
    Set<String> reset = const {},
  }) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null || (set.isEmpty && reset.isEmpty)) {
      return;
    }

    final sheet = currentSpreadsheet.activeSheet;

    if (sheet.rows.isEmpty || sheet.headers.isEmpty) {
      return;
    }

    final firstRow = (startRow < endRow ? startRow : endRow)
        .clamp(0, sheet.rows.length - 1);
    final lastRow = (startRow > endRow ? startRow : endRow)
        .clamp(0, sheet.rows.length - 1);
    final firstColumn = (startColumn < endColumn ? startColumn : endColumn)
        .clamp(0, sheet.headers.length - 1);
    final lastColumn = (startColumn > endColumn ? startColumn : endColumn)
        .clamp(0, sheet.headers.length - 1);

    _recordHistoryPoint();

    // The selection is a block of SHOWN rows. With a sort or filter in
    // place those are scattered through the real data, so work out which
    // canonical rows they are - that is what gets changed and saved.
    final sourceRows = <int>[
      for (int row = firstRow; row <= lastRow; row++) sheet.sourceRowOf(row),
    ];

    final replacements = <int, RowModel>{};

    for (final sourceRow in sourceRows) {
      final current = sheet.allRows[sourceRow];
      final cells = List<CellModel>.from(current.cells);

      for (int column = firstColumn;
          column <= lastColumn && column < cells.length;
          column++) {
        final cell = cells[column];
        cells[column] = cell.copyWith(
          style: cell.style.applied(set, reset: reset),
        );
      }

      replacements[sourceRow] = RowModel(index: current.index, cells: cells);
    }

    final updatedSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    updatedSheets[currentSpreadsheet.activeSheetIndex] =
        sheet.withSourceRows(replacements);

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: currentSpreadsheet.activeSheetIndex,
      sheets: updatedSheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    notifyListeners();

    // One request for the whole selection (one undo step on the server),
    // as runs of consecutive canonical rows.
    final ranges = [
      for (final (first, last) in _contiguousRuns(sourceRows))
        (
          startRow: first,
          startColumn: firstColumn,
          endRow: last,
          endColumn: lastColumn,
        ),
    ];

    _enqueueBackendWrite(
      errorPrefix: 'Failed to save formatting',
      job: () async {
        await _service.setCellStyles(
          ranges: ranges,
          style: set.toJson(),
          reset: reset.toList(),
        );
      },
    );
  }

  /// Groups [rows] into runs of consecutive numbers, in ascending order:
  /// [7, 3, 4, 5, 9, 8] becomes [(3, 5), (7, 9)]. Used to describe a set of
  /// canonical rows to the server as a few ranges instead of one per row.
  List<(int, int)> _contiguousRuns(List<int> rows) {
    if (rows.isEmpty) {
      return const [];
    }

    final sorted = List<int>.of(rows)..sort();
    final runs = <(int, int)>[];

    var start = sorted.first;
    var previous = sorted.first;

    for (final row in sorted.skip(1)) {
      if (row == previous || row == previous + 1) {
        previous = row;
        continue;
      }

      runs.add((start, previous));
      start = row;
      previous = row;
    }

    runs.add((start, previous));
    return runs;
  }

  /// Applies [set] / [reset] to the active sheet's display settings: grid
  /// line color and alternating row colors. Like [setRtl] these are
  /// sheet-level settings set from the Settings dialog - persisted, but
  /// not recorded in the undo history.
  void setAppearance(
    SheetAppearance set, {
    Set<String> reset = const {},
  }) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null || (set.isEmpty && reset.isEmpty)) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final activeSheet = currentSpreadsheet.sheets[activeSheetIndex];

    final updatedSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    updatedSheets[activeSheetIndex] = activeSheet.copyWith(
      appearance: activeSheet.appearance.applied(set, reset: reset),
    );

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: activeSheetIndex,
      sheets: updatedSheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    notifyListeners();

    _enqueueBackendWrite(
      errorPrefix: 'Failed to save sheet appearance',
      job: () async {
        await _service.setAppearance(
          style: set.toJson(),
          reset: reset.toList(),
        );
      },
    );
  }

  /// Applies [set] / [reset] to the active sheet's DEFAULT text style -
  /// what every cell inherits unless it has its own override. Like
  /// [setRtl] this is sheet-level state set from the Settings dialog, so
  /// it is persisted but not recorded in the undo history.
  void setTextDefaults(
    TextStyleSpec set, {
    Set<String> reset = const {},
  }) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null || (set.isEmpty && reset.isEmpty)) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final activeSheet = currentSpreadsheet.sheets[activeSheetIndex];

    final updatedSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    updatedSheets[activeSheetIndex] = activeSheet.copyWith(
      textDefaults: activeSheet.textDefaults.applied(set, reset: reset),
    );

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: activeSheetIndex,
      sheets: updatedSheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    notifyListeners();

    _enqueueBackendWrite(
      errorPrefix: 'Failed to save default text style',
      job: () async {
        await _service.setTextDefaults(
          style: set.toJson(),
          reset: reset.toList(),
        );
      },
    );
  }

  /// Filters the rows shown to those where some cell contains [query]
  /// (case-insensitive; blank = no filter).
  ///
  /// Purely local: it changes which rows THIS client shows, never the data,
  /// and nothing is sent to the server - so in a shared sheet one person's
  /// search can't change anyone else's screen. Formulas and edits keep
  /// working on the real rows (see SheetModel). It is not an edit, so it
  /// isn't undoable - but it doesn't disturb undo history either, since
  /// that history describes the data.
  Future<void> search(String query) async {
    _changeView((view) => view.withSearch(query));
  }

  /// Clears the search filter, showing every row again.
  Future<void> clearSearch() async {
    _changeView((view) => view.withSearch(''));
  }

  /// Sorts the shown rows by [column] (numbers, then text, then blanks -
  /// blanks always last). Local to this client, like [search].
  Future<void> sort({required String column, required bool ascending}) async {
    _changeView((view) => view.withSort(column, ascending: ascending));
  }

  /// Cycles [column]'s sort state on each call, matching standard
  /// spreadsheet header-click behavior: unsorted -> ascending ->
  /// descending -> unsorted (clearing the sort entirely on the third
  /// click).
  Future<void> toggleSort(String column) async {
    if (sortedColumn != column) {
      await sort(column: column, ascending: true);
      return;
    }

    if (sortAscending) {
      await sort(column: column, ascending: false);
      return;
    }

    await clearSort();
  }

  /// Clears the sort, restoring the data's own row order.
  Future<void> clearSort() async {
    _changeView((view) => view.withSort(null));
  }

  /// Applies [change] to the active sheet's view and recomputes which rows
  /// are shown from the sheet's current data.
  void _changeView(SheetView Function(SheetView view) change) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final sheet = currentSpreadsheet.sheets[activeSheetIndex];
    final newView = change(sheet.view);

    if (newView == sheet.view) {
      return;
    }

    final sheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    sheets[activeSheetIndex] = sheet.withView(newView);

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: activeSheetIndex,
      sheets: sheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    notifyListeners();
  }

  /// Replaces the active sheet's data with a fresh conversion of [data],
  /// preserving the sheet's name and every other sheet untouched. Shared
  /// by every row/column mutation, which all refresh the active sheet
  /// from the backend's response after applying their change.
  ///
  /// The response is the CANONICAL data; this client's own view (search
  /// filter and sort) is applied on top of it, so inserting or deleting a
  /// row doesn't throw away what the user was searching or sorting by.
  void _replaceActiveSheet(SpreadsheetData data) {
    final currentSpreadsheet = _spreadsheet;
    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final activeSheetName =
        currentSpreadsheet.sheets[activeSheetIndex].name;

    final updatedSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    updatedSheets[activeSheetIndex] = _sheetFromApiData(
      name: activeSheetName,
      data: data,
    ).withView(currentSpreadsheet.sheets[activeSheetIndex].view);

    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: activeSheetIndex,
      sheets: updatedSheets,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );
  }

  // ============================================================
  // Mock data
  // ============================================================

  void loadMockData() {
    _spreadsheet = SpreadsheetModel(
      activeSheetIndex: 0,
      sheets: [
        SheetModel(
          name: "Sheet1",
          allRows: List.generate(
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

  // ============================================================
  // History management (Undo/Redo)
  // ============================================================

  void _recordHistoryPoint() {
    if (_spreadsheet == null) {
      return;
    }

    _undoStack.add(_spreadsheet!);
    _redoStack.clear();
  }

  /// Undoes the last document edit: the grid updates instantly from the
  /// stored snapshot (so formulas and selection stay intact), and the
  /// backend is told to undo the same step so the saved file agrees.
  void undo() {
    final current = _spreadsheet;

    if (!canUndo || current == null) {
      return;
    }

    _redoStack.add(current);
    _spreadsheet = _withCurrentSettings(_undoStack.removeLast(), current);

    notifyListeners();
    _syncBackendHistory(isUndo: true);
  }

  void redo() {
    final current = _spreadsheet;

    if (!canRedo || current == null) {
      return;
    }

    _undoStack.add(current);
    _spreadsheet = _withCurrentSettings(_redoStack.removeLast(), current);

    notifyListeners();
    _syncBackendHistory(isUndo: false);
  }

  /// Applies [restored] (an old snapshot) but keeps the CURRENT sheet's
  /// direction, default text style and appearance. Those are settings, not edits -
  /// and the backend leaves them alone on undo - so undoing a cell edit
  /// must not also flip RTL back or reset the default font.
  SpreadsheetModel _withCurrentSettings(
    SpreadsheetModel restored,
    SpreadsheetModel current,
  ) {
    final index = restored.activeSheetIndex;

    if (index < 0 ||
        index >= restored.sheets.length ||
        index >= current.sheets.length) {
      return restored;
    }

    // Undo restores the DATA, not how this user happens to be looking at
    // it: keep the current search/sort and re-apply it to the restored rows
    // (their number may differ - e.g. when undoing a row insert).
    final sheets = List<SheetModel>.from(restored.sheets);
    sheets[index] = sheets[index]
        .copyWith(
          isRtl: current.sheets[index].isRtl,
          textDefaults: current.sheets[index].textDefaults,
          appearance: current.sheets[index].appearance,
        )
        .withView(current.sheets[index].view);

    return SpreadsheetModel(
      activeSheetIndex: index,
      sheets: sheets,
      availableSheetNames: restored.availableSheetNames,
    );
  }

  /// Tells the backend to take the same undo/redo step the grid just took.
  /// Queued behind earlier writes so it applies to the right state. If
  /// the backend has no such step (the two histories drifted), the write
  /// fails and [_enqueueBackendWrite] reloads the grid from the backend.
  void _syncBackendHistory({required bool isUndo}) {
    _enqueueBackendWrite(
      errorPrefix: isUndo ? 'Failed to save undo' : 'Failed to save redo',
      job: () async {
        if (isUndo) {
          await _service.undo();
        } else {
          await _service.redo();
        }
      },
    );
  }

  // ============================================================
  // Formula detection
  // ============================================================

  bool _isFormula(String text) {
    return text.startsWith('=');
  }

  SpreadsheetModel _recalculateDependents(
    SpreadsheetModel spreadsheet,
    Set<String> changedCells,
  ) {
    final graph = FormulaDependencyGraph(
      spreadsheet,
      _formulaEngine,
    );
    final cellsToRecalculate = graph.dependentsOf(changedCells);

    for (final changedCell in changedCells) {
      final position = FormulaDependencyGraph.positionFor(changedCell);
      final cell = spreadsheet.activeSheet.allRows[position.row]
          .cells[position.column];
      if (cell.formula != null) {
        cellsToRecalculate.add(changedCell);
      }
    }

    var recalculatedSpreadsheet = spreadsheet;
    for (final address in cellsToRecalculate) {
      final position = FormulaDependencyGraph.positionFor(address);
      final cell = recalculatedSpreadsheet.activeSheet.allRows[position.row]
          .cells[position.column];
      final formula = cell.formula;
      if (formula == null) {
        continue;
      }

      final value = _formulaEngine.evaluate(
        formula,
        recalculatedSpreadsheet,
        resolving: {address},
      );
      recalculatedSpreadsheet = _replaceCell(
        recalculatedSpreadsheet,
        position.row,
        position.column,
        CellModel(
          row: cell.row,
          column: cell.column,
          value: value,
          formula: formula,
          isSelected: cell.isSelected,
          isEditing: false,
          style: cell.style,
        ),
      );
    }

    return recalculatedSpreadsheet;
  }

  /// Replaces one cell. [row] is a CANONICAL row (an index into the
  /// sheet's allRows - the same row numbers formulas use), NOT a position
  /// in the currently shown rows; callers holding a shown row convert it
  /// with [SheetModel.sourceRowOf] first.
  SpreadsheetModel _replaceCell(
    SpreadsheetModel spreadsheet,
    int row,
    int column,
    CellModel cell,
  ) {
    final sheet = spreadsheet.activeSheet;
    final current = sheet.allRows[row];
    final cells = List<CellModel>.from(current.cells);
    cells[column] = cell;

    final sheets = List<SheetModel>.from(spreadsheet.sheets);
    sheets[spreadsheet.activeSheetIndex] = sheet.withSourceRows({
      row: RowModel(index: current.index, cells: cells),
    });

    return SpreadsheetModel(
      sheets: sheets,
      activeSheetIndex: spreadsheet.activeSheetIndex,
      availableSheetNames: spreadsheet.availableSheetNames,
    );
  }

  // ============================================================
  // Cell editing
  // ============================================================

  /// Sets one cell's content. [row] is a row of the grid as SHOWN (this
  /// client's search/sort applied); it is converted to the canonical row
  /// once, up front, and everything after that - the stored cell, formula
  /// references and what is sent to the server - uses canonical rows.
  ///
  /// [value] is the cell's INPUT: either plain text or, if it starts with
  /// "=", a formula. The input is what gets saved, so formulas are stored
  /// as text and re-evaluated whenever the sheet is loaded (the computed
  /// result is derived, never saved).
  void editCell({
    required int row,
    required int column,
    required String value,
  }) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex = currentSpreadsheet.activeSheetIndex;
    final currentSheet = currentSpreadsheet.sheets[activeSheetIndex];

    if (row < 0 || row >= currentSheet.rows.length) {
      return;
    }

    final sourceRow = currentSheet.sourceRowOf(row);
    final currentRow = currentSheet.allRows[sourceRow];

    if (column < 0 || column >= currentRow.cells.length) {
      return;
    }

    _recordHistoryPoint();

    final isFormula = _isFormula(value);
    final newValue =
        isFormula ? _formulaEngine.evaluate(value, currentSpreadsheet) : value;
    final newFormula = isFormula ? value : null;

    final oldCell = currentRow.cells[column];

    final newCell = CellModel(
      row: oldCell.row,
      column: oldCell.column,
      value: newValue,
      formula: newFormula,
      isSelected: oldCell.isSelected,
      isEditing: false,
      style: oldCell.style,
    );

    final newCells = List<CellModel>.from(currentRow.cells);
    newCells[column] = newCell;

    final newSheets = List<SheetModel>.from(currentSpreadsheet.sheets);
    newSheets[activeSheetIndex] = currentSheet.withSourceRows({
      sourceRow: RowModel(index: currentRow.index, cells: newCells),
    });

    final updatedSpreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    _spreadsheet = _recalculateDependents(
      updatedSpreadsheet,
      {
        FormulaDependencyGraph.addressFor(
          row: sourceRow,
          column: column,
        ),
      },
    );

    notifyListeners();

    _persistCellEdits([(row: sourceRow, column: column, value: value)]);
  }

  /// The most recent background save failure (cell edit, paste, clear),
  /// if any - surfaced this way rather than thrown, since those calls
  /// aren't awaited by their callers and the local edit already
  /// succeeded from the user's point of view; only the persistence
  /// failed. UI code that wants to show this can read it after
  /// [notifyListeners] fires and clear it via [clearLastSaveError].
  String? _lastSaveError;
  String? get lastSaveError => _lastSaveError;

  void clearLastSaveError() {
    _lastSaveError = null;
  }

  /// Persists one or more cell edits to the backend, fire-and-forget.
  /// Every local mutation path that changes cell values (single-cell
  /// edit, paste, clear-selection) funnels through here so the backend
  /// save logic - and its failure handling - lives in exactly one place.
  ///
  /// Without this, an edit only ever lives in the frontend's in-memory
  /// model, and any subsequent full-sheet refresh (insert row/column,
  /// search, sort, switching sheets and back) silently overwrites it with
  /// the backend's still-unedited data - which is what "my edit
  /// disappeared after I did something else" looks like from the
  /// outside. Each edit's `value` is the cell's INPUT - formula text such
  /// as "=A1+A2" for a formula, otherwise the plain value - never a computed
  /// result. The server stores it as typed (and writes it to the .xlsx as a
  /// real formula); every client re-evaluates formulas itself on load, so
  /// everyone sees the same results. Rows are CANONICAL rows (indices into
  /// the sheet's allRows), not positions in whatever the user is currently
  /// sorting or filtering.
  ///
  void _persistCellEdits(
    List<({int row, int column, String value})> edits,
  ) {
    if (edits.isEmpty) {
      return;
    }

    // ONE request for the whole batch (a paste or clear can touch many
    // cells): the backend applies it as a single undoable step, and
    // rewrites the worksheet once instead of once per cell.
    _enqueueBackendWrite(
      errorPrefix: 'Failed to save changes',
      job: () async {
        await _service.editCells(edits);
      },
    );
  }

  Future<void> copySelection(SelectionModel selection) async {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    final startRow =
        selection.startRow <= selection.endRow
            ? selection.startRow
            : selection.endRow;

    final endRow =
        selection.startRow <= selection.endRow
            ? selection.endRow
            : selection.startRow;

    final startColumn =
        selection.startColumn <= selection.endColumn
            ? selection.startColumn
            : selection.endColumn;

    final endColumn =
        selection.startColumn <= selection.endColumn
            ? selection.endColumn
            : selection.startColumn;

    final rows = <String>[];

    for (int row = startRow; row <= endRow; row++) {
      final cells = <String>[];

      for (
        int column = startColumn;
        column <= endColumn;
        column++
      ) {
        final cell = currentSheet.rows[row].cells[column];
        cells.add(cell.formula ?? cell.value);
      }

      rows.add(cells.join('\t'));
    }

    await Clipboard.setData(
      ClipboardData(
        text: rows.join('\n'),
      ),
    );
  }

  Future<void> pasteClipboard({
    required int row,
    required int column,
    required String clipboardText,
  }) async {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    // ----------------------------------------------------------
    // Parse clipboard text as TSV
    // ----------------------------------------------------------

    final lines = clipboardText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    // Ignore a trailing newline from the clipboard.
    if (lines.length > 1 && lines.last.isEmpty) {
      lines.removeLast();
    }

    if (lines.isEmpty || lines.first.isEmpty) {
      return;
    }

    final pastedRows = lines.map(
      (line) => line.split('\t'),
    ).toList();

    // ----------------------------------------------------------
    // Validate paste origin
    // ----------------------------------------------------------

    if (row < 0 || row >= currentSheet.rows.length) {
      return;
    }

    if (column < 0 ||
        column >= currentSheet.rows[row].cells.length) {
      return;
    }

    // ----------------------------------------------------------
    // Record history point before mutation
    // ----------------------------------------------------------

    _recordHistoryPoint();

    // ----------------------------------------------------------
    // Create new rows
    // ----------------------------------------------------------

    // The paste runs down the SHOWN rows; each is converted to the
    // canonical row it really is, which is what gets changed and saved.
    final replacements = <int, RowModel>{};
    final changedCells = <String>{};
    final pastedEdits = <({int row, int column, String value})>[];

    for (int pastedRow = 0;
        pastedRow < pastedRows.length;
        pastedRow++) {
      final targetRow = row + pastedRow;

      if (targetRow >= currentSheet.rows.length) {
        break;
      }

      final sourceRow = currentSheet.sourceRowOf(targetRow);
      final currentRow = currentSheet.allRows[sourceRow];

      final newCells =
          List<CellModel>.from(currentRow.cells);

      final values = pastedRows[pastedRow];

      for (int pastedColumn = 0;
          pastedColumn < values.length;
          pastedColumn++) {
        final targetColumn = column + pastedColumn;

        if (targetColumn >= currentRow.cells.length) {
          break;
        }

        final oldCell = currentRow.cells[targetColumn];
        final pastedValue = values[pastedColumn];

        final isFormula = _isFormula(pastedValue);
        final cellFormula = isFormula ? pastedValue : null;

        newCells[targetColumn] = CellModel(
          row: oldCell.row,
          column: oldCell.column,
          value: pastedValue,
          formula: cellFormula,
          isSelected: oldCell.isSelected,
          isEditing: false,
          style: oldCell.style,
        );
        changedCells.add(
          FormulaDependencyGraph.addressFor(
            row: sourceRow,
            column: targetColumn,
          ),
        );
        pastedEdits.add((row: sourceRow, column: targetColumn, value: pastedValue));
      }

      replacements[sourceRow] = RowModel(
        index: currentRow.index,
        cells: newCells,
      );
    }

    // ----------------------------------------------------------
    // Create new sheet
    // ----------------------------------------------------------

    final newSheet = currentSheet.withSourceRows(replacements);

    // ----------------------------------------------------------
    // Create new sheet list
    // ----------------------------------------------------------

    final newSheets =
        List<SheetModel>.from(
      currentSpreadsheet.sheets,
    );

    newSheets[activeSheetIndex] = newSheet;

    // ----------------------------------------------------------
    // Replace spreadsheet
    // ----------------------------------------------------------

    final updatedSpreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    _spreadsheet = _recalculateDependents(
      updatedSpreadsheet,
      changedCells,
    );

    notifyListeners();

    _persistCellEdits(pastedEdits);
  }

  void clearSelection(SelectionModel selection) {
    final currentSpreadsheet = _spreadsheet;

    if (currentSpreadsheet == null) {
      return;
    }

    final activeSheetIndex =
        currentSpreadsheet.activeSheetIndex;

    final currentSheet =
        currentSpreadsheet.sheets[activeSheetIndex];

    // ----------------------------------------------------------
    // Normalize selection bounds
    // ----------------------------------------------------------

    final startRow =
        selection.startRow <= selection.endRow
            ? selection.startRow
            : selection.endRow;

    final endRow =
        selection.startRow <= selection.endRow
            ? selection.endRow
            : selection.startRow;

    final startColumn =
        selection.startColumn <= selection.endColumn
            ? selection.startColumn
            : selection.endColumn;

    final endColumn =
        selection.startColumn <= selection.endColumn
            ? selection.endColumn
            : selection.startColumn;

    // ----------------------------------------------------------
    // Validate selection
    // ----------------------------------------------------------

    if (startRow < 0 ||
        startRow >= currentSheet.rows.length) {
      return;
    }

    // ----------------------------------------------------------
    // Record history point before mutation
    // ----------------------------------------------------------

    _recordHistoryPoint();

    // ----------------------------------------------------------
    // Create new rows
    // ----------------------------------------------------------

    // The selection is a block of SHOWN rows; convert each to the
    // canonical row it really is before changing or saving anything.
    final replacements = <int, RowModel>{};
    final changedCells = <String>{};
    final clearedEdits = <({int row, int column, String value})>[];

    for (int row = startRow; row <= endRow; row++) {
      if (row >= currentSheet.rows.length) {
        break;
      }

      final sourceRow = currentSheet.sourceRowOf(row);
      final currentRow = currentSheet.allRows[sourceRow];

      final newCells =
          List<CellModel>.from(currentRow.cells);

      for (
        int column = startColumn;
        column <= endColumn;
        column++
      ) {
        if (column < 0 ||
            column >= currentRow.cells.length) {
          continue;
        }

        final oldCell = currentRow.cells[column];

        newCells[column] = CellModel(
          row: oldCell.row,
          column: oldCell.column,
          value: "",
          formula: null,
          isSelected: oldCell.isSelected,
          isEditing: false,
          style: oldCell.style,
        );
        changedCells.add(
          FormulaDependencyGraph.addressFor(
            row: sourceRow,
            column: column,
          ),
        );
        clearedEdits.add((row: sourceRow, column: column, value: ""));
      }

      replacements[sourceRow] = RowModel(
        index: currentRow.index,
        cells: newCells,
      );
    }

    // ----------------------------------------------------------
    // Create new sheet
    // ----------------------------------------------------------

    final newSheet = currentSheet.withSourceRows(replacements);

    // ----------------------------------------------------------
    // Create new sheet list
    // ----------------------------------------------------------

    final newSheets =
        List<SheetModel>.from(
      currentSpreadsheet.sheets,
    );

    newSheets[activeSheetIndex] = newSheet;

    // ----------------------------------------------------------
    // Replace spreadsheet
    // ----------------------------------------------------------

    final updatedSpreadsheet = SpreadsheetModel(
      sheets: newSheets,
      activeSheetIndex: activeSheetIndex,
      availableSheetNames: currentSpreadsheet.availableSheetNames,
    );

    _spreadsheet = _recalculateDependents(
      updatedSpreadsheet,
      changedCells,
    );

    notifyListeners();

    _persistCellEdits(clearedEdits);
  }

}