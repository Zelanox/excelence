import 'package:flutter/material.dart';

import '../column_naming.dart';

/// Displays the column letter (A, B, C, ...) for one column.
///
/// Pure/stateless: given a column index, it always shows the same thing.
/// It does not need to listen to any controller because a column's LETTER
/// never changes based on spreadsheet data or selection - only the
/// column's WIDTH or presence would (e.g. inserting/deleting columns),
/// which is handled by the parent grid re-laying-out, not by this widget
/// re-deriving its own label.
class GridColumnHeader extends StatelessWidget {
  const GridColumnHeader({
    super.key,
    required this.columnIndex,
  });

  final int columnIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(
          right: BorderSide(color: Colors.grey.shade400),
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        columnLetterName(columnIndex),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
