// function:
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:isolate';
import 'package:docscanner/main.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
// my packages:
import 'opencv_helper.dart';
import 'package:docscanner/files_helper.dart';

class ImageProcessingManager {
  static Future<void> _processPage(
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
    bool? orientationIn,
  ) async {
    FilesHelper filesHelper = FilesHelper();
    OpenCVHelper cvHelper = OpenCVHelper();

    List<String> pathsOut = await filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );

    // Original
    Uint8List picture = File(pathIn).readAsBytesSync();
    await FilesHelper.saveImage(pathsOut[0], picture);

    // Warped
    var ret = cvHelper.warpImage(
      ParamsWarpImage(
        pathsOut[0],
        inRatioIndex: ratioIndexIn,
        orientation: orientationIn,
      ),
    );
    Uint8List warped = ret.$1;
    List<int> borderCorrectionDepth = ret.$2;
    int ratioIndex = ret.$3;
    orientationIn = ret.$4;
    writePageMetadata(docIndex, pageIndex, ratioIndex, orientationIn);
    await FilesHelper.saveImage(pathsOut[1], warped);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(pathsOut[1]),
    );
    FilesHelper.saveImage(pathsOut[2], processed1);

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(pathsOut[1], borderCorrectionDepth),
    );
    await FilesHelper.saveImage(pathsOut[3], processed2);
    // Update thumbnails:
    if (ratioIndexIn == null) {
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
    } else {
      globalNotifier.triggerEvent(NotifierEvent.reloadPagesThumbnails);
    }
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnailsAndInfo);
  }

  static void processPages(
    (
      SendPort sendPort,
      int docIndex,
      List<String> pathsIn,
      int firstPageIndex,
      int? ratioIndexIn,
      bool? orientationIn,
    )
    data,
  ) {
    SendPort sendPort = data.$1;
    int docIndex = data.$2;
    List<String> pathsIn = data.$3;
    int firstPageIndex = data.$4;

    int? ratioIndexIn = data.$5;
    bool? orientationIn = data.$6;

    for (var i = firstPageIndex; i < pathsIn.length + firstPageIndex; i++) {
      _processPage(docIndex, i, pathsIn[i], ratioIndexIn, orientationIn);
    }

    sendPort.send(true);
  }

  static Future<void> writePageMetadata(
    int docIndex,
    int pageIndex,
    int ratioIndex,
    bool orientationPortrait,
  ) async {
    FilesHelper filesHelper = FilesHelper();
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      /// Read
      if (await file.exists()) {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
      }

      /// Write
      // aspect ratio
      metadata["apectRatio"] = ratioIndex.toString();
      // orientation for aspect ratio (portrait, landscape)
      metadata["orientation"] = orientationPortrait ? "portrait" : "landscape";
      await file.writeAsString(jsonEncode(metadata));
      globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
    } catch (e) {
      dev.log("Error, savePageMetadata: $e");
    }
  }

  static Future<int?> readPageRatio(int docIndex, int pageIndex) async {
    FilesHelper filesHelper = FilesHelper();
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
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

  static Future<int?> readPageOrientation(int docIndex, int pageIndex) async {
    FilesHelper filesHelper = FilesHelper();
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        String orientationString = metadata["orientation"];
        return (orientationString == "portrait" || orientationString == "")
            ? 0
            : 1;
      } catch (e) {
        dev.log("Error, readPageRatio: $e");
      }
    }
    dev.log("Warning, readPageRatio: Metadata does not exist for $pagePath");
    return null;
  }
}
