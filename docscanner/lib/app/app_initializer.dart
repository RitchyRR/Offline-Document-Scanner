import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_globals.dart';
import 'app_runtime.dart';

class AppInitializer extends StatefulWidget {
  const AppInitializer({
    super.key,
    required this.builder,
    required this.initializeStore,
  });

  final WidgetBuilder builder;
  final Future<void> Function() initializeStore;

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void setState(ui.VoidCallback fn) {
    if (!mounted) {
      dev.log("Warning, AppInitializer not mounted at: ${StackTrace.current}");
      return;
    }
    super.setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    packageInfo = await PackageInfo.fromPlatform();
    Future.microtask(() {
      if (mounted) {
        g.filesHelper.calculateScreenWidth(context);
      } else {
        dev.log("Warning, AppInitializer._initialize(): not mounted");
      }
    });

    const secureStorage = FlutterSecureStorage();
    String? proUnlockedString;
    Object? error;
    try {
      proUnlockedString = await secureStorage.read(key: "proUnlocked");
    } catch (exception) {
      dev.log("SecureStorage read failed: $exception");
      await secureStorage.deleteAll();
      error = exception;
    }

    g.proUnlocked = proUnlockedString == "true";
    setState(() {});
    widget.initializeStore();

    if (error != null) {
      throw StateError("App initialization failed: $error");
    }
    g.filesHelper.repairAll();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
