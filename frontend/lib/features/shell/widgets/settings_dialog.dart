import 'package:flutter/material.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/sheet_appearance.dart';
import '../../spreadsheet/models/text_style_spec.dart';
import 'color_picker_dialog.dart';
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
        final appearance = sheet?.appearance ?? SheetAppearance.empty;
        final defaultFill = parseHexColor(sheet?.textDefaults.background);

        // A small round color swatch used by the color rows below.
        Widget dot(Color color) => Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: Colors.grey.shade400),
              ),
            );

        return AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 360,
            // Scrolls so the dialog still fits on a short window now that
            // it has several sections.
            child: SingleChildScrollView(
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
                    color: defaultFill ?? Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Sample text   نص تجريبي   123',
                    style: readableOnFill(
                      resolveCellTextStyle(
                        sheet?.textDefaults ?? TextStyleSpec.empty,
                      ),
                      defaultFill,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: dot(
                    parseHexColor(appearance.gridColor) ??
                        Colors.grey.shade300,
                  ),
                  title: const Text('Grid line color'),
                  subtitle: Text(
                    appearance.gridColor == null
                        ? 'Default'
                        : '#${appearance.gridColor}',
                  ),
                  trailing: TextButton(
                    onPressed: sheet == null
                        ? null
                        : () async {
                            final result = await ColorPickerDialog.show(
                              context,
                              title: 'Grid line color',
                              initial: appearance.gridColor,
                              defaultLabel: 'Default',
                            );

                            if (result == null) {
                              return;
                            }

                            spreadsheetController.setAppearance(
                              result.value == null
                                  ? SheetAppearance.empty
                                  : SheetAppearance(gridColor: result.value),
                              reset: result.value == null
                                  ? {SheetAppearance.fieldGridColor}
                                  : const {},
                            );
                          },
                    child: const Text('Change...'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alternating row colors'),
                  subtitle: const Text('Shade every other row'),
                  value: appearance.bandingOn,
                  onChanged: sheet == null
                      ? null
                      : (value) => spreadsheetController.setAppearance(
                            SheetAppearance(banding: value),
                          ),
                ),
                if (appearance.bandingOn)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: dot(
                      parseHexColor(
                            appearance.bandingColor ??
                                SheetAppearance.defaultBandingColor,
                          ) ??
                          Colors.grey.shade200,
                    ),
                    title: const Text('Stripe color'),
                    subtitle: Text(
                      appearance.bandingColor == null
                          ? 'Default'
                          : '#${appearance.bandingColor}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final result = await ColorPickerDialog.show(
                          context,
                          title: 'Stripe color',
                          initial: appearance.bandingColor,
                          defaultLabel: 'Default',
                        );

                        if (result == null) {
                          return;
                        }

                        spreadsheetController.setAppearance(
                          result.value == null
                              ? SheetAppearance.empty
                              : SheetAppearance(bandingColor: result.value),
                          reset: result.value == null
                              ? {SheetAppearance.fieldBandingColor}
                              : const {},
                        );
                      },
                      child: const Text('Change...'),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Grid line and stripe colors are saved in the file but '
                  'only shown in Excelence, not in Excel. Cell fills are '
                  'real Excel fills.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Behavior',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                const _AutoSearchAfterAddRowTile(),
              ],
            ),
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

/// "Search for a new row after adding it" - a per-user/device preference
/// (see AppPreferences), not part of the document, so unlike the rows above
/// it reads and writes AppPreferences directly instead of going through
/// the spreadsheet controller.
///
/// Its own StatefulWidget because the stored value loads asynchronously;
/// the switch shows the default (on) until it arrives, and is disabled
/// until then so an early tap can't be overwritten by the late load.
class _AutoSearchAfterAddRowTile extends StatefulWidget {
  const _AutoSearchAfterAddRowTile();

  @override
  State<_AutoSearchAfterAddRowTile> createState() =>
      _AutoSearchAfterAddRowTileState();
}

class _AutoSearchAfterAddRowTileState
    extends State<_AutoSearchAfterAddRowTile> {
  static const AppPreferences _preferences = AppPreferences();

  bool _value = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = await _preferences.getAutoSearchAfterAddRow();

    if (!mounted) {
      return;
    }

    setState(() {
      _value = stored;
      _loaded = true;
    });
  }

  Future<void> _change(bool value) async {
    setState(() => _value = value);
    await _preferences.setAutoSearchAfterAddRow(value);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Search for a new row after adding it'),
      subtitle: const Text(
        'After adding a row from the status bar, filter the sheet by the '
        'value you typed so the new row is easy to find and fill in.',
      ),
      value: _value,
      onChanged: _loaded ? _change : null,
    );
  }
}
