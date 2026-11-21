import 'package:flutter/material.dart';

import '../../../app/app_text.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../dictation_controller.dart';
import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/text_style_spec.dart';
import '../../spreadsheet/presentation_v2/actions/text_format_actions.dart';
import 'color_picker_dialog.dart';
import 'font_options_dialog.dart';
import 'settings_dialog.dart';

/// Below this width the Font button shows only its icon (the tooltip keeps
/// the full description).
const double compactToolbarWidth = 600;

// Horizontal padding on each side of the toolbar.
const double _toolbarPadding = 10;

/// The top toolbar: text formatting for the selected cells (font, colors,
/// alignment, and emphasis) plus Settings. The formatting buttons scroll
/// sideways when the window is too narrow to show them all; Settings stays
/// pinned at the right.
///
/// File open/save/undo/redo icons used to sit here but were removed -
/// they were bare Icon widgets with no onTap/IconButton wrapping them at
/// all, not wired to anything. Row/column insert and delete are handled
/// directly on the grid itself (the hover "+" handles past the last
/// row/column in SpreadsheetGrid for insert, a right-click context menu
/// on GridColumnHeader/GridRowHeader for delete/rename), so those were
/// never toolbar candidates to begin with. spreadsheetController and
/// viewportController are both still accepted here even though only the
/// former is currently used (by the settings gear, to open
/// SettingsDialog) - kept rather than dropped from the constructor,
/// since real toolbar actions (a working Save button, Undo/Redo) are
/// the natural next thing to add here and viewportController will be
/// needed for at least some of those.
class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
    this.dictation,
    this.onLocaleChanged,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  /// Speech to text. When set and supported on this platform (PCs only), a
  /// microphone button is shown.
  final DictationController? dictation;
  final ValueChanged<Locale>? onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      // At least 48 high, but free to grow so a large text size can't
      // clip the buttons.
      constraints: const BoxConstraints(minHeight: 48),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: _toolbarPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      // Rebuilds on selection moves (viewportController) as well as on
      // sheet changes, so the buttons always reflect the active cell.
      child: AnimatedBuilder(
        animation: Listenable.merge([
          spreadsheetController,
          viewportController,
          ?dictation,
        ]),
        builder: (context, _) {
          final sheet = spreadsheetController.spreadsheet?.activeSheet;
          final hasCells =
              sheet != null &&
              sheet.rows.isNotEmpty &&
              sheet.headers.isNotEmpty;
          final selection = viewportController.selection;
          final active = hasCells
              ? spreadsheetController.effectiveTextStyleAt(
                  selection.activeRow,
                  selection.activeColumn,
                )
              : TextStyleSpec.empty;

          Widget flagButton({
            required IconData icon,
            required String tooltip,
            required String field,
          }) {
            final on = isTextFlagOn(active, field);

            return IconButton(
              icon: Icon(icon),
              tooltip: tooltip,
              isSelected: on,
              style: IconButton.styleFrom(
                backgroundColor: on
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              onPressed: hasCells
                  ? () => toggleTextFlag(
                      spreadsheetController: spreadsheetController,
                      viewportController: viewportController,
                      field: field,
                    )
                  : null,
            );
          }

          // A color button: the icon with a bar underneath showing the
          // active cell's current color (like Excel's font/fill buttons).
          Widget colorButton({
            required IconData icon,
            required String tooltip,
            required String? current,
            required String title,
            required String defaultLabel,
            required bool allowNoFill,
            required void Function(String? value) onPicked,
          }) {
            final bar = parseHexColor(current);

            return IconButton(
              tooltip: tooltip,
              onPressed: hasCells
                  ? () async {
                      final result = await ColorPickerDialog.show(
                        context,
                        title: title,
                        initial: current,
                        defaultLabel: defaultLabel,
                        allowNoFill: allowNoFill,
                      );

                      if (result != null) {
                        onPicked(result.value);
                      }
                    }
                  : null,
              icon: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(height: 2),
                  Container(
                    width: 20,
                    height: 4,
                    decoration: BoxDecoration(
                      color: bar ?? Colors.transparent,
                      border: bar == null
                          ? Border.all(color: Colors.grey.shade400, width: 0.5)
                          : null,
                    ),
                  ),
                ],
              ),
            );
          }

          // Applies a picker result for ONE style field to the selection:
          // null means "back to inherit", anything else sets it.
          void applyColor(String field, String? value) {
            final set = value == null
                ? TextStyleSpec.empty
                : field == TextStyleSpec.fieldColor
                ? TextStyleSpec(color: value)
                : TextStyleSpec(background: value);

            spreadsheetController.applyTextStyle(
              startRow: selection.startRow,
              startColumn: selection.startColumn,
              endRow: selection.endRow,
              endColumn: selection.endColumn,
              set: set,
              reset: value == null ? {field} : const {},
            );
          }

          void applyAlignment(String field, String value) {
            final set = value == 'reset'
                ? TextStyleSpec.empty
                : field == TextStyleSpec.fieldHorizontalAlignment
                ? TextStyleSpec(horizontalAlignment: value)
                : TextStyleSpec(verticalAlignment: value);

            spreadsheetController.applyTextStyle(
              startRow: selection.startRow,
              startColumn: selection.startColumn,
              endRow: selection.endRow,
              endColumn: selection.endColumn,
              set: set,
              reset: value == 'reset' ? {field} : const {},
            );
          }

          Widget alignmentButton({
            required String field,
            required String tooltip,
            required IconData icon,
            required List<({String value, String label, IconData icon})> items,
          }) {
            return PopupMenuButton<String>(
              tooltip: tooltip,
              enabled: hasCells,
              onSelected: (value) => applyAlignment(field, value),
              icon: Icon(icon),
              itemBuilder: (context) => [
                for (final item in items)
                  PopupMenuItem(
                    value: item.value,
                    child: Row(
                      children: [
                        Icon(item.icon, size: 20),
                        const SizedBox(width: 8),
                        Text(appText(context, item.label)),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'reset',
                  child: Text(appText(context, 'Reset alignment')),
                ),
              ],
            );
          }

          final fontLabel = describeTextStyle(
            active,
            emptyLabel: appText(context, 'Font...'),
          );

          Future<void> openFontDialog() async {
            final result = await FontOptionsDialog.show(
              context,
              title: appText(context, 'Font for selected cells'),
              initial: active,
              resetLabel: appText(context, 'Reset to sheet default'),
              allowNoFill: true,
            );

            if (result == null || result.isEmpty) {
              return;
            }

            spreadsheetController.applyTextStyle(
              startRow: selection.startRow,
              startColumn: selection.startColumn,
              endRow: selection.endRow,
              endColumn: selection.endColumn,
              set: result.set,
              reset: result.reset,
            );
          }

          // The formatting buttons. They scroll sideways when they do not
          // fit; Settings stays pinned at the end so it is always reachable.
          final actions = <Widget>[
            flagButton(
              icon: Icons.format_bold,
              tooltip: appText(context, 'Bold (Ctrl+B)'),
              field: TextStyleSpec.fieldBold,
            ),
            flagButton(
              icon: Icons.format_italic,
              tooltip: appText(context, 'Italic (Ctrl+I)'),
              field: TextStyleSpec.fieldItalic,
            ),
            flagButton(
              icon: Icons.format_underlined,
              tooltip: appText(context, 'Underline (Ctrl+U)'),
              field: TextStyleSpec.fieldUnderline,
            ),
            flagButton(
              icon: Icons.format_strikethrough,
              tooltip: appText(context, 'Strikethrough'),
              field: TextStyleSpec.fieldStrikethrough,
            ),
            colorButton(
              icon: Icons.format_color_text,
              tooltip: appText(context, 'Text color'),
              current: active.color,
              title: appText(context, 'Text color'),
              defaultLabel: appText(context, 'Automatic'),
              allowNoFill: false,
              onPicked: (value) => applyColor(TextStyleSpec.fieldColor, value),
            ),
            colorButton(
              icon: Icons.format_color_fill,
              tooltip: appText(context, 'Fill color'),
              current: active.background,
              title: appText(context, 'Fill color'),
              defaultLabel: appText(context, 'Sheet default'),
              allowNoFill: true,
              onPicked: (value) =>
                  applyColor(TextStyleSpec.fieldBackground, value),
            ),
            alignmentButton(
              field: TextStyleSpec.fieldHorizontalAlignment,
              tooltip: appText(context, 'Horizontal alignment'),
              icon: switch (active.horizontalAlignment) {
                'center' => Icons.format_align_center,
                'right' => Icons.format_align_right,
                _ => Icons.format_align_left,
              },
              items: const [
                (
                  value: 'left',
                  label: 'Align left',
                  icon: Icons.format_align_left,
                ),
                (
                  value: 'center',
                  label: 'Align center',
                  icon: Icons.format_align_center,
                ),
                (
                  value: 'right',
                  label: 'Align right',
                  icon: Icons.format_align_right,
                ),
              ],
            ),
            alignmentButton(
              field: TextStyleSpec.fieldVerticalAlignment,
              tooltip: appText(context, 'Vertical alignment'),
              icon: switch (active.verticalAlignment) {
                'top' => Icons.vertical_align_top,
                'bottom' => Icons.vertical_align_bottom,
                _ => Icons.vertical_align_center,
              },
              items: const [
                (
                  value: 'top',
                  label: 'Align top',
                  icon: Icons.vertical_align_top,
                ),
                (
                  value: 'center',
                  label: 'Align middle',
                  icon: Icons.vertical_align_center,
                ),
                (
                  value: 'bottom',
                  label: 'Align bottom',
                  icon: Icons.vertical_align_bottom,
                ),
              ],
            ),
            const SizedBox(width: 4),
          ];

          // A sheet's RTL setting affects only the grid; toolbar controls
          // keep their physical left-to-right order in every interface.
          return LayoutBuilder(
            builder: (context, constraints) {
              // Compared on the full toolbar width, padding included.
              final compact =
                  constraints.maxWidth + 2 * _toolbarPadding <
                  compactToolbarWidth;

              return Row(
                textDirection: TextDirection.ltr,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: Directionality.of(context) == TextDirection.rtl,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...actions,
                          if (compact)
                            IconButton(
                              icon: const Icon(Icons.text_fields),
                              tooltip: fontLabel,
                              onPressed: hasCells ? openFontDialog : null,
                            )
                          else
                            TextButton.icon(
                              icon: const Icon(Icons.text_fields),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 240,
                                ),
                                child: Text(
                                  fontLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onPressed: hasCells ? openFontDialog : null,
                            ),
                          if (dictation != null && dictation!.isSupported)
                            IconButton(
                              icon: Icon(
                                Icons.mic,
                                color: dictation!.isListening
                                    ? Colors.red
                                    : null,
                              ),
                              tooltip: dictation!.isListening
                                  ? appText(
                                      context,
                                      'Stop speech to text (Ctrl+Shift+M)',
                                    )
                                  : appText(
                                      context,
                                      'Speech to text (Ctrl+Shift+M)',
                                    ),
                              onPressed:
                                  hasCells && !dictation!.isBusy ||
                                      dictation!.isListening
                                  ? dictation!.toggle
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: appText(context, 'Settings'),
                    onPressed: () => SettingsDialog.show(
                      context,
                      spreadsheetController: spreadsheetController,
                      dictation: dictation,
                      onLocaleChanged: onLocaleChanged,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
