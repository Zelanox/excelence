import 'package:flutter/material.dart';

import '../spreadsheet/controllers/spreadsheet_controller.dart';
import '../spreadsheet/models/document_name.dart';
import 'file_error.dart';
import 'widgets/document_name_dialog.dart';
import 'widgets/file_explorer_dialog.dart';

enum _CloseChoice { cancel, closeAnyway, retry }

/// The File menu's actions with their dialogs and messages. Shared by the
/// menu bar and the "No document open" screen, so both behave the same.
///
/// Every failure is shown as a sentence the user can act on; the technical
/// detail is in the log.
class FileActions {
  FileActions._();

  static Future<void> newDocument(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final path = await FileExplorerDialog.show(
      context,
      spreadsheetController: controller,
      mode: FileExplorerMode.create,
    );

    if (path == null || !context.mounted) return;

    await _run(
      context,
      'create the document',
      () => controller.newDocument(path),
    );
  }

  static Future<void> openDocument(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final path = await FileExplorerDialog.show(
      context,
      spreadsheetController: controller,
      mode: FileExplorerMode.open,
    );

    if (path == null || !context.mounted) return;

    await _run(
      context,
      'open the document',
      () => controller.loadDocument(path),
    );
  }

  static Future<void> save(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await controller.saveDocument();
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(describeFileError(error, 'save the document')),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              if (context.mounted) {
                save(context, controller);
              }
            },
          ),
        ),
      );
    }
  }

  static Future<void> saveAs(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final current = controller.openFilename;

    if (current == null) return;

    final messenger = ScaffoldMessenger.of(context);

    final result = await DocumentNameDialog.show(
      context,
      title: 'Save as',
      confirmLabel: 'Save',
      initial: '${documentNameWithoutExtension(current)} copy',
      current: current,
      onSubmit: controller.saveDocumentAs,
    );

    if (result != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Saved a copy as ${result.name}.')),
      );
    }
  }

  static Future<void> rename(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final current = controller.openFilename;

    if (current == null) return;

    final messenger = ScaffoldMessenger.of(context);

    final result = await DocumentNameDialog.show(
      context,
      title: 'Rename document',
      confirmLabel: 'Rename',
      initial: documentNameWithoutExtension(current),
      current: current,
      onSubmit: controller.renameDocument,
    );

    if (result != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Renamed to ${result.name}.')),
      );
    }
  }

  /// Saves and closes. If the save fails the user chooses: try again, close
  /// without saving, or keep the document open.
  static Future<void> close(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    var force = false;

    while (true) {
      final result = await controller.closeCurrentDocument(force: force);

      if (result.ok) return;

      if (!result.saveFailed) {
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }

      if (!context.mounted) return;

      final choice = await showDialog<_CloseChoice>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could not save your changes'),
          content: const Text(
            'The document is still open. You can try saving again, or close '
            'it anyway and lose the changes that were not saved.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_CloseChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_CloseChoice.closeAnyway),
              child: const Text('Close anyway'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_CloseChoice.retry),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

      if (choice == _CloseChoice.retry) continue;

      if (choice == _CloseChoice.closeAnyway) {
        force = true;
        continue;
      }

      return;
    }
  }

  static Future<void> delete(
    BuildContext context,
    SpreadsheetController controller,
  ) async {
    final name = controller.openFilename;

    if (name == null) return;

    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text(
          'This permanently deletes the file from the server. '
          'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final result = await controller.deleteDocument();

    if (result.ok) {
      messenger.showSnackBar(SnackBar(content: Text('Deleted $name.')));
      return;
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Could not delete the document'),
        content: Text(result.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Runs a controller action; a failure becomes a readable snackbar.
  static Future<void> _run(
    BuildContext context,
    String action,
    Future<void> Function() work,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await work();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeFileError(error, action))),
      );
    }
  }
}
