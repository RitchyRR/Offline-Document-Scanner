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
    SendPort sendPort,
    FilesHelper filesHelper,
    bool primary,
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
    bool? orientationIn,
  ) async {
    OpenCVHelper cvHelper = OpenCVHelper();

    List<String> pathsOut = await filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );

    // Original
    Uint8List picture = File(pathIn).readAsBytesSync();
    await FilesHelper.saveImage(pathsOut[0], picture);
    if (primary) sendPort.send(NotifierEvent.processPagePictureDone);

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
    writePageMetadata(
      sendPort,
      filesHelper,
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIn,
    );
    await FilesHelper.saveImage(pathsOut[1], warped);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(pathsOut[1]),
    );
    await FilesHelper.saveImage(pathsOut[2], processed1);

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(pathsOut[1], borderCorrectionDepth),
    );
    await FilesHelper.saveImage(pathsOut[3], processed2);
    // Update thumbnails:
    if (ratioIndexIn == null) {
      sendPort.send(NotifierEvent.loadPagesThumbnails);
    } else {
      sendPort.send(NotifierEvent.reloadPagesThumbnails);
    }
    sendPort.send(NotifierEvent.loadDocsThumbnailsAndInfo);
  }

  static Future<void> _processPagesIsolate(
    (
      SendPort sendPort,
      FilesHelper filesHelper,
      int docIndex,
      int firstPageIndex,
      List<String> pathsIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelper = data.$2;
    int docIndex = data.$3;
    int firstPageIndex = data.$4;
    List<String> pathsIn = data.$5;

    // Collect all processing tasks in a list of futures
    // -> sendPort.send('done'); waits correctly
    List<Future<void>> processingTasks = [];

    for (var i = 0; i < pathsIn.length; i++) {
      processingTasks.add(
        _processPage(
          sendPort,
          filesHelper,
          false,
          docIndex,
          firstPageIndex + i,
          pathsIn[i],
          null,
          null,
        ),
      );
    }
    await Future.wait(processingTasks);
    sendPort.send('done');
  }

  static Future<void> _processPageIsolate(
    (
      SendPort sendPort,
      FilesHelper filesHelper,
      int docIndex,
      int pageIndex,
      String pathIn,
      int? ratioIndexIn,
      bool? orientationIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelper = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;
    String pathIn = data.$5;

    int? ratioIndexIn = data.$6;
    bool? orientationIn = data.$7;

    await _processPage(
      sendPort,
      filesHelper,
      true,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
    );
    sendPort.send('done');
  }

  static Future<void> processPages(
    int docIndex,
    int firstPageIndex,
    List<String> pathsIn,
  ) async {
    final pagePort = ReceivePort();
    final pagesPort = ReceivePort();
    final filesHelper = FilesHelper();
    await filesHelper.initializeDocumentsPath();

    Isolate.spawn(_processPageIsolate, (
      pagePort.sendPort,
      filesHelper,
      docIndex,
      firstPageIndex,
      pathsIn[0],
      null,
      null,
    ));
    pathsIn.removeAt(0);
    Isolate.spawn(_processPagesIsolate, (
      pagesPort.sendPort,
      filesHelper,
      docIndex,
      firstPageIndex + 1,
      pathsIn,
    ));

    pagePort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        pagePort.close();
      }
    });
    pagesPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        pagesPort.close();
      }
    });
  }

  static Future<void> processPage(
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
    bool? orientationIn,
  ) async {
    final port = ReceivePort();
    final filesHelper = FilesHelper();
    await filesHelper.initializeDocumentsPath();

    Isolate.spawn(_processPageIsolate, (
      port.sendPort,
      filesHelper,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
    ));

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
      }
    });
  }

  static Future<void> writePageMetadata(
    SendPort? sendPort,
    FilesHelper filesHelper,
    int docIndex,
    int pageIndex,
    int ratioIndex,
    bool orientationPortrait,
  ) async {
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
      if (sendPort != null) {
        sendPort.send(NotifierEvent.loadPageMetadata);
      } else {
        globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
      }
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
