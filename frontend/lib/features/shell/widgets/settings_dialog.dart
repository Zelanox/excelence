import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/text_style_spec.dart';
import 'font_options_dialog.dart';

/// The app's settings dialog, opened via the gear icon in the toolbar
/// (see Toolbar).
///
/// Scoped today to just the one setting that actually exists and needs
/// an explicit UI control (sheet direction - column width has no
/// equivalent entry here since it's set by dragging a column header's
/// edge, not through a dialog). Structured as sections (just "Sheet" for
/// now) so future settings - cell text formatting, alternating row
/// colors, search preferences, language - each get their own section
/// added here rather than needing this dialog rebuilt from scratch.
///
/// Per-document settings (this dialog's "Sheet" section: RTL today,
/// eventually cell/table formatting) read and write through
/// [spreadsheetController], the same as everywhere else those settings
/// are touched (e.g. GridColumnHeader's resize handle for width). A
/// later per-user/device section (search preferences, language) would
/// instead read/write AppPreferences directly, with no controller
/// involvement - that's a deliberate difference in this dialog's rows,
/// not an oversight, since those settings don't belong to the document.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({
    super.key,
    required this.spreadsheetController,
  });

  final SpreadsheetController spreadsheetController;

  static Future<void> show(
    BuildContext context, {
    required SpreadsheetController spreadsheetController,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        spreadsheetController: spreadsheetController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: spreadsheetController,
      builder: (context, _) {
        final sheet = spreadsheetController.spreadsheet?.activeSheet;

        return AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sheet',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                // Disabled (rather than hidden) when no document is
                // loaded yet, rather than the dialog being unreachable
                // during that brief window - the toolbar has no other
                // way to signal "settings aren't ready yet" short of
                // hiding the gear icon itself, which would be a more
                // surprising affordance to take away than a disabled
                // row here.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Right-to-left'),
                  subtitle: const Text(
                    'Mirrors column order and row numbers to the right edge for this sheet.',
                  ),
                  value: sheet?.isRtl ?? false,
                  onChanged: sheet == null
                      ? null
                      : (value) => spreadsheetController.setRtl(value),
                ),
                const SizedBox(height: 16),
                Text(
                  'Text',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                // The sheet-wide default font. Individual cells can still
                // override it from the toolbar (Font... / B / I / U).
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Default font'),
                  subtitle: Text(
                    describeTextStyle(
                      sheet?.textDefaults ?? TextStyleSpec.empty,
                      emptyLabel: 'App default',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: sheet == null
                        ? null
                        : () async {
                            final result = await FontOptionsDialog.show(
                              context,
                              title: 'Default font for this sheet',
                              initial: sheet.textDefaults,
                              resetLabel: 'Reset to app default',
                            );

                            if (result == null || result.isEmpty) {
                              return;
                            }

                            spreadsheetController.setTextDefaults(
                              result.set,
                              reset: result.reset,
                            );
                          },
                    child: const Text('Customize...'),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Sample text   نص تجريبي   123',
                    style: resolveCellTextStyle(
                      sheet?.textDefaults ?? TextStyleSpec.empty,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}
