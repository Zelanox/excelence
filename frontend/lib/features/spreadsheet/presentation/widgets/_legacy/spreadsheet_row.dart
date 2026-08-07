import 'package:flutter/material.dart';

import '../../models/row_model.dart';
import 'spreadsheet_cell.dart';

class SpreadsheetRow extends StatelessWidget {
  const SpreadsheetRow({
    super.key,
    required this.row,
  });

  final RowModel row;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: row.cells
          .map(
            (cell) => SpreadsheetCell(
              cell: cell,
            ),
          )
          .toList(),
    );
  }
}