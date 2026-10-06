import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'app_navigation.dart';
import 'app_theme.dart';
import 'app_theme_mode.dart';

class DocScannerApp extends StatelessWidget {
  const DocScannerApp({
    super.key,
    required this.home,
    required this.onGenerateRoute,
  });

  final Widget home;
  final RouteFactory onGenerateRoute;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(ColorScheme, ColorScheme)>(
      future: generateAdaptiveColorSchemes(),
      builder: (context, snapshot) {
        final (lightTheme, darkTheme) =
            snapshot.data ??
            (
              ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
              ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
            );

        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeMode,
          builder: (context, themeMode, _) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            navigatorKey: navigatorKey,
            navigatorObservers: [routeObserver],
            title: "Offline Document Scanner",
            initialRoute: "/",
            onGenerateRoute: onGenerateRoute,
            builder: FToastBuilder(),
            theme: _themeData(
              lightTheme,
              lightThemePrimary: lightTheme.primary,
            ),
            darkTheme: _themeData(
              darkTheme,
              lightThemePrimary: lightTheme.primary,
              isDark: true,
            ),
            themeMode: themeMode,
            home: home,
            onUnknownRoute: (_) => MaterialPageRoute(builder: (_) => home),
          ),
        );
      },
    );
  }

  ThemeData _themeData(
    ColorScheme colorScheme, {
    required Color lightThemePrimary,
    bool isDark = false,
  }) {
    return ThemeData(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      colorScheme: colorScheme,
      primaryColor: lightThemePrimary,
      useMaterial3: true,
      cardTheme: isDark
          ? CardThemeData(color: colorScheme.surfaceContainerHigh)
          : null,
      popupMenuTheme: PopupMenuThemeData(color: colorScheme.primaryContainer),
    );
  }
}
