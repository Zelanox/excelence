import 'package:flutter/material.dart';

import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/text_style_spec.dart';
import 'color_picker_dialog.dart';

/// What the user chose in [FontOptionsDialog], expressed as a change to
/// apply rather than a full style: [set] holds only the fields the user
/// actually changed, and [reset] names fields to return to "inherit".
/// Both empty means nothing changed.
class FontOptionsResult {
  const FontOptionsResult({
    this.set = TextStyleSpec.empty,
    this.reset = const {},
  });

  final TextStyleSpec set;
  final Set<String> reset;

  bool get isEmpty => set.isEmpty && reset.isEmpty;
}

/// A font options dialog with a live preview: family, size, bold / italic
/// / underline / strikethrough, text color and cell fill.
///
/// Used for both levels of text formatting - the sheet-wide default
/// (opened from Settings) and the selected cells (opened from the
/// toolbar). The caller passes the style to start from as [initial];
/// the result is the DIFFERENCE from it, so changing only the size on a
/// cell doesn't also pin that cell's font family and color as overrides
/// (which would stop it following later changes to the sheet default).
class FontOptionsDialog extends StatefulWidget {
  const FontOptionsDialog({
    super.key,
    required this.title,
    required this.initial,
    required this.resetLabel,
    this.allowNoFill = false,
  });

  final String title;

  /// Whether "No fill" is offered for the fill color. True when editing
  /// cells (one cell can opt out of a sheet-wide fill); false for the sheet
  /// default itself, where "no fill" is just "not set".
  final bool allowNoFill;

  /// The style the dialog starts from (null fields show as "Default").
  final TextStyleSpec initial;

  /// Label for the button that clears every field back to "inherit".
  final String resetLabel;

  static Future<FontOptionsResult?> show(
    BuildContext context, {
    required String title,
    required TextStyleSpec initial,
    required String resetLabel,
    bool allowNoFill = false,
  }) {
    return showDialog<FontOptionsResult>(
      context: context,
      builder: (context) => FontOptionsDialog(
        title: title,
        initial: initial,
        resetLabel: resetLabel,
        allowNoFill: allowNoFill,
      ),
    );
  }

  @override
  State<FontOptionsDialog> createState() => _FontOptionsDialogState();
}

class _FontOptionsDialogState extends State<FontOptionsDialog> {
  late bool _bold;
  late bool _italic;
  late bool _underline;
  late bool _strikethrough;
  String? _family;
  double? _size;
  String? _color;
  String? _background;

  static const String _groupPrefix = '__group__';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _bold = initial.bold ?? false;
    _italic = initial.italic ?? false;
    _underline = initial.underline ?? false;
    _strikethrough = initial.strikethrough ?? false;
    _family = initial.fontFamily;
    _size = initial.fontSize;
    _color = initial.color;
    _background = initial.background;
  }

  /// What the preview (and a later Apply) is based on.
  TextStyleSpec get _working => TextStyleSpec(
        bold: _bold,
        italic: _italic,
        underline: _underline,
        strikethrough: _strikethrough,
        fontFamily: _family,
        fontSize: _size,
        color: _color,
        background: _background,
      );

  /// The change from [FontOptionsDialog.initial] to the current choices.
  FontOptionsResult _result() {
    final initial = widget.initial;
    final reset = <String>{};

    // A flag counts as unchanged when it matches what it started as,
    // treating "unset" and "off" as the same - toggling bold on and back
    // off must not leave an explicit "not bold" override behind.
    bool? flag(bool? before, bool after, String field) {
      if ((before ?? false) == after) {
        return null;
      }
      return after;
    }

    T? value<T>(T? before, T? after, String field) {
      if (before == after) {
        return null;
      }
      if (after == null) {
        reset.add(field);
        return null;
      }
      return after;
    }

    final set = TextStyleSpec(
      bold: flag(initial.bold, _bold, TextStyleSpec.fieldBold),
      italic: flag(initial.italic, _italic, TextStyleSpec.fieldItalic),
      underline:
          flag(initial.underline, _underline, TextStyleSpec.fieldUnderline),
      strikethrough: flag(
        initial.strikethrough,
        _strikethrough,
        TextStyleSpec.fieldStrikethrough,
      ),
      fontFamily: value<String>(
        initial.fontFamily,
        _family,
        TextStyleSpec.fieldFontFamily,
      ),
      fontSize: value<double>(
        initial.fontSize,
        _size,
        TextStyleSpec.fieldFontSize,
      ),
      color: value<String>(initial.color, _color, TextStyleSpec.fieldColor),
      background: value<String>(
        initial.background,
        _background,
        TextStyleSpec.fieldBackground,
      ),
    );

    return FontOptionsResult(set: set, reset: reset);
  }

  List<DropdownMenuItem<String?>> _familyItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('Default')),
    ];

    final known = kFontChoices.map((choice) => choice.family).toSet();

    // A family that came from a workbook but isn't in the catalog (say
    // "Verdana") still has to be a valid dropdown value, or the dropdown
    // would assert. It is listed first and drawn in the default font.
    if (_family != null && !known.contains(_family)) {
      items.add(DropdownMenuItem<String?>(
        value: _family,
        child: Text(_family!),
      ));
    }

    String? currentGroup;

    for (final choice in kFontChoices) {
      if (choice.group != currentGroup) {
        currentGroup = choice.group;
        items.add(DropdownMenuItem<String?>(
          value: '$_groupPrefix${choice.group}',
          enabled: false,
          child: Text(
            choice.group.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ));
      }

      items.add(DropdownMenuItem<String?>(
        value: choice.family,
        child: Text(
          choice.family,
          style: resolveCellTextStyle(
            TextStyleSpec(fontFamily: choice.family),
            base: const TextStyle(fontSize: 15),
          ),
        ),
      ));
    }

    return items;
  }

  List<DropdownMenuItem<double?>> _sizeItems() {
    final sizes = [...kFontSizes];

    if (_size != null && !sizes.contains(_size)) {
      sizes
        ..add(_size!)
        ..sort();
    }

    return [
      const DropdownMenuItem<double?>(value: null, child: Text('Default')),
      for (final size in sizes)
        DropdownMenuItem<double?>(
          value: size,
          child: Text(
            size == size.roundToDouble()
                ? size.toInt().toString()
                : size.toString(),
          ),
        ),
    ];
  }

  Widget _flagButton({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer : null,
      ),
      onPressed: () => setState(() => onChanged(!selected)),
    );
  }

  /// A "label  [swatch] value  Change..." row that opens the color picker.
  Widget _colorRow({
    required String label,
    required String? value,
    required String defaultLabel,
    required bool allowNoFill,
    required ValueChanged<String?> onPicked,
  }) {
    final color = parseHexColor(value);
    final description = value == null
        ? defaultLabel
        : value == TextStyleSpec.noFill
            ? 'No fill'
            : '#$value';

    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? Colors.white,
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: color == null
              ? Icon(Icons.block, size: 14, color: Colors.grey.shade500)
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(description)),
        TextButton(
          onPressed: () async {
            final result = await ColorPickerDialog.show(
              context,
              title: label,
              initial: value,
              defaultLabel: defaultLabel,
              allowNoFill: allowNoFill,
            );

            if (result != null) {
              onPicked(result.value);
            }
          },
          child: const Text('Change...'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewFill = parseHexColor(_background);
    final previewStyle = readableOnFill(
      resolveCellTextStyle(_working),
      previewFill,
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Font', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              DropdownButton<String?>(
                isExpanded: true,
                value: _family,
                menuMaxHeight: 360,
                items: _familyItems(),
                onChanged: (value) => setState(() => _family = value),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Size',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 4),
                        DropdownButton<double?>(
                          isExpanded: true,
                          value: _size,
                          menuMaxHeight: 320,
                          items: _sizeItems(),
                          onChanged: (value) => setState(() => _size = value),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _flagButton(
                    icon: Icons.format_bold,
                    tooltip: 'Bold',
                    selected: _bold,
                    onChanged: (value) => _bold = value,
                  ),
                  _flagButton(
                    icon: Icons.format_italic,
                    tooltip: 'Italic',
                    selected: _italic,
                    onChanged: (value) => _italic = value,
                  ),
                  _flagButton(
                    icon: Icons.format_underlined,
                    tooltip: 'Underline',
                    selected: _underline,
                    onChanged: (value) => _underline = value,
                  ),
                  _flagButton(
                    icon: Icons.format_strikethrough,
                    tooltip: 'Strikethrough',
                    selected: _strikethrough,
                    onChanged: (value) => _strikethrough = value,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _colorRow(
                label: 'Text color',
                value: _color,
                defaultLabel: 'Automatic',
                allowNoFill: false,
                onPicked: (value) => setState(() => _color = value),
              ),
              _colorRow(
                label: 'Fill',
                value: _background,
                defaultLabel: widget.allowNoFill ? 'Sheet default' : 'None',
                allowNoFill: widget.allowNoFill,
                onPicked: (value) => setState(() => _background = value),
              ),
              const SizedBox(height: 16),
              Text('Preview', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: previewFill ?? Colors.white,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The quick brown fox jumps over the lazy dog',
                      style: previewStyle,
                    ),
                    const SizedBox(height: 6),
                    Text('0123456789   Aa Bb Cc', style: previewStyle),
                    const SizedBox(height: 6),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          'أبجد هوز حطي كلمن  ١٢٣٤٥٦٧٨٩٠',
                          style: previewStyle,
                        ),
                      ),
                    ),
                  ],
                ),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            FontOptionsResult(reset: TextStyleSpec.allFields),
          ),
          child: Text(widget.resetLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_result()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
