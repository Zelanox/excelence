import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';

class FormulaBar extends StatefulWidget {
  const FormulaBar({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
    required this.spreadsheetFocusNode,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;
  final FocusNode spreadsheetFocusNode;

  @override
  State<FormulaBar> createState() => _FormulaBarState();
}

class _FormulaBarState extends State<FormulaBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    widget.viewportController.addListener(_updateFromSelection);
    widget.spreadsheetController.addListener(_updateFromSpreadsheet);
    _updateFromSelection();
  }

  @override
  void dispose() {
    widget.viewportController.removeListener(_updateFromSelection);
    widget.spreadsheetController.removeListener(_updateFromSpreadsheet);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateFromSelection() {
    if (_focusNode.hasFocus) {
      return;
    }
    _updateText();
  }

  void _updateFromSpreadsheet() {
    if (_focusNode.hasFocus) {
      return;
    }
    _updateText();
  }

  void _updateText() {
    final spreadsheet = widget.spreadsheetController.spreadsheet;
    if (spreadsheet == null) {
      return;
    }

    final selection = widget.viewportController.selection;
    final rows = spreadsheet.activeSheet.rows;

    // Defensive bounds check: the viewport controller is responsible for
    // keeping the selection within the loaded sheet's size, but we guard
    // here too so a stale/out-of-range selection can never crash the
    // formula bar (e.g. right after switching to a smaller document).
    if (selection.activeRow < 0 ||
        selection.activeRow >= rows.length) {
      return;
    }
    final cells = rows[selection.activeRow].cells;
    if (selection.activeColumn < 0 ||
        selection.activeColumn >= cells.length) {
      return;
    }

    final cell = cells[selection.activeColumn];
    final text = cell.formula ?? cell.value;
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _commit() {
    final spreadsheet = widget.spreadsheetController.spreadsheet;
    if (spreadsheet == null) {
      return;
    }

    final selection = widget.viewportController.selection;
    debugPrint(
      '[FormulaBar] final editor text: ${_controller.text}; '
      'target cell: (${selection.activeRow}, ${selection.activeColumn})',
    );
    widget.spreadsheetController.editCell(
      row: selection.activeRow,
      column: selection.activeColumn,
      value: _controller.text,
    );
    _focusNode.unfocus();
    widget.spreadsheetFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          const Text(
            "fx",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onSubmitted: (_) => _commit(),
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}