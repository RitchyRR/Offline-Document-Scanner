// function:
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:isolate';
import 'package:docscanner/main.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
// my packages:
import 'opencv_helper.dart';
import 'package:docscanner/files_helper.dart';

class ImageProcessingManager {
  static Future<void> _processPage(
    SendPort sendPort,
    FilesHelper filesHelperIn,
    bool isPrimary,
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
    bool? orientationIn,
  ) async {
    OpenCVHelper cvHelper = OpenCVHelper();

    List<String> pathsOut = await filesHelperIn.getImagePathsForPage(
      docIndex,
      pageIndex,
    );

    // Original
    Uint8List picture = File(pathIn).readAsBytesSync();
    await filesHelperIn.saveImage(pathsOut[0], picture);
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
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIn,
      filesHelperIn: filesHelperIn,
    );
    if (isPrimary) {
      metadataFuture.whenComplete(
        () => sendPort.send(NotifierEvent.loadPageMetadata),
      );
    }
    await filesHelperIn.saveImage(pathsOut[1], warped);
    if (isPrimary) sendPort.send(NotifierEvent.warpSaved);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(pathsOut[1]),
    );
    Future<void> p1Future = filesHelperIn.saveImage(pathsOut[2], processed1);
    if (isPrimary) {
      p1Future.whenComplete(() => sendPort.send(NotifierEvent.processed1Saved));
    }

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(pathsOut[1], borderCorrectionDepth),
    );
    await filesHelperIn.saveImage(pathsOut[3], processed2);
    if (isPrimary) sendPort.send(NotifierEvent.processed2Saved);

    // Update thumbnails:
    if (ratioIndexIn != null) {
      sendPort.send(NotifierEvent.reloadPagesThumbnails);
    } else {
      sendPort.send(NotifierEvent.loadPagesThumbnails);
    }
    sendPort.send(NotifierEvent.loadDocsThumbnailsAndInfo);

    writeScaledThumbnail(
      sendPort,
      pathsOut[3],
      filesHelperIn.screenWidth,
      overwrite: true,
    );
    // Make sure that futures are waited for,
    // to make sendPort.send('done'); wait,
    // otherwise their events might not be sent
    await metadataFuture;
    await p1Future;
  }

  static Future<void> _processPagesIsolate(
    (
      SendPort sendPort,
      FilesHelper filesHelperIn,
      int docIndex,
      int firstPageIndex,
      List<String> pathsIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    int docIndex = data.$3;
    int firstPageIndex = data.$4;
    List<String> pathsIn = data.$5;

    // process max 3 pages at a time (quad-core: 1 UI, 3 pages)
    const int maxConcurrentPagesProcessing = 3;
    List<Future<void>> futures = [];

    for (int i = 0; i < pathsIn.length; i++) {
      // Start processing a new page
      Future<void> future = _processPage(
        sendPort,
        filesHelperIn,
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
      FilesHelper filesHelperIn,
      int docIndex,
      int pageIndex,
      String pathIn,
      int? ratioIndexIn,
      bool? orientationIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;
    String pathIn = data.$5;

    int? ratioIndexIn = data.$6;
    bool? orientationIn = data.$7;

    await _processPage(
      sendPort,
      filesHelperIn,
      true,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
    );
    sendPort.send('done');
  }

  Map<(int, int), Future<Isolate>> primaryIsolates = {};
  Map<int, Future<Isolate>> secondaryIsolates = {};
  //Future<void> killAllIsolates() async {
  //  if (primaryIsolates.isNotEmpty) {
  //    for (var future in primaryIsolates.values) {
  //      (await future).kill(priority: Isolate.immediate);
  //    }
  //  }
  //  if (secondaryIsolates.isNotEmpty) {
  //    for (var future in secondaryIsolates.values) {
  //      (await future).kill(priority: Isolate.immediate);
  //    }
  //  }
  //}

  Future<void> killPrimaryIsolateOfPage(int docIndex, int pageIndex) async {
    var key = (docIndex, pageIndex);
    if (primaryIsolates.containsKey(key)) {
      (await primaryIsolates[key]!).kill(priority: Isolate.immediate);
      primaryIsolates.remove(key);
    }
    // killing secondary isolates for specific pages is impossible
    // -> ignore
  }

  Future<void> killIsolatesOfDocument(int docIndex) async {
    List<(int, int)> keys = [];
    for (var key in primaryIsolates.keys) {
      if (key.$1 == docIndex) {
        keys.add(key);
      }
    }
    for (var key in keys) {
      (await primaryIsolates[key]!).kill(priority: Isolate.immediate);
      primaryIsolates.remove(key);
    }
    if (secondaryIsolates.containsKey(docIndex)) {
      (await secondaryIsolates[docIndex]!).kill(priority: Isolate.immediate);
      secondaryIsolates.remove(docIndex);
    }
  }

  Future<void> processPages(
    int docIndex,
    int firstPageIndex,
    List<String> pathsIn,
  ) async {
    if (pathsIn.isEmpty) return;

    // First page is prioritized
    ReceivePort primaryPort = ReceivePort();
    primaryIsolates.addEntries([
      MapEntry(
        (docIndex, firstPageIndex),
        Isolate.spawn(_processPageIsolate, (
          primaryPort.sendPort,
          filesHelper,
          docIndex,
          firstPageIndex,
          pathsIn[0],
          null,
          null,
        )),
      ),
    ]);
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
      }
    });

    List<Future<dynamic>> beforeSecundary = [];
    beforeSecundary.add(Future.delayed(Duration(milliseconds: 1000)));
    beforeSecundary.add(primaryIsolates.values.last);

    // Remaining pages
    pathsIn.removeAt(0);
    if (pathsIn.isNotEmpty) {
      await Future.any(beforeSecundary);
      final secondaryPagesPort = ReceivePort();
      secondaryIsolates.addEntries([
        MapEntry(
          docIndex,
          Isolate.spawn(_processPagesIsolate, (
            secondaryPagesPort.sendPort,
            filesHelper,
            docIndex,
            firstPageIndex + 1,
            pathsIn,
          )),
        ),
      ]);
      secondaryPagesPort.listen((message) {
        if (message is NotifierEvent) {
          globalNotifier.triggerEvent(message);
        } else if (message == 'done') {
          secondaryPagesPort.close();
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

    primaryIsolates.addEntries([
      MapEntry(
        (docIndex, pageIndex),
        Isolate.spawn(_processPageIsolate, (
          primaryPort.sendPort,
          filesHelper,
          docIndex,
          pageIndex,
          pathIn,
          ratioIndexIn,
          orientationIn,
        )),
      ),
    ]);
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
      }
    });
  }

  static Future<void> writePageMetadata(
    int docIndex,
    int pageIndex,
    int ratioIndex,
    bool orientationPortrait, {
    FilesHelper? filesHelperIn,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Read
      //if (await file.exists()) {
      //  String content = await file.readAsString();
      //  metadata = jsonDecode(content).cast<String, String>();
      //}

      // Write
      metadata["apectRatio"] = ratioIndex.toString();
      metadata["orientation"] = orientationPortrait ? "portrait" : "landscape";
      await file.writeAsString(jsonEncode(metadata));
      if (filesHelperIn != null) {
        // if started outside of isolate
        globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
      }
    } catch (e) {
      dev.log("Error, savePageMetadata: $e");
    }
  }

  static Future<int?> readPageRatio(
    int docIndex,
    int pageIndex, {
    bool supressWarning = false,
  }) async {
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
    if (!supressWarning) {
      dev.log("Warning, readPageRatio: Metadata does not exist for $pagePath");
    }
    return null;
  }

  static Future<int?> readPageOrientation(
    int docIndex,
    int pageIndex, {
    bool supressWarning = false,
  }) async {
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
    if (!supressWarning) {
      dev.log("Warning, readPageRatio: Metadata does not exist for $pagePath");
    }
    return null;
  }

  static Future<void> writeScaledThumbnail(
    SendPort sendPort,
    String pathIn,
    int screenWidth, {
    bool overwrite = false,
  }) async {
    String pathOut = p.join(p.dirname(pathIn), 'thumbnail.png');
    File fileIn = File(pathIn);
    File fileOut = File(pathOut);

    //bool fileOutExists = false;
    if (!fileIn.existsSync()) {
      dev.log("Error, writeScaledThumbnail: $pathIn does not exist");
      return;
    } else if (fileOut.existsSync()) {
      //fileOutExists = true;
      if (overwrite) {
        dev.log("Overwriting, writeScaledThumbnail: $pathIn");
      } else {
        return;
      }
    }
    // Read
    Uint8List imageBytes = await fileIn.readAsBytes();
    img.Image? original = img.decodeImage(imageBytes);
    if (original == null) return;
    // Resize
    img.Image resized = img.copyResize(
      original,
      width:
          (screenWidth.toDouble() * 0.927083333)
              .toInt(), // thumbnail width in Pages Widget
      maintainAspect: true,
      interpolation: img.Interpolation.cubic,
    );
    // Check if aspect ratio is different
    //bool newAspectRatio = false;
    //if (fileOutExists &&
    //    resized.height !=
    //        (img.decodeImage(await fileOut.readAsBytes())?.width ?? 0)) {
    //  newAspectRatio = true;
    //}
    // Save
    fileOut.writeAsBytesSync(img.encodePng(resized));

    // Update thumbnails:
    //if (newAspectRatio) {
    //  sendPort.send(NotifierEvent.reloadPagesThumbnails);
    //} else {
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    //}
    sendPort.send(NotifierEvent.loadDocsThumbnailsAndInfo);
  }
}
