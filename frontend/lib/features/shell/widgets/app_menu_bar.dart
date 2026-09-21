import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import 'file_explorer_dialog.dart';

enum _FileMenuAction { newDocument, openDocument, saveDocument }

/// The app's top menu bar. Only "File" is wired up for now (New/Open/
/// Save via FileExplorerDialog and SpreadsheetController) - Edit/View/
/// Insert/Data/Tools/Help stay as plain labels until they get the same
/// treatment.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({
    super.key,
    required this.spreadsheetController,
  });

  final SpreadsheetController spreadsheetController;

  Future<void> _handleFileAction(
    BuildContext context,
    _FileMenuAction action,
  ) async {
    switch (action) {
      case _FileMenuAction.newDocument:
        final path = await FileExplorerDialog.show(
          context,
          spreadsheetController: spreadsheetController,
          mode: FileExplorerMode.create,
        );
        if (path == null || !context.mounted) return;
        await _run(context, () => spreadsheetController.newDocument(path));
        break;

      case _FileMenuAction.openDocument:
        final path = await FileExplorerDialog.show(
          context,
          spreadsheetController: spreadsheetController,
          mode: FileExplorerMode.open,
        );
        if (path == null || !context.mounted) return;
        await _run(context, () => spreadsheetController.loadDocument(path));
        break;

      case _FileMenuAction.saveDocument:
        await _run(context, spreadsheetController.saveDocument);
        break;
    }
  }

  /// Runs a controller action, showing a snackbar on failure. Success is
  /// silent - the grid updating (for New/Open) or simply not erroring
  /// (for Save) is feedback enough, matching how the rest of the app
  /// (e.g. GridColumnHeader's rename/delete) only surfaces failures.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
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
      child: Row(
        children: [
          PopupMenuButton<_FileMenuAction>(
            tooltip: '',
            offset: const Offset(0, 24),
            onSelected: (action) => _handleFileAction(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _FileMenuAction.newDocument,
                child: Text('New'),
              ),
              PopupMenuItem(
                value: _FileMenuAction.openDocument,
                child: Text('Open...'),
              ),
              PopupMenuItem(
                value: _FileMenuAction.saveDocument,
                child: Text('Save'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('File'),
            ),
          ),
          const SizedBox(width: 20),
          const Text('Edit'),
          const SizedBox(width: 20),
          const Text('View'),
          const SizedBox(width: 20),
          const Text('Insert'),
          const SizedBox(width: 20),
          const Text('Data'),
          const SizedBox(width: 20),
          const Text('Tools'),
          const SizedBox(width: 20),
          const Text('Help'),
        ],
      ),
    );
  }
}