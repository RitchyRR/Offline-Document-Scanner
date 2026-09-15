import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_initializer.dart';
import 'app/app_router.dart';
import 'app/global_notifier.dart';
import 'features/documents/documents_screen.dart';
import 'features/pro/pro_purchase.dart';

void main() async {
  await bootstrapApp();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale("en"), Locale("de")],
      fallbackLocale: const Locale("en"),
      path: 'assets/lang',

      child: Provider<GlobalNotifier>.value(
        value: globalNotifier,
        child: AppInitializer(
          initializeStore: initStoreInfo,
          builder: (_) => DocScannerApp(
            home: const DocumentsHome(),
            onGenerateRoute: generateAppRoute,
          ),
        ),
      ),
    ),
  );
}
