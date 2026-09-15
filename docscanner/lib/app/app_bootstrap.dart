import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:docscanner/app/app_globals.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  CameraPlatform.instance = AndroidCameraCameraX();
  MobileAds.instance.initialize();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    ErrorLogger.logError(details.exceptionAsString(), details.stack);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogger.logError(error.toString(), stack);
    dev.log("$error | $stack");
    return true;
  };

  pdfrx.pdfrxFlutterInitialize();
}
