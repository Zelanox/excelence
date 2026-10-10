import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/text_style_spec.dart';
import '../../spreadsheet/presentation_v2/actions/text_format_actions.dart';
import 'color_picker_dialog.dart';
import 'font_options_dialog.dart';
import 'settings_dialog.dart';

/// The top toolbar: text formatting for the selected cells (bold, italic,
/// underline, strikethrough, and a Font... dialog with preview) plus
/// Settings.
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
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      // Rebuilds on selection moves (viewportController) as well as on
      // sheet changes, so the buttons always reflect the active cell.
      child: AnimatedBuilder(
        animation: Listenable.merge([
          spreadsheetController,
          viewportController,
        ]),
        builder: (context, _) {
          final sheet = spreadsheetController.spreadsheet?.activeSheet;
          final hasCells =
              sheet != null && sheet.rows.isNotEmpty && sheet.headers.isNotEmpty;
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

          return Row(
            children: [
              flagButton(
                icon: Icons.format_bold,
                tooltip: 'Bold (Ctrl+B)',
                field: TextStyleSpec.fieldBold,
              ),
              flagButton(
                icon: Icons.format_italic,
                tooltip: 'Italic (Ctrl+I)',
                field: TextStyleSpec.fieldItalic,
              ),
              flagButton(
                icon: Icons.format_underlined,
                tooltip: 'Underline (Ctrl+U)',
                field: TextStyleSpec.fieldUnderline,
              ),
              flagButton(
                icon: Icons.format_strikethrough,
                tooltip: 'Strikethrough',
                field: TextStyleSpec.fieldStrikethrough,
              ),
              colorButton(
                icon: Icons.format_color_text,
                tooltip: 'Text color',
                current: active.color,
                title: 'Text color',
                defaultLabel: 'Automatic',
                allowNoFill: false,
                onPicked: (value) =>
                    applyColor(TextStyleSpec.fieldColor, value),
              ),
              colorButton(
                icon: Icons.format_color_fill,
                tooltip: 'Fill color',
                current: active.background,
                title: 'Fill color',
                defaultLabel: 'Sheet default',
                allowNoFill: true,
                onPicked: (value) =>
                    applyColor(TextStyleSpec.fieldBackground, value),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                icon: const Icon(Icons.text_fields),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    describeTextStyle(active, emptyLabel: 'Font...'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: hasCells
                    ? () async {
                        final result = await FontOptionsDialog.show(
                          context,
                          title: 'Font for selected cells',
                          initial: active,
                          resetLabel: 'Reset to sheet default',
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
                    : null,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () => SettingsDialog.show(
                  context,
                  spreadsheetController: spreadsheetController,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
