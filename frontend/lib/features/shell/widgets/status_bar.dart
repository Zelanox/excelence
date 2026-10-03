import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';

/// The bottom status bar: save state, a quick-add-row field, active
/// sheet name, and zoom level.
///
/// Previously every value here (`"Ready"`, `"Sheet1"`, `"100%"`) was a
/// hardcoded string reflecting nothing real. Each is now wired to actual
/// controller state - see [SpreadsheetController.isSaving] for save
/// state, the active sheet's name for the sheet-name display, and
/// [ViewportController]'s viewport.zoom for zoom - rather than removed,
/// since all three correspond to something the app genuinely tracks;
/// only the toolbar's fully-decorative icons (nothing behind them at
/// all) were actually removed as part of this cleanup.
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: AnimatedBuilder(
        animation:
            Listenable.merge([spreadsheetController, viewportController]),
        builder: (context, _) {
          final sheet = spreadsheetController.spreadsheet?.activeSheet;
          final zoomPercent =
              (viewportController.viewport.zoom * 100).round();

          return Row(
            children: [
              Text(
                // Autosave runs a moment after the last change, so there's
                // a short "Unsaved changes" window between editing and
                // "Saving...".
                spreadsheetController.isSaving
                    ? 'Saving...'
                    : spreadsheetController.hasUnsavedChanges
                        ? 'Unsaved changes'
                        : 'All changes saved',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _QuickAddRowField(
                  spreadsheetController: spreadsheetController,
                ),
              ),
              const SizedBox(width: 16),
              Text(sheet?.name ?? ''),
              const SizedBox(width: 20),
              Text('$zoomPercent%'),
            ],
          );
        },
      ),
    );
  }
}

/// The status bar's quick-add-row field: typing a value and pressing
/// Enter appends a new row to the active sheet with that value in its
/// first column (see
/// SpreadsheetController.appendRowWithFirstColumnValue). Deliberately a
/// StatefulWidget of its own rather than inline in StatusBar.build, so
/// its TextEditingController survives StatusBar's AnimatedBuilder
/// rebuilds (save-state/zoom changes firing mid-typing shouldn't reset
/// whatever the user has half-typed).
class _QuickAddRowField extends StatefulWidget {
  const _QuickAddRowField({required this.spreadsheetController});

  final SpreadsheetController spreadsheetController;

  @override
  State<_QuickAddRowField> createState() => _QuickAddRowFieldState();
}

class _QuickAddRowFieldState extends State<_QuickAddRowField> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(String value) async {
    if (_isSubmitting) {
      return;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.spreadsheetController
          .appendRowWithFirstColumnValue(trimmed);
      _controller.clear();
    } catch (error) {
      // Same convention as SpreadsheetGrid._showError: a snackbar, since
      // this is a direct user-initiated action awaiting its own result
      // (unlike a background fire-and-forget save, where
      // lastSaveError/isSaving are the right surface - insertRow here
      // is awaited directly and can genuinely throw, so silently
      // swallowing it would leave the user's typed value stuck with no
      // feedback at all).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add row: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: TextField(
        controller: _controller,
        enabled: !_isSubmitting,
        style: const TextStyle(fontSize: 12),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          hintText: 'Add row with value...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade400,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        onSubmitted: _handleSubmit,
      ),
    );
  }
}
