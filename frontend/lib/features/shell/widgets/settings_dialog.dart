import 'package:flutter/material.dart';

import '../../../app/app_text.dart';
import '../../../core/connection/connection_scope.dart';
import '../../../core/connection/server_connection.dart';
import '../../../core/preferences/app_preferences.dart';
import '../dictation_controller.dart';
import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/fonts/font_catalog.dart';
import '../../spreadsheet/models/sheet_appearance.dart';
import '../../spreadsheet/models/text_style_spec.dart';
import 'color_picker_dialog.dart';
import 'connection_form.dart';
import 'font_options_dialog.dart';

/// The app's settings dialog, opened via the gear icon in the toolbar
/// (see Toolbar).
///
/// Groups per-document sheet settings with per-user interface and speech
/// language preferences.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({
    super.key,
    required this.spreadsheetController,
    this.dictation,
    this.onLocaleChanged,
  });

  final SpreadsheetController spreadsheetController;
  final DictationController? dictation;
  final ValueChanged<Locale>? onLocaleChanged;

  static Future<void> show(
    BuildContext context, {
    required SpreadsheetController spreadsheetController,
    DictationController? dictation,
    ValueChanged<Locale>? onLocaleChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        spreadsheetController: spreadsheetController,
        dictation: dictation,
        onLocaleChanged: onLocaleChanged,
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

        // The Connection tab only exists when the app provides a connection
        // (it always does in the real app).
        final connectionScope = ConnectionScope.maybeOf(context);
        final navigator = Navigator.of(context);

        final contentHeight = (MediaQuery.sizeOf(context).height - 220)
            .clamp(100.0, 420.0)
            .toDouble();

        return DefaultTabController(
          length: connectionScope == null ? 3 : 4,
          child: AlertDialog(
            title: Text(appText(context, 'Settings')),
            content: SizedBox(
              // Wide enough for all four tabs where the screen allows it.
              width: (MediaQuery.sizeOf(context).width - 80)
                  .clamp(260.0, 420.0)
                  .toDouble(),
              height: contentHeight,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    tabs: [
                      Tab(text: appText(context, 'General')),
                      Tab(text: appText(context, 'Sheet')),
                      Tab(text: appText(context, 'Appearance')),
                      if (connectionScope != null)
                        Tab(text: appText(context, 'Connection')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _settingsSectionTitle(context, 'Language'),
                              _InterfaceLanguageTile(
                                onLocaleChanged: onLocaleChanged,
                              ),
                              if (dictation?.isSupported ?? false)
                                _SpeechLanguageTile(dictation: dictation!),
                              const SizedBox(height: 16),
                              _settingsSectionTitle(context, 'Behavior'),
                              const _AutoSearchAfterAddRowTile(),
                            ],
                          ),
                        ),
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _settingsSectionTitle(context, 'Sheet'),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(appText(context, 'Right-to-left')),
                                subtitle: Text(
                                  appText(
                                    context,
                                    'Mirrors column order and row numbers to the right edge for this sheet.',
                                  ),
                                ),
                                value: sheet?.isRtl ?? false,
                                onChanged: sheet == null
                                    ? null
                                    : (value) =>
                                          spreadsheetController.setRtl(value),
                              ),
                              const SizedBox(height: 16),
                              _settingsSectionTitle(context, 'Text'),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(appText(context, 'Default font')),
                                subtitle: Text(
                                  describeTextStyle(
                                    sheet?.textDefaults ?? TextStyleSpec.empty,
                                    emptyLabel: appText(context, 'App default'),
                                  ),
                                ),
                                trailing: TextButton(
                                  onPressed: sheet == null
                                      ? null
                                      : () async {
                                          final result =
                                              await FontOptionsDialog.show(
                                                context,
                                                title: appText(
                                                  context,
                                                  'Default font for this sheet',
                                                ),
                                                initial: sheet.textDefaults,
                                                resetLabel: appText(
                                                  context,
                                                  'Reset to app default',
                                                ),
                                              );

                                          if (result == null ||
                                              result.isEmpty) {
                                            return;
                                          }

                                          spreadsheetController.setTextDefaults(
                                            result.set,
                                            reset: result.reset,
                                          );
                                        },
                                  child: Text(appText(context, 'Customize...')),
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: defaultFill ?? Colors.white,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Sample text   نص تجريبي   123',
                                  style: readableOnFill(
                                    resolveCellTextStyle(
                                      sheet?.textDefaults ??
                                          TextStyleSpec.empty,
                                    ),
                                    defaultFill,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _settingsSectionTitle(context, 'Appearance'),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: dot(
                                  parseHexColor(appearance.gridColor) ??
                                      Colors.grey.shade300,
                                ),
                                title: Text(
                                  appText(context, 'Grid line color'),
                                ),
                                subtitle: Text(
                                  appearance.gridColor == null
                                      ? appText(context, 'Default')
                                      : '#${appearance.gridColor}',
                                ),
                                trailing: TextButton(
                                  onPressed: sheet == null
                                      ? null
                                      : () async {
                                          final result =
                                              await ColorPickerDialog.show(
                                                context,
                                                title: appText(
                                                  context,
                                                  'Grid line color',
                                                ),
                                                initial: appearance.gridColor,
                                                defaultLabel: appText(
                                                  context,
                                                  'Default',
                                                ),
                                              );

                                          if (result == null) {
                                            return;
                                          }

                                          spreadsheetController.setAppearance(
                                            result.value == null
                                                ? SheetAppearance.empty
                                                : SheetAppearance(
                                                    gridColor: result.value,
                                                  ),
                                            reset: result.value == null
                                                ? {
                                                    SheetAppearance
                                                        .fieldGridColor,
                                                  }
                                                : const {},
                                          );
                                        },
                                  child: Text(appText(context, 'Change...')),
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  appText(context, 'Alternating row colors'),
                                ),
                                subtitle: Text(
                                  appText(context, 'Shade every other row'),
                                ),
                                value: appearance.bandingOn,
                                onChanged: sheet == null
                                    ? null
                                    : (value) =>
                                          spreadsheetController.setAppearance(
                                            SheetAppearance(banding: value),
                                          ),
                              ),
                              if (appearance.bandingOn)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: dot(
                                    parseHexColor(
                                          appearance.bandingColor ??
                                              SheetAppearance
                                                  .defaultBandingColor,
                                        ) ??
                                        Colors.grey.shade200,
                                  ),
                                  title: Text(appText(context, 'Stripe color')),
                                  subtitle: Text(
                                    appearance.bandingColor == null
                                        ? appText(context, 'Default')
                                        : '#${appearance.bandingColor}',
                                  ),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      final result =
                                          await ColorPickerDialog.show(
                                            context,
                                            title: appText(
                                              context,
                                              'Stripe color',
                                            ),
                                            initial: appearance.bandingColor,
                                            defaultLabel: appText(
                                              context,
                                              'Default',
                                            ),
                                          );

                                      if (result == null) {
                                        return;
                                      }

                                      spreadsheetController.setAppearance(
                                        result.value == null
                                            ? SheetAppearance.empty
                                            : SheetAppearance(
                                                bandingColor: result.value,
                                              ),
                                        reset: result.value == null
                                            ? {
                                                SheetAppearance
                                                    .fieldBandingColor,
                                              }
                                            : const {},
                                      );
                                    },
                                    child: Text(appText(context, 'Change...')),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                appText(
                                  context,
                                  'Grid line and stripe colors are saved in the file but only shown in Excelence, not in Excel. Cell fills are real Excel fills.',
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        if (connectionScope != null)
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _settingsSectionTitle(context, 'Server'),
                                if (!connectionScope.savedOnDevice) ...[
                                  Text(
                                    appText(
                                      context,
                                      'This address comes from the build and is not saved on this device. Press Save to keep it.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                ConnectionForm(
                                  initial: connectionScope.connection,
                                  onSave: (connection) async {
                                    // Send this device's pending edits to the
                                    // old server first; if that fails, stop
                                    // rather than lose them.
                                    try {
                                      await spreadsheetController
                                          .flushPendingChanges();
                                    } catch (_) {
                                      throw const ConnectionChangeBlocked(
                                        'Your open document could not be saved first, so the address was not changed. Try again.',
                                      );
                                    }

                                    navigator.pop();
                                    await connectionScope.change(connection);
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(appText(context, 'Done')),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _settingsSectionTitle(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(
      appText(context, title),
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );
}

class _InterfaceLanguageTile extends StatelessWidget {
  const _InterfaceLanguageTile({this.onLocaleChanged});

  final ValueChanged<Locale>? onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(appText(context, 'Interface language')),
      trailing: DropdownButton<Locale>(
        value: locale.languageCode == 'ar'
            ? const Locale('ar')
            : const Locale('en'),
        items: [
          DropdownMenuItem(
            value: const Locale('en'),
            child: Text(appText(context, 'English')),
          ),
          DropdownMenuItem(
            value: const Locale('ar'),
            child: Text(appText(context, 'Arabic')),
          ),
        ],
        onChanged: onLocaleChanged == null
            ? null
            : (value) {
                if (value != null) {
                  onLocaleChanged!(value);
                }
              },
      ),
    );
  }
}

class _SpeechLanguageTile extends StatefulWidget {
  const _SpeechLanguageTile({required this.dictation});

  final DictationController dictation;

  @override
  State<_SpeechLanguageTile> createState() => _SpeechLanguageTileState();
}

class _SpeechLanguageTileState extends State<_SpeechLanguageTile> {
  static const AppPreferences _preferences = AppPreferences();

  String _localeId = 'ar_SA';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final localeId = await _preferences.getSpeechLanguage();

    if (!mounted) {
      return;
    }

    setState(() {
      _localeId = localeId;
      _loaded = true;
    });
    widget.dictation.localeId = localeId == 'system' ? 'auto' : localeId;
  }

  Future<void> _change(String? localeId) async {
    if (localeId == null) {
      return;
    }

    setState(() => _localeId = localeId);
    widget.dictation.localeId = localeId == 'system' ? 'auto' : localeId;
    await _preferences.setSpeechLanguage(localeId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(context, 'Speech language'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          appText(
            context,
            'Arabic is the default speech language. The offline small model is about 460 MB and may run slower on CPU. It downloads on first use; audio stays on this device.',
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SizedBox(
            width: 240,
            child: DropdownButton<String>(
              isExpanded: true,
              value: _localeId,
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(appText(context, 'Use system language')),
                ),
                DropdownMenuItem(
                  value: 'ar_SA',
                  child: Text(appText(context, 'Arabic (Saudi Arabia)')),
                ),
              ],
              onChanged: _loaded ? _change : null,
            ),
          ),
        ),
      ],
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
      title: Text(appText(context, 'Search for a new row after adding it')),
      subtitle: Text(
        appText(
          context,
          'After adding a row from the status bar, filter the sheet by the value you typed so the new row is easy to find and fill in.',
        ),
      ),
      value: _value,
      onChanged: _loaded ? _change : null,
    );
  }
}
