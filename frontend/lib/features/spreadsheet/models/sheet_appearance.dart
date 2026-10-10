import 'package:flutter/foundation.dart';

/// Sheet-level display settings: the grid line color and alternating row
/// colors. Mirrors the backend's SheetAppearance - a PARTIAL set where null
/// means "built-in default".
///
/// These are display settings rather than cell content, so they are not
/// part of undo history, and (unlike cell fills) they have no Excel
/// equivalent: they are saved in the file but only Excelence shows them.
@immutable
class SheetAppearance {
  const SheetAppearance({
    this.gridColor,
    this.banding,
    this.bandingColor,
  });

  static const SheetAppearance empty = SheetAppearance();

  static const String fieldGridColor = 'grid_color';
  static const String fieldBanding = 'banding';
  static const String fieldBandingColor = 'banding_color';

  /// The stripe color used when banding is on and none was chosen.
  static const String defaultBandingColor = 'F2F2F2';

  /// "RRGGBB", or null for the built-in grid line color.
  final String? gridColor;

  /// Alternating row colors on (true) / off (false or null).
  final bool? banding;

  /// "RRGGBB" of the shaded rows; null means [defaultBandingColor].
  final String? bandingColor;

  bool get bandingOn => banding == true;

  factory SheetAppearance.fromJson(Map<String, dynamic> json) {
    return SheetAppearance(
      gridColor:
          json[fieldGridColor] is String ? json[fieldGridColor] as String : null,
      banding: json[fieldBanding] is bool ? json[fieldBanding] as bool : null,
      bandingColor: json[fieldBandingColor] is String
          ? json[fieldBandingColor] as String
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (gridColor != null) fieldGridColor: gridColor,
      if (banding != null) fieldBanding: banding,
      if (bandingColor != null) fieldBandingColor: bandingColor,
    };
  }

  bool get isEmpty => gridColor == null && banding == null && bandingColor == null;

  /// A copy with [set]'s fields applied and fields named in [reset]
  /// cleared - the same semantics as the backend's apply_patch.
  SheetAppearance applied(SheetAppearance set, {Set<String> reset = const {}}) {
    return SheetAppearance(
      gridColor: reset.contains(fieldGridColor)
          ? null
          : (set.gridColor ?? gridColor),
      banding: reset.contains(fieldBanding) ? null : (set.banding ?? banding),
      bandingColor: reset.contains(fieldBandingColor)
          ? null
          : (set.bandingColor ?? bandingColor),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SheetAppearance &&
        other.gridColor == gridColor &&
        other.banding == banding &&
        other.bandingColor == bandingColor;
  }

  @override
  int get hashCode => Object.hash(gridColor, banding, bandingColor);

  @override
  String toString() => 'SheetAppearance(${toJson()})';
}
