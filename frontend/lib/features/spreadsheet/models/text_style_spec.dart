import 'package:flutter/foundation.dart';

/// A PARTIAL text style: every field is optional, and null means "not set
/// here - inherit". Used at two levels, mirroring the backend's CellStyle:
///
///  * [SheetModel.textDefaults] - the sheet-wide default text style.
///  * [CellModel.style] - a cell's own overrides on top of that default.
///
/// A cell is drawn with its overrides merged over the sheet default
/// ([mergedOver]); anything still unset after that falls through to the
/// grid's built-in text style.
///
/// Field names in [toJson]/[fromJson] are the backend's snake_case names,
/// and [bold]..[color] are also the keys used in a "reset" set - see
/// [fieldBold] etc.
@immutable
class TextStyleSpec {
  const TextStyleSpec({
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
    this.fontFamily,
    this.fontSize,
    this.color,
  });

  static const TextStyleSpec empty = TextStyleSpec();

  static const String fieldBold = 'bold';
  static const String fieldItalic = 'italic';
  static const String fieldUnderline = 'underline';
  static const String fieldStrikethrough = 'strikethrough';
  static const String fieldFontFamily = 'font_family';
  static const String fieldFontSize = 'font_size';
  static const String fieldColor = 'color';

  static const Set<String> allFields = {
    fieldBold,
    fieldItalic,
    fieldUnderline,
    fieldStrikethrough,
    fieldFontFamily,
    fieldFontSize,
    fieldColor,
  };

  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strikethrough;
  final String? fontFamily;
  final double? fontSize;

  /// "RRGGBB", upper-case, no leading "#" (the backend's format).
  final String? color;

  bool get isEmpty =>
      bold == null &&
      italic == null &&
      underline == null &&
      strikethrough == null &&
      fontFamily == null &&
      fontSize == null &&
      color == null;

  /// Tolerant of missing/odd values - never throws on server data.
  factory TextStyleSpec.fromJson(Map<String, dynamic> json) {
    bool? asBool(Object? value) => value is bool ? value : null;

    return TextStyleSpec(
      bold: asBool(json[fieldBold]),
      italic: asBool(json[fieldItalic]),
      underline: asBool(json[fieldUnderline]),
      strikethrough: asBool(json[fieldStrikethrough]),
      fontFamily: json[fieldFontFamily] is String
          ? json[fieldFontFamily] as String
          : null,
      fontSize: json[fieldFontSize] is num
          ? (json[fieldFontSize] as num).toDouble()
          : null,
      color: json[fieldColor] is String ? json[fieldColor] as String : null,
    );
  }

  /// Only the fields that are set - an empty style is `{}`.
  Map<String, dynamic> toJson() {
    return {
      if (bold != null) fieldBold: bold,
      if (italic != null) fieldItalic: italic,
      if (underline != null) fieldUnderline: underline,
      if (strikethrough != null) fieldStrikethrough: strikethrough,
      if (fontFamily != null) fieldFontFamily: fontFamily,
      if (fontSize != null) fieldFontSize: fontSize,
      if (color != null) fieldColor: color,
    };
  }

  /// This style's set fields win; unset ones fall back to [base].
  TextStyleSpec mergedOver(TextStyleSpec base) {
    return TextStyleSpec(
      bold: bold ?? base.bold,
      italic: italic ?? base.italic,
      underline: underline ?? base.underline,
      strikethrough: strikethrough ?? base.strikethrough,
      fontFamily: fontFamily ?? base.fontFamily,
      fontSize: fontSize ?? base.fontSize,
      color: color ?? base.color,
    );
  }

  /// A copy with [set]'s fields applied and every field named in [reset]
  /// cleared back to "inherit". Mirrors the backend's apply_patch, so the
  /// optimistic local update and the persisted result agree.
  TextStyleSpec applied(TextStyleSpec set, {Set<String> reset = const {}}) {
    final merged = set.mergedOver(this);

    return TextStyleSpec(
      bold: reset.contains(fieldBold) ? null : merged.bold,
      italic: reset.contains(fieldItalic) ? null : merged.italic,
      underline: reset.contains(fieldUnderline) ? null : merged.underline,
      strikethrough:
          reset.contains(fieldStrikethrough) ? null : merged.strikethrough,
      fontFamily: reset.contains(fieldFontFamily) ? null : merged.fontFamily,
      fontSize: reset.contains(fieldFontSize) ? null : merged.fontSize,
      color: reset.contains(fieldColor) ? null : merged.color,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TextStyleSpec &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline &&
        other.strikethrough == strikethrough &&
        other.fontFamily == fontFamily &&
        other.fontSize == fontSize &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(
        bold,
        italic,
        underline,
        strikethrough,
        fontFamily,
        fontSize,
        color,
      );

  @override
  String toString() => 'TextStyleSpec(${toJson()})';
}
