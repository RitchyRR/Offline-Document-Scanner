import 'dart:developer' as dev show log;
import 'dart:io' show File, FileMode;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;
import 'package:docscanner/app/files_helper.dart';
import 'package:docscanner/app/metadata_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as img;
import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

class AppGlobals {
  // singleton setup:
  static final AppGlobals _instance = AppGlobals._internal();
  factory AppGlobals() {
    return _instance;
  }
  AppGlobals._internal() {
    filesHelper;
  } // private constructor
  List<int> proFilterIndexes = [4, 5];
  int defaultIndex = 3;
  bool proUnlocked = false;
  final FilesHelper filesHelper = FilesHelper();
  final MetadataHelper metadataHelper = MetadataHelper();
  //final ImageProcessingManager imageProcessingManager =
  //    ImageProcessingManager();
  void setDefaultIndex(int? newDefaultIndex) {
    if (!proUnlocked && proFilterIndexes.contains(newDefaultIndex)) {
      newDefaultIndex = 3;
    }
    defaultIndex = newDefaultIndex ?? (proUnlocked ? 4 : 3);
  }

  List<AspectRatioInfo> commonAspectRatios = [];
  List<AspectRatioInfo> availableAspectRatios = [];
  void translateAspectRatios(BuildContext contextIn) {
    commonAspectRatios = [
      //// International Standard (ISO 216 - A, B, C series)
      AspectRatioInfo("DIN", "DIN A/B/C (√2:1)", math.sqrt2), // ~1.414
      //// North American Paper Sizes (Letter, Legal, etc.)
      AspectRatioInfo("Letter", "Letter (8.5x11″, US)", 11 / 8.5), // ~1.294
      AspectRatioInfo("Legal", "Legal (8.5x14″, US)", 14 / 8.5), // ~1.647
      AspectRatioInfo(
        "Tabloid",
        "Tabloid / Ledger (11x17″, US)",
        17 / 11,
      ), // ~1.545
      //// Cards & Paper
      AspectRatioInfo(
        tr("aspectRatios.businessCard"),
        tr("aspectRatios.description.businessCard"),
        3.5 / 2,
      ), // 1.75
      AspectRatioInfo(
        tr("aspectRatios.creditCard"),
        tr("aspectRatios.description.creditCard"),
        85.6 / 53.98,
      ), // ~1.586
      AspectRatioInfo(
        tr("aspectRatios.square"),
        tr("aspectRatios.description.square"),
        1.0,
      ), // 1.0
      //// Photo & Monitors
      AspectRatioInfo("5:4", tr("aspectRatios.description.5:4"), 5 / 4), // 1.25
      AspectRatioInfo(
        "4:3",
        tr("aspectRatios.description.4:3"),
        4 / 3,
      ), // 1.333
      AspectRatioInfo(
        "16:9",
        tr("aspectRatios.description.16:9"),
        16 / 9,
      ), // ~1.777
      AspectRatioInfo(
        "16:10",
        tr("aspectRatios.description.16:10"),
        16 / 10,
      ), // 1.6
      AspectRatioInfo(
        "21:9",
        tr("aspectRatios.description.21:9"),
        21 / 9,
      ), // ~2.333
    ];
  }

  static img.DecodeInfo? getPngInfo(Uint8List bytes) {
    return img.PngDecoder().startDecode(bytes);
  }

  static Future<img.DecodeInfo?> getImageInfo(String imagePath) async {
    final decoder = findDecoderForNamedImage(imagePath);
    final bytes = await readFile(imagePath);
    return decoder!.startDecode(bytes!);
  }

  static Future<img.DecodeInfo?> getImageBytesInfo(
    Uint8List bytes,
    String extension,
  ) async {
    final decoder = findDecoderForNamedImage(".$extension");
    return decoder!.startDecode(bytes);
  }
}

final g = AppGlobals();

class AspectRatioInfo {
  final String name;
  final String description;
  final double value;

  AspectRatioInfo(this.name, this.description, this.value);
}

enum NotifierEvent {
  loadPagesThumbnails,
  loadDocsThumbnails,
  imagesDeleted,
  setState,
}

enum PopUpType { share, save, delete }

class ErrorLogger {
  static Future<void> log(String message) async {
    final now = DateTime.now();
    final logMessage = '[$now] $message\n';

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/error_log.txt');
    await file.writeAsString(logMessage, mode: FileMode.append);
  }

  static Future<void> logError(String error, StackTrace? stack) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logFile = File('${dir.path}/error_log.txt');
      final now = DateTime.now().toIso8601String();
      final message = '[$now] ERROR: $error\nSTACKTRACE:\n$stack\n\n';
      dev.log(message);
      await logFile.writeAsString(message, mode: FileMode.append);
    } catch (e) {
      Fluttertoast.showToast(msg: "Could not log error: $e");
    }
  }
}
