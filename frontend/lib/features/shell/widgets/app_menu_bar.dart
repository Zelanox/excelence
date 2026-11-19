import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../file_actions.dart';

/// Menu items that are planned but not built yet. They are shown greyed out
/// so the menus already have their final shape; an item moves out of this
/// list (and becomes a working one) when its feature is implemented.
/// "-" is a divider.
const Map<String, List<String>> plannedMenuItems = {
  'File': ['Import...', 'Download as...', 'Print...'],
  'Edit': ['Find and replace...', 'Select all', 'Clear formatting'],
  'View': [
    'Freeze rows and columns',
    'Show gridlines',
    'Zoom...',
    'Full screen',
  ],
  'Insert': ['Chart', 'Image', 'Link', 'Comment'],
  'Data': [
    'Sort range...',
    'Create a filter',
    'Data validation...',
    'Remove duplicates',
  ],
  'Tools': ['Speech to text', 'Spell check'],
  'Help': ['Keyboard shortcuts', 'About Excelence'],
};

List<PopupMenuEntry<T>> _plannedEntries<T>(String menu) {
  return <PopupMenuEntry<T>>[
    for (final item in plannedMenuItems[menu] ?? const <String>[])
      if (item == '-')
        const PopupMenuDivider()
      else
        PopupMenuItem<T>(enabled: false, child: Text(item)),
  ];
}

/// A top-level menu whose items are all planned (greyed out).
class _PlannedMenu extends StatelessWidget {
  const _PlannedMenu(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: '',
      offset: const Offset(0, 24),
      itemBuilder: (context) => _plannedEntries<Object>(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label),
      ),
    );
  }
}

enum _FileMenuAction {
  newDocument,
  openDocument,
  saveDocument,
  saveAs,
  rename,
  close,
  delete,
}

/// The app's top menu bar. The File menu's document actions work (what each
/// one does lives in [FileActions]); every other item is a greyed-out
/// placeholder listed in [plannedMenuItems] until its feature is built.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({
    super.key,
    required this.spreadsheetController,
  });

  final SpreadsheetController spreadsheetController;

  Future<void> _handleFileAction(
    BuildContext context,
    _FileMenuAction action,
  ) {
    switch (action) {
      case _FileMenuAction.newDocument:
        return FileActions.newDocument(context, spreadsheetController);
      case _FileMenuAction.openDocument:
        return FileActions.openDocument(context, spreadsheetController);
      case _FileMenuAction.saveDocument:
        return FileActions.save(context, spreadsheetController);
      case _FileMenuAction.saveAs:
        return FileActions.saveAs(context, spreadsheetController);
      case _FileMenuAction.rename:
        return FileActions.rename(context, spreadsheetController);
      case _FileMenuAction.close:
        return FileActions.close(context, spreadsheetController);
      case _FileMenuAction.delete:
        return FileActions.delete(context, spreadsheetController);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      // Scrolls sideways instead of overflowing on a very narrow screen.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          PopupMenuButton<_FileMenuAction>(
            tooltip: '',
            offset: const Offset(0, 24),
            onSelected: (action) => _handleFileAction(context, action),
            itemBuilder: (context) {
              // Read when the menu opens: document items need an open
              // document, and nothing is offered while another file action
              // is still running.
              final idle = !spreadsheetController.isFileActionBusy;
              final onDocument = idle && spreadsheetController.hasDocument;

              return [
                PopupMenuItem(
                  value: _FileMenuAction.newDocument,
                  enabled: idle,
                  child: const Text('New'),
                ),
                PopupMenuItem(
                  value: _FileMenuAction.openDocument,
                  enabled: idle,
                  child: const Text('Open...'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _FileMenuAction.saveDocument,
                  enabled: onDocument,
                  child: const Text('Save'),
                ),
                PopupMenuItem(
                  value: _FileMenuAction.saveAs,
                  enabled: onDocument,
                  child: const Text('Save as...'),
                ),
                PopupMenuItem(
                  value: _FileMenuAction.rename,
                  enabled: onDocument,
                  child: const Text('Rename...'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _FileMenuAction.close,
                  enabled: onDocument,
                  child: const Text('Close'),
                ),
                PopupMenuItem(
                  value: _FileMenuAction.delete,
                  enabled: onDocument,
                  child: const Text('Delete...'),
                ),
                const PopupMenuDivider(),
                ..._plannedEntries<_FileMenuAction>('File'),
              ];
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('File'),
            ),
          ),
          const SizedBox(width: 20),
          const _PlannedMenu('Edit'),
          const SizedBox(width: 20),
          const _PlannedMenu('View'),
          const SizedBox(width: 20),
          const _PlannedMenu('Insert'),
          const SizedBox(width: 20),
          const _PlannedMenu('Data'),
          const SizedBox(width: 20),
          const _PlannedMenu('Tools'),
          const SizedBox(width: 20),
          const _PlannedMenu('Help'),
        ],
        ),
      ),
    );
  }
}
