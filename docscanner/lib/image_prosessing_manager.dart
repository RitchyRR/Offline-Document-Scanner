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
    bool isPrimary,
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
    if (isPrimary) sendPort.send(NotifierEvent.pictureSaved);

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
    // Metadata
    int ratioIndex = ret.$3;
    orientationIn = ret.$4;
    Future<void> metadataFuture = writePageMetadata(
      filesHelper,
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIn,
      whileImageProcessing: true,
    );
    if (isPrimary) {
      metadataFuture.whenComplete(
        () => sendPort.send(NotifierEvent.loadPageMetadata),
      );
    }
    await FilesHelper.saveImage(pathsOut[1], warped);
    if (isPrimary) sendPort.send(NotifierEvent.warpSaved);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(pathsOut[1]),
    );
    Future<void> p1Future = FilesHelper.saveImage(pathsOut[2], processed1);
    if (isPrimary) {
      p1Future.whenComplete(() => sendPort.send(NotifierEvent.processed1Saved));
    }

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(pathsOut[1], borderCorrectionDepth),
    );
    await FilesHelper.saveImage(pathsOut[3], processed2);
    if (isPrimary) sendPort.send(NotifierEvent.processed2Saved);

    // Update thumbnails:
    if (ratioIndexIn == null) {
      sendPort.send(NotifierEvent.loadPagesThumbnails);
    } else {
      sendPort.send(NotifierEvent.reloadPagesThumbnails);
    }
    sendPort.send(NotifierEvent.loadDocsThumbnailsAndInfo);

    // Make sure that futures are waited for,
    // to make sendPort.send('done'); wait,
    // otherwise their events might not be sent
    await metadataFuture;
    await p1Future;
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

    // process max 2 pages at a time
    const int maxConcurrentPagesProcessing = 2;
    List<Future<void>> futures = [];

    for (int i = 0; i < pathsIn.length; i++) {
      // Start processing a new page
      Future<void> future = _processPage(
        sendPort,
        filesHelper,
        false,
        docIndex,
        firstPageIndex + i,
        pathsIn[i],
        null,
        null,
      );
      futures.add(future);
      // register removal from list when future completes
      future.whenComplete(() => futures.remove(future));

      if (futures.length >= maxConcurrentPagesProcessing) {
        await Future.any(futures);
      }
    }
    await Future.wait(futures);
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

  Future<Isolate>? primaryIsolate;
  Future<void> killPrimaryIsolate() async {
    if (primaryIsolate == null) {
      dev.log("Warning, killPrimaryIsolate: isolate is null");
      return;
    }
    (await primaryIsolate)!.kill(priority: Isolate.immediate);
  }

  Future<void> processPages(
    int docIndex,
    int firstPageIndex,
    List<String> pathsIn,
  ) async {
    if (pathsIn.isEmpty) return;
    ReceivePort primaryPort = ReceivePort();
    final filesHelper = FilesHelper();
    await filesHelper.initializeDocumentsPath();

    // First page is prioritized
    primaryIsolate = Isolate.spawn(_processPageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      docIndex,
      firstPageIndex,
      pathsIn[0],
      null,
      null,
    ));
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
      }
    });

    // Remaining pages
    pathsIn.removeAt(0);
    if (pathsIn.isNotEmpty) {
      await Future.delayed(Duration(milliseconds: 100));
      final pagesPort = ReceivePort();
      Isolate.spawn(_processPagesIsolate, (
        pagesPort.sendPort,
        filesHelper,
        docIndex,
        firstPageIndex + 1,
        pathsIn,
      ));
      pagesPort.listen((message) {
        if (message is NotifierEvent) {
          globalNotifier.triggerEvent(message);
        } else if (message == 'done') {
          pagesPort.close();
        }
      });
    }
  }

  Future<void> processPage(
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
    bool? orientationIn,
  ) async {
    ReceivePort primaryPort = ReceivePort();
    final filesHelper = FilesHelper();
    await filesHelper.initializeDocumentsPath();

    primaryIsolate = Isolate.spawn(_processPageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
    ));
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
      }
    });
  }

  static Future<void> writePageMetadata(
    FilesHelper filesHelper,
    int docIndex,
    int pageIndex,
    int ratioIndex,
    bool orientationPortrait, {
    bool whileImageProcessing = false,
  }) async {
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
      if (!whileImageProcessing) {
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
