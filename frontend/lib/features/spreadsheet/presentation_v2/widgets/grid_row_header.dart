import 'package:flutter/material.dart';

import '../../../../app/app_text.dart';
import '../../controllers/spreadsheet_controller.dart';
import '../../models/sheet_model.dart';

/// Displays the row number (1, 2, 3, ...) for one row.
///
/// The number itself is pure/stateless - a row's NUMBER never changes
/// based on spreadsheet content or selection, only its position (handled
/// by the parent grid re-laying-out on insert/delete). Right-clicking
/// shows row actions, and dragging the bottom edge resizes it.
class GridRowHeader extends StatelessWidget {
  const GridRowHeader({
    super.key,
    required this.rowIndex,
    required this.spreadsheetController,
  });

  final int rowIndex;
  final SpreadsheetController spreadsheetController;

  Future<void> _deleteRow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failedDeletePrefix = appText(context, 'Failed to delete row: ');

    try {
      await spreadsheetController.deleteRow(index: rowIndex);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$failedDeletePrefix$error'),
        ),
      );
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final rowId = _rowId();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (rowId != null)
          PopupMenuItem(
            value: 'height',
            child: Text(appText(context, 'Row height...')),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Text(appText(context, 'Delete row')),
        ),
      ],
    );

    if (!context.mounted) {
      return;
    }

    if (selected == 'height' && rowId != null) {
      await _editRowHeight(context, rowId);
    } else if (selected == 'delete') {
      await _deleteRow(context);
    }
  }

  String? _rowId() {
    final sheet = spreadsheetController.spreadsheet?.activeSheet;

    if (sheet == null || rowIndex < 0 || rowIndex >= sheet.rows.length) {
      return null;
    }

    final sourceRow = sheet.sourceRowOf(rowIndex);

    if (sourceRow < 0 || sourceRow >= sheet.rowIds.length) {
      return null;
    }

    final rowId = sheet.rowIds[sourceRow];
    return rowId.isEmpty ? null : rowId;
  }

  Future<void> _editRowHeight(BuildContext context, String rowId) async {
    final sheet = spreadsheetController.spreadsheet?.activeSheet;
    final initial =
        sheet?.rowHeightForViewRow(
          rowIndex,
          defaultHeight: SheetModel.defaultRowHeight,
        ) ??
        SheetModel.defaultRowHeight;
    final input = TextEditingController(
      text: initial.toStringAsFixed(initial == initial.roundToDouble() ? 0 : 1),
    );
    String? errorText;

    final selectedHeight = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = double.tryParse(input.text.trim());
            if (value == null || value < 16 || value > 500) {
              setDialogState(() {
                errorText = appText(context, 'Invalid row height.');
              });
              return;
            }

            Navigator.pop(dialogContext, value);
          }

          return AlertDialog(
            title: Text(appText(context, 'Row height')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: input,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: appText(context, 'Height (pixels)'),
                    errorText: errorText,
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 8),
                Text(
                  appText(context, 'Enter a height from 16 to 500.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(appText(context, 'Cancel')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(appText(context, 'Apply')),
              ),
            ],
          );
        },
      ),
    );

    input.dispose();

    if (selectedHeight != null) {
      spreadsheetController.setRowHeight(rowId: rowId, height: selectedHeight);
    }
  }

  /// The number shown for this row: its position in the DATA, not on screen.
  ///
  /// With a sort or filter in place the shown row N is some other row of the
  /// data. Formulas refer to the data's own row numbers (`=A3` is the third
  /// row of the data), so the gutter shows those - sorted rows appear out of
  /// order and filtered-out rows leave gaps, as in Excel - which keeps the
  /// number you read here the number a formula needs.
  int _dataRowNumber() {
    final sheet = spreadsheetController.spreadsheet?.activeSheet;

    if (sheet == null || rowIndex < 0 || rowIndex >= sheet.rows.length) {
      return rowIndex + 1;
    }

    return sheet.sourceRowOf(rowIndex) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final sheet = spreadsheetController.spreadsheet?.activeSheet;
    final rowId = _rowId();
    final currentHeight =
        sheet?.rowHeightForViewRow(
          rowIndex,
          defaultHeight: SheetModel.defaultRowHeight,
        ) ??
        SheetModel.defaultRowHeight;

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border(
                right: BorderSide(color: Colors.grey.shade400),
                bottom: BorderSide(color: Colors.grey.shade400),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${_dataRowNumber()}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (rowId != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 8,
              child: _RowResizeHandle(
                rowId: rowId,
                height: currentHeight,
                spreadsheetController: spreadsheetController,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowResizeHandle extends StatefulWidget {
  const _RowResizeHandle({
    required this.rowId,
    required this.height,
    required this.spreadsheetController,
  });

  final String rowId;
  final double height;
  final SpreadsheetController spreadsheetController;

  @override
  State<_RowResizeHandle> createState() => _RowResizeHandleState();
}

class _RowResizeHandleState extends State<_RowResizeHandle> {
  late double _height = widget.height;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant _RowResizeHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _height = widget.height;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _isDragging = true;
          _height = widget.height;
        },
        onVerticalDragUpdate: (details) {
          _height = (_height + details.delta.dy).clamp(16.0, 500.0).toDouble();
          widget.spreadsheetController.setRowHeightLocal(
            rowId: widget.rowId,
            height: _height,
          );
        },
        onVerticalDragEnd: (_) {
          _isDragging = false;
          widget.spreadsheetController.setRowHeight(
            rowId: widget.rowId,
            height: _height,
          );
        },
      ),
    );
  }
}
