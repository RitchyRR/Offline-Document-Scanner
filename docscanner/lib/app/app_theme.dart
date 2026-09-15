import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

Future<(ColorScheme, ColorScheme)> generateAdaptiveColorSchemes() async {
  final corePalette = await DynamicColorPlugin.getCorePalette();
  if (corePalette == null) {
    return (
      ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
    );
  }

  return (
    ColorScheme.fromSeed(
      seedColor: Color(corePalette.primary.get(40)),
      brightness: Brightness.light,
    ),
    ColorScheme.fromSeed(
      seedColor: Color(corePalette.primary.get(40)),
      brightness: Brightness.dark,
    ),
  );
}
