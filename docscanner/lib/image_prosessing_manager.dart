// function:
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:docscanner/main.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
// my packages:
import 'opencv_helper.dart';
import 'package:docscanner/files_helper.dart';

class ImageProcessingManager {
  static Future<void> processPage(
    String picturePath,
    List<String> versionPaths,
    String pagePath, {
    int? inRatioIndex,
  }) async {
    OpenCVHelper cvHelper = OpenCVHelper();

    // Original
    Uint8List picture = File(picturePath).readAsBytesSync();
    await FilesHelper.saveImage(versionPaths[0], picture);

    // Warped
    var ret = await compute(
      cvHelper.warpImage,
      ParamsWarpImage(versionPaths[0], inRatioIndex: inRatioIndex),
    );
    Uint8List warped = ret.$1;
    List<int> borderCorrectionDepth = ret.$2;
    int ratioIndex = ret.$3;
    writePageMetadata(ratioIndex, pagePath);
    await FilesHelper.saveImage(versionPaths[1], warped);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = await compute(
      cvHelper.processImage1,
      ParamsProcessImage1(versionPaths[1]),
    );
    FilesHelper.saveImage(versionPaths[2], processed1);

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = await compute(
      cvHelper.processImage2,
      ParamsProcessImage2(versionPaths[1], borderCorrectionDepth),
    );
    await FilesHelper.saveImage(versionPaths[3], processed2);
    // Update thumbnails:
    if (inRatioIndex == null) {
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
    } else {
      globalNotifier.triggerEvent(NotifierEvent.reloadPagesThumbnails);
    }
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
  }

  static Future<void> writePageMetadata(int ratioIndex, String pagePath) async {
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    //// Read
    //if (await file.exists()) {
    //  try {
    //    String content = await file.readAsString();
    //    metadata = jsonDecode(content).cast<String, String>();
    //  } catch (e) {
    //    dev.log("Error, savePageMetadata: $e");
    //  }
    //}

    // Write
    metadata["apectRatio"] = ratioIndex.toString();
    await file.writeAsString(jsonEncode(metadata));
    globalNotifier.triggerEvent(NotifierEvent.loadAspectRatio);
  }

  static Future<int?> readPageRatio(String pagePath) async {
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        return int.parse(metadata["apectRatio"]);
      } catch (e) {
        dev.log("Error, readPageRatio: $e");
      }
    }
    dev.log("Warning, readPageRatio: Metadata does not exist for $pagePath");
    return null;
  }
}
