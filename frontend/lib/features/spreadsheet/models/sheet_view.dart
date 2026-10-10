import 'package:flutter/foundation.dart';

import 'row_model.dart';

/// How a sheet is presented to ONE user: an optional search filter and an
/// optional sort. A view never changes the sheet's data - it only chooses
/// which rows are shown, and in what order.
///
/// Views are CLIENT-LOCAL by design. In a shared sheet, one person's sort
/// or filter must not rearrange anyone else's screen, and a sorted/filtered
/// row number must never be mistaken for a position in the real data. The
/// full rows always live in [SheetModel.allRows]; this class computes which
/// of them to show.
///
/// The ordering rules deliberately match the server's SortService, so the
/// order a user sees doesn't change depending on where it was computed:
/// within a column, numbers come first, then text (case-insensitive), then
/// blanks - and blanks are always last, whichever direction is chosen. In
/// descending order the number/text groups swap (text first), as in Excel.
@immutable
class SheetView {
  const SheetView({
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
  });

  static const SheetView none = SheetView();

  /// Rows are kept only if some cell contains this text (case-insensitive,
  /// literal - not a pattern). Empty / whitespace-only means "no filter".
  final String searchQuery;

  /// Name of the column to sort by, or null for the data's own order.
  final String? sortColumn;

  final bool sortAscending;

  /// True when this view shows every row in the data's own order.
  bool get isIdentity => searchQuery.trim().isEmpty && sortColumn == null;

  SheetView withSearch(String query) {
    return SheetView(
      searchQuery: query,
      sortColumn: sortColumn,
      sortAscending: sortAscending,
    );
  }

  SheetView withSort(String? column, {bool ascending = true}) {
    return SheetView(
      searchQuery: searchQuery,
      sortColumn: column,
      sortAscending: ascending,
    );
  }

  /// The indices into [rows] to show, in display order - or null when the
  /// view is the identity (every row, in order), so callers can skip the
  /// mapping entirely in the common case.
  ///
  /// A sort column that no longer exists (deleted or renamed) is ignored
  /// rather than failing.
  List<int>? apply(List<String> headers, List<RowModel> rows) {
    final query = searchQuery.trim().toLowerCase();
    final column = sortColumn == null ? -1 : headers.indexOf(sortColumn!);

    if (query.isEmpty && column < 0) {
      return null;
    }

    var indices = <int>[
      for (int i = 0; i < rows.length; i++) i,
    ];

    if (query.isNotEmpty) {
      indices = [
        for (final i in indices)
          if (_rowMatches(rows[i], query)) i,
      ];
    }

    if (column >= 0) {
      indices = _sorted(indices, rows, column, sortAscending);
    }

    return indices;
  }

  static bool _rowMatches(RowModel row, String lowerCaseQuery) {
    for (final cell in row.cells) {
      if (cell.value.toLowerCase().contains(lowerCaseQuery)) {
        return true;
      }
    }

    return false;
  }

  static List<int> _sorted(
    List<int> indices,
    List<RowModel> rows,
    int column,
    bool ascending,
  ) {
    // Each cell is classified ONCE up front, not on every comparison.
    final keys = <int, _SortKey>{
      for (final i in indices)
        i: _SortKey.of(
          column < rows[i].cells.length ? rows[i].cells[column].value : '',
        ),
    };

    int rank(_SortKey key) {
      switch (key.kind) {
        case _SortKey.kindBlank:
          return 2; // blanks are always last
        case _SortKey.kindNumber:
          return ascending ? 0 : 1;
        default:
          return ascending ? 1 : 0;
      }
    }

    final result = List<int>.of(indices);

    result.sort((a, b) {
      final keyA = keys[a]!;
      final keyB = keys[b]!;

      final byRank = rank(keyA).compareTo(rank(keyB));
      if (byRank != 0) {
        return byRank;
      }

      int within = 0;

      if (keyA.kind == _SortKey.kindNumber) {
        within = ascending
            ? keyA.numberValue.compareTo(keyB.numberValue)
            : keyB.numberValue.compareTo(keyA.numberValue);
      } else if (keyA.kind == _SortKey.kindText) {
        within = ascending
            ? keyA.textValue.compareTo(keyB.textValue)
            : keyB.textValue.compareTo(keyA.textValue);
      }

      // Dart's List.sort is not stable, so equal cells are ordered by their
      // original position - which makes the result stable, like the server's.
      return within != 0 ? within : a.compareTo(b);
    });

    return result;
  }

  @override
  bool operator ==(Object other) {
    return other is SheetView &&
        other.searchQuery == searchQuery &&
        other.sortColumn == sortColumn &&
        other.sortAscending == sortAscending;
  }

  @override
  int get hashCode => Object.hash(searchQuery, sortColumn, sortAscending);
}

/// A cell's sort classification: a number, text (lower-cased), or blank.
class _SortKey {
  const _SortKey._(this.kind, this.numberValue, this.textValue);

  static const int kindNumber = 0;
  static const int kindText = 1;
  static const int kindBlank = 2;

  static const _SortKey _blank = _SortKey._(kindBlank, 0, '');

  final int kind;
  final double numberValue;
  final String textValue;

  /// Classifies one cell's displayed value. Any text that parses as a
  /// finite number counts as a number (every value on the client is a
  /// string, so "25" and "7.5" must sort numerically); everything else
  /// non-blank is text.
  factory _SortKey.of(String raw) {
    final trimmed = raw.trim();

    if (trimmed.isEmpty) {
      return _blank;
    }

    final number = double.tryParse(trimmed);

    if (number != null && number.isFinite) {
      return _SortKey._(kindNumber, number, '');
    }

    return _SortKey._(kindText, 0, trimmed.toLowerCase());
  }
}
