import 'package:flutter/material.dart';

import 'cell_canvas.dart';
import 'column_header.dart';
import 'corner_cell.dart';
import 'row_header.dart';
import 'scroll_coordinator.dart';

class SpreadsheetViewport extends StatefulWidget {
  const SpreadsheetViewport({
    super.key,
  });

  static const double rowHeaderWidth = 48;
  static const double columnHeaderHeight = 32;

  @override
  State<SpreadsheetViewport> createState() =>
      _SpreadsheetViewportState();
}

class _SpreadsheetViewportState
    extends State<SpreadsheetViewport> {
  late final ScrollCoordinator _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollCoordinator();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: SpreadsheetViewport.columnHeaderHeight,
          child: Row(
            children: [
              const SizedBox(
                width: SpreadsheetViewport.rowHeaderWidth,
                child: CornerCell(),
              ),

              Expanded(
                child: ColumnHeader(
                  controller: _scroll.horizontal,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: SpreadsheetViewport.rowHeaderWidth,
                child: RowHeader(
                  controller: _scroll.vertical,
                ),
              ),

              Expanded(
                child: CellCanvas(
                  horizontalController: _scroll.horizontal,
                  verticalController: _scroll.vertical,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}