import 'dart:async';

import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';

/// A search bar shown directly above the spreadsheet grid, filtering the
/// active sheet's visible rows to those matching the typed text.
///
/// This is a live row filter (like Excel's AutoFilter search box), not a
/// cell-highlighting "find" - as the user types, non-matching rows drop
/// out of the grid entirely; clearing the text (or the field itself)
/// brings every row back. Typing is debounced so a search request isn't
/// fired on every keystroke, only after the user pauses briefly.
class SpreadsheetSearchBar extends StatefulWidget {
  const SpreadsheetSearchBar({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  State<SpreadsheetSearchBar> createState() => _SpreadsheetSearchBarState();
}

class _SpreadsheetSearchBarState extends State<SpreadsheetSearchBar> {
  final TextEditingController _textController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    // Only the suffix (clear) icon's visibility depends on whether the
    // field is empty - rebuild for that, cheaply, on every keystroke.
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
    });

    try {
      if (query.trim().isEmpty) {
        await widget.spreadsheetController.clearSearch();
      } else {
        await widget.spreadsheetController.search(query);
      }
      _refreshSheetBounds();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _refreshSheetBounds() {
    final sheet = widget.spreadsheetController.spreadsheet?.activeSheet;
    if (sheet == null) {
      return;
    }
    widget.viewportController.setSheetBounds(
      rowCount: sheet.rows.length,
      columnCount: sheet.rows.isEmpty ? 0 : sheet.rows.first.cells.length,
    );
  }

  void _clear() {
    _debounce?.cancel();
    _textController.clear();
    _runSearch('');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: TextField(
        controller: _textController,
        onChanged: _onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search this sheet…',
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search, size: 20),
          suffixIcon: _textController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear search',
                  onPressed: _clear,
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
      ),
    );
  }
}
