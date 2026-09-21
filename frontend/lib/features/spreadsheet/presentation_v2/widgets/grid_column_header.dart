import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/spreadsheet_controller.dart';
import '../column_naming.dart';

/// Displays one column's header.
///
/// Shows the column's REAL backend header name (e.g. "Name", "Age") when
/// one is known - the backend is the source of truth for header names,
/// tracked in SheetModel.headers. Only a column with no tracked name yet
/// (index beyond the known headers list - practically, a column inserted
/// this session before its response round-tripped) falls back to a
/// placeholder letter (A, B, C...) via columnLetterName.
///
/// A single tap toggles this column's sort - unsorted -> ascending ->
/// descending -> unsorted again on the third click, matching standard
/// spreadsheet header-click behavior - and shows a small arrow when this
/// column is the active sort. Right-clicking (or double-tapping) shows/
/// starts a small rename/delete interaction. Rename swaps the header
/// into an inline TextField, committed on Enter/blur and cancelled on
/// Escape - the same edit-in-place-then-commit shape GridCell uses for
/// cell editing, kept local to this widget's State since a header's
/// in-progress rename text is transient input state, not committed
/// spreadsheet data.
class GridColumnHeader extends StatefulWidget {
  const GridColumnHeader({
    super.key,
    required this.columnIndex,
    required this.spreadsheetController,
    this.onRenamingChanged,
  });

  final int columnIndex;
  final SpreadsheetController spreadsheetController;

  /// Notifies the parent grid when this header starts/stops renaming, so
  /// the grid can suspend its own focus-stealing and keystroke handling
  /// while this header's inline TextField owns keyboard input.
  final ValueChanged<bool>? onRenamingChanged;

  @override
  State<GridColumnHeader> createState() => _GridColumnHeaderState();
}

class _GridColumnHeaderState extends State<GridColumnHeader> {
  bool _isRenaming = false;
  TextEditingController? _textController;
  FocusNode? _focusNode;

  @override
  void dispose() {
    if (_isRenaming) {
      widget.onRenamingChanged?.call(false);
    }
    _textController?.dispose();
    _focusNode?.dispose();
    super.dispose();
  }

  String? get _currentName {
    final headers =
        widget.spreadsheetController.spreadsheet?.activeSheet.headers;
    if (headers == null ||
        widget.columnIndex < 0 ||
        widget.columnIndex >= headers.length) {
      return null;
    }
    return headers[widget.columnIndex];
  }

  String get _displayName =>
      _currentName ?? columnLetterName(widget.columnIndex);

  KeyEventResult _handleRenameKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelRename();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _startRenaming() {
    final name = _currentName;
    if (name == null) {
      // No tracked backend name yet (still a placeholder letter) - there's
      // nothing real to rename until this column round-trips through an
      // insert response.
      return;
    }

    final controller = TextEditingController(text: name);
    final focusNode = FocusNode(
      debugLabel: 'ColumnHeaderRename',
      onKeyEvent: _handleRenameKeyEvent,
    );

    setState(() {
      _isRenaming = true;
      _textController = controller;
      _focusNode = focusNode;
    });
    widget.onRenamingChanged?.call(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focusNode.requestFocus();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  Future<void> _commitRename() async {
    if (!_isRenaming) return;

    final oldName = _currentName;
    final newName = _textController?.text.trim() ?? '';

    final controller = _textController;
    final focusNode = _focusNode;

    setState(() {
      _isRenaming = false;
      _textController = null;
      _focusNode = null;
    });
    widget.onRenamingChanged?.call(false);
    controller?.dispose();
    focusNode?.dispose();

    if (oldName == null || newName.isEmpty || newName == oldName) {
      return;
    }

    try {
      await widget.spreadsheetController.renameColumn(
        oldName: oldName,
        newName: newName,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename column: $error')),
        );
      }
    }
  }

  void _cancelRename() {
    if (!_isRenaming) return;

    final controller = _textController;
    final focusNode = _focusNode;

    setState(() {
      _isRenaming = false;
      _textController = null;
      _focusNode = null;
    });
    widget.onRenamingChanged?.call(false);
    controller?.dispose();
    focusNode?.dispose();
  }

  Future<void> _deleteColumn() async {
    final name = _currentName;
    if (name == null) {
      return;
    }

    try {
      await widget.spreadsheetController.deleteColumn(name: name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete column: $error')),
        );
      }
    }
  }

  Future<void> _toggleSort() async {
    final name = _currentName;
    if (name == null) {
      // No real backend name yet - nothing meaningful to sort by until
      // this column round-trips through an insert response.
      return;
    }

    try {
      await widget.spreadsheetController.toggleSort(name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sort: $error')),
        );
      }
    }
  }

  Future<void> _sortAscending() async {
    final name = _currentName;
    if (name == null) return;
    try {
      await widget.spreadsheetController.sort(column: name, ascending: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sort: $error')),
        );
      }
    }
  }

  Future<void> _sortDescending() async {
    final name = _currentName;
    if (name == null) return;
    try {
      await widget.spreadsheetController.sort(column: name, ascending: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sort: $error')),
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
        PopupMenuItem(value: 'sort_asc', child: Text('Sort ascending')),
        PopupMenuItem(value: 'sort_desc', child: Text('Sort descending')),
        PopupMenuItem(value: 'rename', child: Text('Rename column')),
        PopupMenuItem(value: 'delete', child: Text('Delete column')),
      ],
    );

    if (!mounted) return;

    switch (selected) {
      case 'sort_asc':
        _sortAscending();
        break;
      case 'sort_desc':
        _sortDescending();
        break;
      case 'rename':
        _startRenaming();
        break;
      case 'delete':
        _deleteColumn();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _currentName;
    final isSortedColumn =
        name != null && widget.spreadsheetController.sortedColumn == name;
    final sortAscending = widget.spreadsheetController.sortAscending;

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      onDoubleTap: _startRenaming,
      onTap: _isRenaming ? null : _toggleSort,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          border: Border(
            right: BorderSide(color: Colors.grey.shade400),
            bottom: BorderSide(color: Colors.grey.shade400),
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _isRenaming
            ? TextField(
                controller: _textController,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _commitRename(),
                onTapOutside: (_) => _commitRename(),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isSortedColumn) ...[
                    const SizedBox(width: 2),
                    Icon(
                      sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 12,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}