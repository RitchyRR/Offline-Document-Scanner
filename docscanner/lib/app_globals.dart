import 'dart:math' as math;
import 'package:docscanner/files_helper.dart';
//import 'package:docscanner/image_prosessing_manager.dart';
import 'package:docscanner/metadata_helper.dart';

class AppGlobals {
  // singleton setup:
  static final AppGlobals _instance = AppGlobals._internal();
  factory AppGlobals() {
    return _instance;
  }
  AppGlobals._internal() {
    filesHelper;
  } // private constructor

  bool? proUnlocked;
  final FilesHelper filesHelper = FilesHelper();
  final MetadataHelper metadataHelper = MetadataHelper();
  //final ImageProcessingManager imageProcessingManager =
  //    ImageProcessingManager();

  final List<AspectRatioInfo> commonAspectRatios = [
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
    AspectRatioInfo("Business Card", "Business Card (3.5x2″)", 3.5 / 2), // 1.75
    AspectRatioInfo(
      "Credit Card",
      "Credit Card (ISO/ID-1, 85.6x53.98 mm)",
      85.6 / 53.98,
    ), // ~1.586
    AspectRatioInfo("Square", "1:1 Square (Notes, Covers)", 1.0), // 1.0
    //// Photo & Monitors
    AspectRatioInfo("5:4", "5:4 (Photo, Old Monitors)", 5 / 4), // 1.25
    AspectRatioInfo("4:3", "4:3 (Photo)", 4 / 3), // 1.333
    AspectRatioInfo("16:9", "16:9 (Video, Widescreen)", 16 / 9), // ~1.777
    AspectRatioInfo("16:10", "16:10 (Widescreen)", 16 / 10), // 1.6
    AspectRatioInfo("21:9", "21:9 (Ultrawide, Cinema)", 21 / 9), // ~2.333
  ];
  List<AspectRatioInfo> availableAspectRatios = [];
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
  loadPageMetadata,
  photoSaved,
  warpSaved,
  processed1Saved,
  processed2Saved,
  imagesDeleted,
  setState,
}

enum PopUpType { share, save, delete }
