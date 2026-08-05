import 'package:flutter/material.dart';

import 'cell_viewport.dart';
import 'column_header.dart';
import 'corner_cell.dart';
import 'row_header.dart';

class SpreadsheetGrid extends StatelessWidget {
  const SpreadsheetGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(
          height: 32,
          child: Row(
            children: [
              CornerCell(),
              Expanded(
                child: ColumnHeader(),
              ),
            ],
          ),
        ),

        const Expanded(
          child: Row(
            children: [
              RowHeader(),
              Expanded(
                child: CellViewport(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}