import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/text_style_spec.dart';

/// What the user chose in [ColorPickerDialog].
///
/// [value] is one of:
///  * `null` - "no explicit color": inherit / automatic (the dialog's
///    default option);
///  * [TextStyleSpec.noFill] (`'NONE'`) - explicitly no fill (only offered
///    when the dialog was opened with `allowNoFill`);
///  * an "RRGGBB" hex string.
class ColorPickResult {
  const ColorPickResult(this.value);

  final String? value;
}

/// Converts hue (degrees, any value), saturation and value (both 0..1) to
/// an "RRGGBB" string. Pure arithmetic - no Color objects - so there is
/// nothing to drift between Flutter versions.
String hsvToHex(double hue, double saturation, double value) {
  final h = hue % 360.0;
  final c = value * saturation;
  final hp = h / 60.0;
  final x = c * (1 - ((hp % 2) - 1).abs());
  final m = value - c;

  // The (r, g, b) base for each 60-degree sector of the wheel. Plain
  // lists of doubles rather than record patterns: nothing here should
  // depend on language-feature subtleties.
  final List<double> rgb;

  switch (hp.floor()) {
    case 0:
      rgb = [c, x, 0.0];
      break;
    case 1:
      rgb = [x, c, 0.0];
      break;
    case 2:
      rgb = [0.0, c, x];
      break;
    case 3:
      rgb = [0.0, x, c];
      break;
    case 4:
      rgb = [x, 0.0, c];
      break;
    default:
      rgb = [c, 0.0, x];
      break;
  }

  String channel(double component) => ((component + m) * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0')
      .toUpperCase();

  return '${channel(rgb[0])}${channel(rgb[1])}${channel(rgb[2])}';
}

/// The inverse of [hsvToHex] for a valid "RRGGBB" string:
/// (hue 0..360, saturation 0..1, value 0..1).
(double, double, double) hexToHsv(String hex) {
  final r = int.parse(hex.substring(0, 2), radix: 16) / 255;
  final g = int.parse(hex.substring(2, 4), radix: 16) / 255;
  final b = int.parse(hex.substring(4, 6), radix: 16) / 255;

  final maxChannel = math.max(r, math.max(g, b));
  final minChannel = math.min(r, math.min(g, b));
  final delta = maxChannel - minChannel;

  double hue;

  if (delta == 0) {
    hue = 0;
  } else if (maxChannel == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (maxChannel == g) {
    hue = 60 * ((b - r) / delta + 2);
  } else {
    hue = 60 * ((r - g) / delta + 4);
  }

  final saturation = maxChannel == 0 ? 0.0 : delta / maxChannel;

  return (hue, saturation, maxChannel);
}

/// A color picker: a hue/saturation WHEEL with a brightness slider, a
/// palette of ready-made swatches, a hex field for exact values, and an
/// optional "default" and "no fill" choice. Returns a [ColorPickResult], or
/// null if the user cancels.
///
/// Used for text color, cell fill, grid line color and stripe color - the
/// caller decides what a null / 'NONE' / hex result means for its setting.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.title,
    required this.initial,
    this.defaultLabel = 'Automatic',
    this.allowDefault = true,
    this.allowNoFill = false,
  });

  final String title;

  /// The current value (see [ColorPickResult.value]).
  final String? initial;

  /// Label of the "no explicit color" option, e.g. "Automatic" or "Default".
  final String defaultLabel;

  final bool allowDefault;
  final bool allowNoFill;

  static Future<ColorPickResult?> show(
    BuildContext context, {
    required String title,
    required String? initial,
    String defaultLabel = 'Automatic',
    bool allowDefault = true,
    bool allowNoFill = false,
  }) {
    return showDialog<ColorPickResult>(
      context: context,
      builder: (context) => ColorPickerDialog(
        title: title,
        initial: initial,
        defaultLabel: defaultLabel,
        allowDefault: allowDefault,
        allowNoFill: allowNoFill,
      ),
    );
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  static final RegExp _hexPattern = RegExp(r'^[0-9A-Fa-f]{6}$');

  /// null = default/automatic, 'NONE' = no fill, else "RRGGBB".
  String? _value;

  // The wheel's position. Kept separately from [_value] because several
  // different colors share one hue (every grey has none), so the hue can't
  // always be recovered from the hex - dragging the wheel to the centre
  // must not snap the hue to red.
  double _hue = 0;
  double _saturation = 0;
  double _brightness = 1;

  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _hexController = TextEditingController(
      text: _isHex(_value) ? _value : '',
    );

    if (_isHex(_value)) {
      _syncWheelFromHex(_value!);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  bool _isHex(String? value) => value != null && _hexPattern.hasMatch(value);

  /// Moves the wheel/slider to show [hex], keeping the current hue when
  /// [hex] has none of its own (greys, black, white).
  void _syncWheelFromHex(String hex) {
    final (hue, saturation, brightness) = hexToHsv(hex);

    _saturation = saturation;
    _brightness = brightness;

    if (saturation > 0.0001 && brightness > 0.0001) {
      _hue = hue;
    }
  }

  void _select(String? value) {
    setState(() {
      _value = value;
      _hexError = null;
      _hexController.text = _isHex(value) ? value! : '';

      if (_isHex(value)) {
        _syncWheelFromHex(value!);
      }
    });
  }

  /// The user moved the wheel or the brightness slider.
  void _setHsv({double? hue, double? saturation, double? brightness}) {
    setState(() {
      _hue = hue ?? _hue;
      _saturation = saturation ?? _saturation;
      _brightness = brightness ?? _brightness;

      final hex = hsvToHex(_hue, _saturation, _brightness);
      _value = hex;
      _hexError = null;
      _hexController.text = hex;
    });
  }

  void _onHexChanged(String text) {
    final cleaned = text.trim().replaceFirst('#', '').toUpperCase();

    setState(() {
      if (cleaned.isEmpty) {
        _hexError = null;
      } else if (_hexPattern.hasMatch(cleaned)) {
        _hexError = null;
        _value = cleaned;
        _syncWheelFromHex(cleaned);
      } else {
        _hexError = 'Use 6 hex digits, e.g. FFCC00';
      }
    });
  }

  Widget _optionChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Widget _swatch(String hex) {
    final selected = _value == hex;

    return Tooltip(
      message: '#$hex',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _select(hex),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: parseHexColor(hex),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade400,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = parseHexColor(_value);
    final fullBrightness = parseHexColor(hsvToHex(_hue, _saturation, 1));

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.allowDefault || widget.allowNoFill)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (widget.allowDefault)
                      _optionChip(
                        label: widget.defaultLabel,
                        selected: _value == null,
                        icon: Icons.format_color_reset,
                        onTap: () => _select(null),
                      ),
                    if (widget.allowNoFill)
                      _optionChip(
                        label: 'No fill',
                        selected: _value == TextStyleSpec.noFill,
                        icon: Icons.block,
                        onTap: () => _select(TextStyleSpec.noFill),
                      ),
                  ],
                ),
              if (widget.allowDefault || widget.allowNoFill)
                const SizedBox(height: 12),
              Center(
                child: _ColorWheel(
                  size: 200,
                  hue: _hue,
                  saturation: _saturation,
                  brightness: _brightness,
                  // Nothing is selected yet when the value is null/'NONE',
                  // so don't draw a marker implying a color is chosen.
                  showMarker: _isHex(_value),
                  onChanged: (hue, saturation) =>
                      _setHsv(hue: hue, saturation: saturation),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.brightness_6, size: 18),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _brightness,
                      activeColor: fullBrightness ?? Colors.grey,
                      onChanged: (value) => _setHsv(brightness: value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final hex in kColorPalette) _swatch(hex),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _hexController,
                      onChanged: _onHexChanged,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9A-Fa-f]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Hex color',
                        prefixText: '#',
                        errorText: _hexError,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: previewColor ?? Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: previewColor == null
                        ? Icon(
                            _value == TextStyleSpec.noFill
                                ? Icons.block
                                : Icons.format_color_reset,
                            size: 20,
                            color: Colors.grey.shade600,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // An invalid half-typed hex would otherwise silently apply the
          // PREVIOUS color; make the user finish or fix it.
          onPressed: _hexError != null
              ? null
              : () => Navigator.of(context).pop(ColorPickResult(_value)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// A hue/saturation color wheel: hue runs around the circle, saturation
/// grows from white at the centre to full color at the rim. [brightness]
/// only dims the DRAWING (so the wheel previews the result of the
/// brightness slider); it doesn't change what a tap on the wheel reports,
/// which is always (hue, saturation).
class _ColorWheel extends StatelessWidget {
  const _ColorWheel({
    required this.size,
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.showMarker,
    required this.onChanged,
  });

  final double size;
  final double hue;
  final double saturation;
  final double brightness;
  final bool showMarker;
  final void Function(double hue, double saturation) onChanged;

  void _report(Offset local) {
    final radius = size / 2;
    final delta = local - Offset(radius, radius);
    final distance = delta.distance;

    final newSaturation = (distance / radius).clamp(0.0, 1.0).toDouble();

    // Right at the centre the angle is meaningless (and jitters between
    // 0 and 180); keep the current hue instead of snapping to red.
    if (distance < 2) {
      onChanged(hue, newSaturation);
      return;
    }

    var newHue = math.atan2(delta.dy, delta.dx) * 180 / math.pi;

    if (newHue < 0) {
      newHue += 360;
    }

    onChanged(newHue, newSaturation);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _report(details.localPosition),
      onPanStart: (details) => _report(details.localPosition),
      onPanUpdate: (details) => _report(details.localPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _ColorWheelPainter(
              hue: hue,
              saturation: saturation,
              brightness: brightness,
              showMarker: showMarker,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.showMarker,
  });

  final double hue;
  final double saturation;
  final double brightness;
  final bool showMarker;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Hue: a full sweep starting at 3 o'clock and running clockwise -
    //    the same direction and origin the hit-testing in _report uses.
    final hueSweep = SweepGradient(
      colors: [
        for (int degrees = 0; degrees <= 360; degrees += 60)
          HSVColor.fromAHSV(1, degrees.toDouble(), 1, 1).toColor(),
      ],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = hueSweep.createShader(rect),
    );

    // 2. Saturation: white at the centre fading out to the rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // 3. Brightness: dim the whole wheel to preview the slider.
    if (brightness < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - brightness),
      );
    }

    // 4. Rim, so the wheel reads against any dialog background.
    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.grey.shade500,
    );

    if (!showMarker) {
      return;
    }

    // 5. Marker at the chosen (hue, saturation).
    final angle = hue * math.pi / 180;
    final marker = center + Offset.fromDirection(angle, saturation * radius);

    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ColorWheelPainter old) {
    return old.hue != hue ||
        old.saturation != saturation ||
        old.brightness != brightness ||
        old.showMarker != showMarker;
  }
}
