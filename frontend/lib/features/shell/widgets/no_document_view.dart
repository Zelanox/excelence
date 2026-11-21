import 'package:flutter/material.dart';

import '../../../app/app_text.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../file_actions.dart';

/// Shown instead of the grid when no document is open (after Close or
/// Delete, or when nothing could be opened at startup).
class NoDocumentView extends StatelessWidget {
  const NoDocumentView({
    super.key,
    required this.spreadsheetController,
    this.problem,
    this.onRetry,
  });

  final SpreadsheetController spreadsheetController;

  /// Why no document could be opened, if that is the reason we are here.
  final String? problem;

  /// Offered as "Try again" when set.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              appText(context, 'No document open'),
              style: theme.textTheme.titleMedium,
            ),
            if (problem != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  appText(context, problem!),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(appText(context, 'New...')),
                  onPressed: () =>
                      FileActions.newDocument(context, spreadsheetController),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(appText(context, 'Open...')),
                  onPressed: () => FileActions.openDocument(
                    context,
                    spreadsheetController,
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: Text(appText(context, 'Try again')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
