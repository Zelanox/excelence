import 'package:flutter/material.dart';

import '../../controllers/spreadsheet_controller.dart';

/// Displays the row number (1, 2, 3, ...) for one row.
///
/// The number itself is pure/stateless - a row's NUMBER never changes
/// based on spreadsheet content or selection, only its position (handled
/// by the parent grid re-laying-out on insert/delete). Right-clicking
/// shows a small context menu to delete the row - rows are identified by
/// index, not name, so there's no rename affordance here (unlike
/// GridColumnHeader).
class GridRowHeader extends StatelessWidget {
  const GridRowHeader({
    super.key,
    required this.rowIndex,
    required this.spreadsheetController,
  });

  final int rowIndex;
  final SpreadsheetController spreadsheetController;

  Future<void> _deleteRow(BuildContext context) async {
    try {
      await spreadsheetController.deleteRow(index: rowIndex);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete row: $error')),
        );
      }
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('Delete row')),
      ],
    );

    if (selected == 'delete') {
      _deleteRow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          border: Border(
            right: BorderSide(color: Colors.grey.shade400),
            bottom: BorderSide(color: Colors.grey.shade400),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '${rowIndex + 1}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
