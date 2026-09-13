import 'package:flutter/material.dart';

import '../../controllers/spreadsheet_controller.dart';
import '../../controllers/viewport_controller.dart';
import 'grid_cell.dart';
import 'grid_column_header.dart';
import 'grid_row_header.dart';

/// The scrollable grid of column headers, row headers, and cells.
///
/// Built as a single [Table] so that column widths line up between the
/// header row and every data row automatically (a real spreadsheet-like
/// guarantee that's easy to get wrong with independently-positioned
/// widgets). The whole table scrolls both directions together inside a
/// two-axis scroll view - this is the simplest correct approach for a
/// first version; a virtualized/windowed approach can replace this later
/// once real sheets are larger than a screenful.
///
/// This widget holds NO state describing what's selected, being edited,
/// or what any cell contains - all of that lives in the controllers and
/// is read fresh by [GridCell] itself. This widget's only job is layout:
/// deciding where cells go, not what they show.
class SpreadsheetGrid extends StatelessWidget {
  const SpreadsheetGrid({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  static const double columnWidth = 100;
  static const double rowHeight = 28;
  static const double headerSize = 40;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: spreadsheetController,
      builder: (context, _) {
        final sheet = spreadsheetController.spreadsheet?.activeSheet;

        if (sheet == null || sheet.rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final rowCount = sheet.rows.length;
        final columnCount = sheet.rows
            .map((row) => row.cells.length)
            .fold<int>(0, (max, length) => length > max ? length : max);

        if (columnCount == 0) {
          return const SizedBox.shrink();
        }

        final columnWidths = <int, TableColumnWidth>{
          0: const FixedColumnWidth(headerSize),
          for (var c = 0; c < columnCount; c++)
            c + 1: const FixedColumnWidth(columnWidth),
        };

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              columnWidths: columnWidths,
              defaultVerticalAlignment:
                  TableCellVerticalAlignment.middle,
              children: [
                // ------------------------------------------------
                // Header row: blank corner + column letters
                // ------------------------------------------------
                TableRow(
                  children: [
                    const SizedBox(
                      width: headerSize,
                      height: headerSize,
                    ),
                    for (var c = 0; c < columnCount; c++)
                      SizedBox(
                        height: headerSize,
                        child: GridColumnHeader(columnIndex: c),
                      ),
                  ],
                ),

                // ------------------------------------------------
                // Data rows: row number + cells
                // ------------------------------------------------
                for (var r = 0; r < rowCount; r++)
                  TableRow(
                    children: [
                      SizedBox(
                        height: rowHeight,
                        child: GridRowHeader(rowIndex: r),
                      ),
                      for (var c = 0; c < columnCount; c++)
                        SizedBox(
                          height: rowHeight,
                          child: GridCell(
                            row: r,
                            column: c,
                            spreadsheetController: spreadsheetController,
                            viewportController: viewportController,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
