import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);

Future<void> initializeAppThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final savedMode = prefs.getString("themeMode");
  appThemeMode.value = switch (savedMode) {
    "light" => ThemeMode.light,
    "dark" => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

Future<void> setAppThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  final savedMode = switch (mode) {
    ThemeMode.light => "light",
    ThemeMode.dark => "dark",
    ThemeMode.system => "system",
  };
  await prefs.setString("themeMode", savedMode);
  appThemeMode.value = mode;
}
