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
    bool? orientation,
  }) async {
    OpenCVHelper cvHelper = OpenCVHelper();

    // Original
    Uint8List picture = File(picturePath).readAsBytesSync();
    await FilesHelper.saveImage(versionPaths[0], picture);

    // Warped
    var ret = await compute(
      cvHelper.warpImage,
      ParamsWarpImage(
        versionPaths[0],
        inRatioIndex: inRatioIndex,
        orientation: orientation,
      ),
    );
    Uint8List warped = ret.$1;
    List<int> borderCorrectionDepth = ret.$2;
    int ratioIndex = ret.$3;
    orientation = ret.$4;
    writePageMetadata(ratioIndex, orientation, pagePath);
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
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnailsAndInfo);
  }

  static Future<void> writePageMetadata(
    int ratioIndex,
    bool orientationPortrait,
    String pagePath,
  ) async {
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    if (await file.exists()) {
      try {
        /// Read
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();

        /// Write
        // aspect ratio
        metadata["apectRatio"] = ratioIndex.toString();
        // orientation for aspect ratio (portrait, landscape)
        metadata["orientation"] =
            orientationPortrait ? "portrait" : "landscape";
        await file.writeAsString(jsonEncode(metadata));
        globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
      } catch (e) {
        dev.log("Error, savePageMetadata: $e");
      }
    }
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

  static Future<bool?> readPageOrientation(String pagePath) async {
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        String orientationString = metadata["orientation"];
        return (orientationString == "portrait" || orientationString == "");
      } catch (e) {
        dev.log("Error, readPageRatio: $e");
      }
    }
    dev.log("Warning, readPageRatio: Metadata does not exist for $pagePath");
    return null;
  }
}
