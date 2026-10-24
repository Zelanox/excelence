import 'dart:math';

import '../models/sheet_model.dart';

/// The most changes the server accepts in one batch.
const int maxOpsBatchSize = 500;

/// Makes the `client_batch_id` of each batch. The server remembers them, so
/// that a batch sent twice (the answer got lost and the client tried again)
/// is applied only once.
class BatchIdGenerator {
  final String _salt = Random().nextInt(1 << 30).toRadixString(36);
  int _count = 0;

  String next() {
    _count++;
    return 'b$_salt-${_count.toRadixString(36)}';
  }
}

/// A batch that sets [edits] (rows and columns as positions in [sheet]'s
/// canonical data, like everything the controller sends), addressed by the
/// stable row, column and sheet IDs instead of positions.
///
/// Returns null when the batch can't be made safely, and the caller should
/// use the older position-based request instead: the sheet's IDs are
/// missing or out of step with its shape, an edit lies outside the sheet,
/// or there are more changes than one batch may hold (the old request sends
/// them all as one undoable step).
Map<String, dynamic>? buildSetCellsBatch({
  required SheetModel sheet,
  required List<({int row, int column, String value})> edits,
  required String clientBatchId,
  int baseRevision = 0,
}) {
  if (!sheet.hasIds || edits.isEmpty || edits.length > maxOpsBatchSize) {
    return null;
  }

  final cells = <Map<String, dynamic>>[];

  for (final edit in edits) {
    final validRow = edit.row >= 0 && edit.row < sheet.rowIds.length;
    final validColumn = edit.column >= 0 && edit.column < sheet.columnIds.length;

    if (!validRow || !validColumn) {
      return null;
    }

    cells.add({
      'row': sheet.rowIds[edit.row],
      'column': sheet.columnIds[edit.column],
      'value': edit.value,
    });
  }

  return {
    'client_batch_id': clientBatchId,
    'base_revision': baseRevision,
    'sheet_id': sheet.sheetId,
    'ops': [
      {'op': 'set_cells', 'cells': cells},
    ],
  };
}
