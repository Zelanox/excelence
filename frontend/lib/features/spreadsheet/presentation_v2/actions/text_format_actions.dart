import '../../controllers/spreadsheet_controller.dart';
import '../../controllers/viewport_controller.dart';
import '../../models/text_style_spec.dart';

/// Whether [field] (one of TextStyleSpec.fieldBold / fieldItalic /
/// fieldUnderline / fieldStrikethrough) is on in [style].
bool isTextFlagOn(TextStyleSpec style, String field) {
  switch (field) {
    case TextStyleSpec.fieldBold:
      return style.bold ?? false;
    case TextStyleSpec.fieldItalic:
      return style.italic ?? false;
    case TextStyleSpec.fieldUnderline:
      return style.underline ?? false;
    case TextStyleSpec.fieldStrikethrough:
      return style.strikethrough ?? false;
    default:
      return false;
  }
}

/// Toggles bold / italic / underline / strikethrough for the whole
/// current selection, like a toolbar button or Ctrl+B/I/U.
///
/// The new state is decided by the ACTIVE cell (the one being edited or
/// last clicked): if it currently has the flag on, the whole selection
/// is turned off, otherwise on - the same rule spreadsheets use, so a
/// mixed selection ends up uniform instead of flipping cell by cell.
void toggleTextFlag({
  required SpreadsheetController spreadsheetController,
  required ViewportController viewportController,
  required String field,
}) {
  final selection = viewportController.selection;
  final current = spreadsheetController.effectiveTextStyleAt(
    selection.activeRow,
    selection.activeColumn,
  );
  final turnOn = !isTextFlagOn(current, field);

  spreadsheetController.applyTextStyle(
    startRow: selection.startRow,
    startColumn: selection.startColumn,
    endRow: selection.endRow,
    endColumn: selection.endColumn,
    set: TextStyleSpec(
      bold: field == TextStyleSpec.fieldBold ? turnOn : null,
      italic: field == TextStyleSpec.fieldItalic ? turnOn : null,
      underline: field == TextStyleSpec.fieldUnderline ? turnOn : null,
      strikethrough:
          field == TextStyleSpec.fieldStrikethrough ? turnOn : null,
    ),
  );
}
