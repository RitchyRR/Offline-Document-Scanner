import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_globals.dart';
import '../../app/app_runtime.dart';
import '../../app/app_theme_mode.dart';
import '../documents/documents_view.dart';
import '../pro/pro_purchase.dart';
import 'aspect_ratio_settings.dart';
import 'default_thumbnail_filter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DocumentsView? _documentsView;
  String _languageSelection = "system";
  bool _didInitializeLanguageSelection = false;

  @override
  void initState() {
    super.initState();
    _loadDocumentsView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializeLanguageSelection) return;
    _didInitializeLanguageSelection = true;
    _loadLanguageSelection(
      EasyLocalization.of(context)!.savedLocale?.languageCode,
    );
  }

  Future<void> _loadLanguageSelection(String? legacyLanguageCode) async {
    final prefs = await SharedPreferences.getInstance();
    final savedSelection = prefs.getString("languageSelection");
    final selection = switch (savedSelection ?? legacyLanguageCode) {
      "en" => "en",
      "de" => "de",
      _ => "system",
    };
    if (savedSelection == null) {
      await prefs.setString("languageSelection", selection);
    }
    if (!mounted) return;
    setState(() {
      _languageSelection = selection;
    });
  }

  Future<void> _setLanguageSelection(String selection) async {
    final localization = EasyLocalization.of(context)!;
    final prefs = await SharedPreferences.getInstance();
    if (selection == "system") {
      await localization.resetLocale();
      await localization.deleteSaveLocale();
    } else {
      await localization.setLocale(Locale(selection));
    }
    await prefs.setString("languageSelection", selection);
    if (!mounted) return;
    setState(() {
      _languageSelection = selection;
    });
  }

  Future<void> _loadDocumentsView() async {
    final view = await DocumentsView.load();
    if (!mounted) return;
    setState(() {
      _documentsView = view;
    });
  }

  Future<void> _setDocumentsView(DocumentsView view) async {
    await view.save();
    if (!mounted) return;
    setState(() {
      _documentsView = view;
    });
  }

  Future<void> _openProPopup() async {
    await proPopup(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr("settings.title"))),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(g.proUnlocked ? Icons.verified : Icons.lock),
            title: Text(
              g.proUnlocked
                  ? tr("documents.menu.pro1")
                  : tr("documents.menu.pro2"),
            ),
            onTap: _openProPopup,
          ),
          ListTile(
            leading: const Icon(Icons.crop),
            title: Text(tr("documents.menu.ratios")),
            onTap: () => selectAspectRatiosDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.hide_image),
            title: Text(tr("documents.menu.defaultFilter")),
            onTap: () =>
                showDefaultThumbnailVersionDialog(context, unlockPro: proPopup),
          ),
          ListTile(
            leading: const Icon(Icons.view_agenda_outlined),
            title: Text(tr("settings.documentView")),
            trailing: _documentsView == null
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : DropdownButton<DocumentsView>(
                    value: _documentsView,
                    alignment: AlignmentDirectional.centerEnd,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: DocumentsView.standard,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          tr("documents.views.standardView"),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DropdownMenuItem(
                        value: DocumentsView.spacious,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          tr("documents.views.spaciousView"),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DropdownMenuItem(
                        value: DocumentsView.compact,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          tr("documents.views.compactView"),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) _setDocumentsView(value);
                    },
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr("settings.language")),
            trailing: DropdownButton<String>(
              value: _languageSelection,
              alignment: AlignmentDirectional.centerEnd,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: "system",
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    tr(
                      context.deviceLocale.languageCode == "de"
                          ? "settings.languages.systemGerman"
                          : "settings.languages.systemEnglish",
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
                DropdownMenuItem(
                  value: "en",
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    tr("settings.languages.en"),
                    textAlign: TextAlign.end,
                  ),
                ),
                DropdownMenuItem(
                  value: "de",
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    tr("settings.languages.de"),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
              onChanged: (languageCode) {
                if (languageCode != null) {
                  _setLanguageSelection(languageCode);
                }
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr("settings.theme")),
            trailing: ValueListenableBuilder<ThemeMode>(
              valueListenable: appThemeMode,
              builder: (context, themeMode, _) => DropdownButton<ThemeMode>(
                value: themeMode,
                alignment: AlignmentDirectional.centerEnd,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      tr("settings.themes.system"),
                      textAlign: TextAlign.end,
                    ),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      tr("settings.themes.light"),
                      textAlign: TextAlign.end,
                    ),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      tr("settings.themes.dark"),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) setAppThemeMode(mode);
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr("documents.menu.licenses")),
            onTap: () => showLicensePage(
              context: context,
              applicationName: tr("appName"),
              applicationVersion:
                  "${packageInfo.version}+${packageInfo.buildNumber}",
            ),
          ),
        ],
      ),
    );
  }
}
