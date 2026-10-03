import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_globals.dart';
import '../../app/app_runtime.dart';
import '../pro/pro_purchase.dart';
import 'aspect_ratio_settings.dart';
import 'default_thumbnail_filter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _compactDocumentsView;

  @override
  void initState() {
    super.initState();
    _loadCompactDocumentsView();
  }

  Future<void> _loadCompactDocumentsView() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _compactDocumentsView = prefs.getBool("compactDocumentsView") ?? true;
    });
  }

  Future<void> _setCompactDocumentsView(bool compact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("compactDocumentsView", compact);
    if (!mounted) return;
    setState(() {
      _compactDocumentsView = compact;
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
            leading: const Icon(Icons.info_outline),
            title: Text(tr("documents.menu.licenses")),
            onTap: () => showLicensePage(
              context: context,
              applicationName: tr("appName"),
              applicationVersion:
                  "${packageInfo.version}+${packageInfo.buildNumber}",
            ),
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
            trailing: _compactDocumentsView == null
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : DropdownButton<bool>(
                    value: _compactDocumentsView,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: true,
                        child: Text(tr("documents.views.compactView")),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text(tr("documents.views.spaciousView")),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) _setCompactDocumentsView(value);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
