import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';

/// A row of worksheet tabs shown below the grid, Excel-style - click a
/// tab to switch sheets, click "+" to add a new one, right-click a tab
/// for rename/delete. This is the only place in the shell that knows
/// about the workbook's full sheet list (SpreadsheetController.spreadsheet
/// only ever holds the currently ACTIVE sheet's data - switching tabs
/// fetches that sheet's data fresh rather than keeping every sheet's data
/// resident at once).
class SheetTabs extends StatefulWidget {
  const SheetTabs({
    super.key,
    required this.spreadsheetController,
  });

  final SpreadsheetController spreadsheetController;

  @override
  State<SheetTabs> createState() => _SheetTabsState();
}

class _SheetTabsState extends State<SheetTabs> {
  // Which tab (by sheet name) is currently mid-rename, if any. Kept here
  // rather than per-tab since only one tab can be renaming at a time and
  // this widget already owns the whole row.
  String? _renamingSheet;
  TextEditingController? _renameTextController;
  FocusNode? _renameFocusNode;

  @override
  void dispose() {
    _renameTextController?.dispose();
    _renameFocusNode?.dispose();
    super.dispose();
  }

  Future<void> _switchTo(String sheetName) async {
    try {
      await widget.spreadsheetController.switchSheet(sheetName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to switch sheet: $error')),
        );
      }
    }
  }

  Future<void> _addSheet() async {
    final existingNames = widget
            .spreadsheetController.spreadsheet?.availableSheetNames ??
        const <String>[];

    var index = existingNames.length + 1;
    String candidate;
    do {
      candidate = 'Sheet$index';
      index++;
    } while (existingNames.contains(candidate));

    try {
      await widget.spreadsheetController.addSheet(candidate);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add sheet: $error')),
        );
      }
    }
  }

  Future<void> _deleteSheet(String sheetName) async {
    try {
      await widget.spreadsheetController.deleteSheet(sheetName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete sheet: $error')),
        );
      }
    }
  }

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

  void _startRenaming(String sheetName) {
    final controller = TextEditingController(text: sheetName);
    final focusNode = FocusNode(
      debugLabel: 'SheetTabRename',
      onKeyEvent: _handleRenameKeyEvent,
    );

    setState(() {
      _renamingSheet = sheetName;
      _renameTextController = controller;
      _renameFocusNode = focusNode;
    });

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
    final oldName = _renamingSheet;
    final newName = _renameTextController?.text.trim() ?? '';

    final controller = _renameTextController;
    final focusNode = _renameFocusNode;

    setState(() {
      _renamingSheet = null;
      _renameTextController = null;
      _renameFocusNode = null;
    });
    controller?.dispose();
    focusNode?.dispose();

    if (oldName == null || newName.isEmpty || newName == oldName) {
      return;
    }

    try {
      await widget.spreadsheetController.renameSheet(
        oldName: oldName,
        newName: newName,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename sheet: $error')),
        );
      }
    }
  }

  void _cancelRename() {
    final controller = _renameTextController;
    final focusNode = _renameFocusNode;

    setState(() {
      _renamingSheet = null;
      _renameTextController = null;
      _renameFocusNode = null;
    });
    controller?.dispose();
    focusNode?.dispose();
  }

  Future<void> _showContextMenu(
    BuildContext context,
    String sheetName,
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
        PopupMenuItem(value: 'rename', child: Text('Rename sheet')),
        PopupMenuItem(value: 'delete', child: Text('Delete sheet')),
      ],
    );

    if (!mounted) return;

    switch (selected) {
      case 'rename':
        _startRenaming(sheetName);
        break;
      case 'delete':
        _deleteSheet(sheetName);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.spreadsheetController,
      builder: (context, _) {
        final spreadsheet = widget.spreadsheetController.spreadsheet;
        final sheetNames = spreadsheet?.availableSheetNames ?? const [];
        final activeName = spreadsheet?.activeSheet.name;

        return Container(
          height: 32,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final sheetName in sheetNames)
                      _SheetTab(
                        name: sheetName,
                        isActive: sheetName == activeName,
                        isRenaming: sheetName == _renamingSheet,
                        renameController: sheetName == _renamingSheet
                            ? _renameTextController
                            : null,
                        renameFocusNode: sheetName == _renamingSheet
                            ? _renameFocusNode
                            : null,
                        onTap: () => _switchTo(sheetName),
                        onSecondaryTapDown: (position) =>
                            _showContextMenu(context, sheetName, position),
                        onDoubleTap: () => _startRenaming(sheetName),
                        onRenameSubmitted: _commitRename,
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add sheet',
                onPressed: _addSheet,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetTab extends StatelessWidget {
  const _SheetTab({
    required this.name,
    required this.isActive,
    required this.isRenaming,
    required this.renameController,
    required this.renameFocusNode,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onDoubleTap,
    required this.onRenameSubmitted,
  });

  final String name;
  final bool isActive;
  final bool isRenaming;
  final TextEditingController? renameController;
  final FocusNode? renameFocusNode;
  final VoidCallback onTap;
  final void Function(Offset position) onSecondaryTapDown;
  final VoidCallback onDoubleTap;
  final VoidCallback onRenameSubmitted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isRenaming ? null : onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: (details) =>
          onSecondaryTapDown(details.globalPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        constraints: const BoxConstraints(minWidth: 72),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isActive
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                )
              : Border.all(color: Colors.grey.shade300),
        ),
        child: isRenaming
            ? SizedBox(
                width: 90,
                child: TextField(
                  controller: renameController,
                  focusNode: renameFocusNode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onRenameSubmitted(),
                  onTapOutside: (_) => onRenameSubmitted(),
                ),
              )
            : Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
      ),
    );
  }
}
