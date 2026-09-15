import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_globals.dart';
import '../../app/filter_names.dart';

Future<void> loadDefaultThumbnailVersion() async {
  // Set Default Thumbnail Version
  final prefs = await SharedPreferences.getInstance();
  final String? defaultThumbnailString = prefs.getString(
    "defaultThumnailVersion",
  );
  int? defaultThumbnailIndex;
  if (defaultThumbnailString != null) {
    defaultThumbnailIndex = versionNamesInternal.indexOf(
      defaultThumbnailString,
    );
  }
  g.setDefaultIndex(defaultThumbnailIndex);
  prefs.setString(
    "defaultThumnailVersion",
    versionNamesInternal[g.defaultIndex],
  );
}

Future<bool> showDefaultThumbnailVersionDialog(
  BuildContext context, {
  required Future<bool> Function(BuildContext context) unlockPro,
}) async {
  int selectedIndex = g.defaultIndex;
  bool allowed = true;
  bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hide_image, size: 30),
                SizedBox(width: 12),
                Flexible(child: Text(tr("popup.defaultThumbnail.title"))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr("popup.defaultThumbnail.text")),
                RadioGroup<int>(
                  groupValue: selectedIndex,
                  onChanged: (int? value) {
                    if (value != null) {
                      if (!g.proUnlocked &&
                          g.proFilterIndexes.contains(value)) {
                        allowed = false;
                      } else {
                        allowed = true;
                      }
                      setStateDialog(() {
                        selectedIndex = value;
                      });
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(
                      versionNames.length - 1,
                      (index) => RadioListTile<int>(
                        title: Row(
                          children: [
                            Text(versionNames[index + 1]),
                            !g.proUnlocked &&
                                    g.proFilterIndexes.contains(index + 1)
                                ? const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(Icons.lock),
                                  )
                                : const SizedBox(),
                          ],
                        ),
                        value: index + 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false), // Cancel
                child: Text(tr("popup.cancel")),
              ),
              allowed
                  ? ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      child: Text(tr("popup.ok")),
                    )
                  : ElevatedButton.icon(
                      icon: Icon(Icons.lock),
                      onPressed: () async {
                        await unlockPro(context);
                        setStateDialog(() {});
                      },
                      label: Text(tr("popup.unlock")),
                    ),
            ],
          );
        },
      );
    },
  );

  if (confirmed == true && allowed) {
    _setDefaultThumbnail(selectedIndex);
    return true;
  }
  return false;
}

Future<bool> _setDefaultThumbnail(final int newDefaultThumnailIndex) async {
  final prefs = await SharedPreferences.getInstance();
  g.setDefaultIndex(newDefaultThumnailIndex);
  return await prefs.setString(
    "defaultThumnailVersion",
    versionNamesInternal[g.defaultIndex],
  );
}
