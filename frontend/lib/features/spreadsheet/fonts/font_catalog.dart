import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sheet_appearance.dart';
import '../models/text_style_spec.dart';

/// One selectable font family.
///
/// [family] is the name stored in the workbook (and shown in the UI), so
/// it should be a name Excel recognises. [renderAs] is the Google Fonts
/// family actually used to DRAW it in this app when that differs - Flutter
/// web can't use fonts installed on the user's machine, so a name like
/// "Calibri" is drawn with its metric-compatible stand-in (Carlito) while
/// the file still says "Calibri".
class FontChoice {
  const FontChoice(this.family, this.group, {this.renderAs});

  final String family;
  final String group;
  final String? renderAs;

  String get googleFamily => renderAs ?? family;
}

/// The fonts offered in the font menu, grouped for display.
///
/// The list is deliberately curated (rather than all ~1,500 Google
/// fonts): common text faces, a monospace pair, the Office names a
/// workbook from Excel will already use, and a good set of Arabic faces.
const List<FontChoice> kFontChoices = [
  // Office-compatible names (drawn with metric-compatible substitutes).
  FontChoice('Calibri', 'Office', renderAs: 'Carlito'),
  FontChoice('Arial', 'Office', renderAs: 'Arimo'),
  FontChoice('Times New Roman', 'Office', renderAs: 'Tinos'),
  FontChoice('Courier New', 'Office', renderAs: 'Cousine'),
  FontChoice('Cambria', 'Office', renderAs: 'Caladea'),
  // Sans-serif
  FontChoice('Roboto', 'Sans-serif'),
  FontChoice('Open Sans', 'Sans-serif'),
  FontChoice('Lato', 'Sans-serif'),
  FontChoice('Montserrat', 'Sans-serif'),
  FontChoice('Noto Sans', 'Sans-serif'),
  // Serif
  FontChoice('Merriweather', 'Serif'),
  FontChoice('Playfair Display', 'Serif'),
  FontChoice('Noto Serif', 'Serif'),
  // Monospace
  FontChoice('Roboto Mono', 'Monospace'),
  FontChoice('Source Code Pro', 'Monospace'),
  // Arabic
  FontChoice('Cairo', 'Arabic'),
  FontChoice('Tajawal', 'Arabic'),
  FontChoice('Almarai', 'Arabic'),
  FontChoice('Amiri', 'Arabic'),
  FontChoice('Noto Naskh Arabic', 'Arabic'),
  FontChoice('Noto Kufi Arabic', 'Arabic'),
  FontChoice('IBM Plex Sans Arabic', 'Arabic'),
  FontChoice('Reem Kufi', 'Arabic'),
];

/// Font sizes offered in the size menu (points).
const List<double> kFontSizes = [
  8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48,
];

/// Swatches offered for text color, as "RRGGBB".
const List<String> kTextColors = [
  '000000', '595959', 'A6A6A6', 'C00000', 'FF0000', 'FF9900',
  'FFD700', '00A651', '00B0F0', '0070C0', '7030A0', 'E91E63',
];

/// The color picker's palette, as "RRGGBB": greys, strong colors, then
/// soft tints that work well as cell fills. Laid out 10 to a row.
const List<String> kColorPalette = [
  'FFFFFF', 'F2F2F2', 'D9D9D9', 'BFBFBF', 'A6A6A6',
  '808080', '595959', '404040', '262626', '000000',
  'C00000', 'FF0000', 'FF9900', 'FFC000', 'FFFF00',
  '92D050', '00B050', '00B0F0', '0070C0', '7030A0',
  'FCE4D6', 'FFF2CC', 'E2EFDA', 'DDEBF7', 'D9E1F2',
  'EDEDED', 'F8CBAD', 'FFE699', 'C6E0B4', 'BDD7EE',
];

/// The grid's built-in text style, used for anything a sheet's default
/// and a cell's own style leave unset.
const TextStyle kGridBaseTextStyle = TextStyle(fontSize: 12);

final Map<String, String> _renderAs = {
  for (final choice in kFontChoices)
    if (choice.renderAs != null) ...{choice.family: choice.renderAs!},
};

final Map<String, TextStyle> _cache = {};

/// The fill a cell is drawn with, or null for the plain default.
///
/// Precedence, strongest first:
///  1. the cell's OWN fill (an explicit "no fill" means plain - it does
///     not fall through to stripes or the sheet default);
///  2. the alternating-row stripe, on every second VISIBLE row
///     ([row] is the row as shown, so stripes stay even when the sheet is
///     sorted or filtered);
///  3. the sheet's default fill.
Color? resolveCellFill({
  required TextStyleSpec own,
  required TextStyleSpec defaults,
  required SheetAppearance appearance,
  required int row,
}) {
  if (own.background == TextStyleSpec.noFill) {
    return null;
  }

  if (own.background != null) {
    return parseHexColor(own.background);
  }

  if (appearance.bandingOn && row.isOdd) {
    return parseHexColor(
      appearance.bandingColor ?? SheetAppearance.defaultBandingColor,
    );
  }

  return parseHexColor(defaults.background);
}

/// If [style] has no explicit text color and [fill] is dark, switches the
/// text to white so it stays readable - the same behavior as Excel's
/// "Automatic" font color. An explicit text color is always respected.
TextStyle readableOnFill(TextStyle style, Color? fill) {
  if (style.color == null && fill != null && fill.computeLuminance() < 0.35) {
    return style.copyWith(color: Colors.white);
  }

  return style;
}

/// Parses an "RRGGBB" color, or null if it isn't one.
Color? parseHexColor(String? hex) {
  if (hex == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return null;
  }

  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// Builds the Flutter [TextStyle] for an effective (already merged)
/// [style], on top of [base].
///
/// A font family that can't be resolved (not a Google font, or the font
/// fails to download - e.g. offline) is not an error: the text simply
/// renders in [base]'s font. Results are cached, since every visible cell
/// asks for its style on every build.
TextStyle resolveCellTextStyle(
  TextStyleSpec style, {
  TextStyle base = kGridBaseTextStyle,
}) {
  final cacheKey = '${base.hashCode}|${style.toJson()}';
  final cached = _cache[cacheKey];

  if (cached != null) {
    return cached;
  }

  final decorations = <TextDecoration>[
    if (style.underline == true) TextDecoration.underline,
    if (style.strikethrough == true) TextDecoration.lineThrough,
  ];

  var result = base.copyWith(
    fontWeight: style.bold == true ? FontWeight.w700 : null,
    fontStyle: style.italic == true ? FontStyle.italic : null,
    fontSize: style.fontSize,
    color: parseHexColor(style.color),
    decoration:
        decorations.isEmpty ? null : TextDecoration.combine(decorations),
  );

  final family = style.fontFamily;

  if (family != null) {
    try {
      result = GoogleFonts.getFont(
        _renderAs[family] ?? family,
        textStyle: result,
      );
    } catch (_) {
      // Unknown family: keep the base font.
    }
  }

  _cache[cacheKey] = result;
  return result;
}

/// A short human-readable summary of a style, e.g. "Cairo, 14, Bold".
/// Returns [emptyLabel] when nothing is set.
String describeTextStyle(
  TextStyleSpec style, {
  String emptyLabel = 'Default',
}) {
  final parts = <String>[
    if (style.fontFamily != null) style.fontFamily!,
    if (style.fontSize != null)
      style.fontSize! == style.fontSize!.roundToDouble()
          ? style.fontSize!.toInt().toString()
          : style.fontSize!.toString(),
    if (style.bold == true) 'Bold',
    if (style.italic == true) 'Italic',
    if (style.underline == true) 'Underline',
    if (style.strikethrough == true) 'Strikethrough',
    if (style.background != null && style.background != TextStyleSpec.noFill)
      'Fill',
  ];

  return parts.isEmpty ? emptyLabel : parts.join(', ');
}
