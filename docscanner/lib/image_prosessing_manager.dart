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
    await writePageMetadata(
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIn,
      filesHelperIn: filesHelperIn,
    );
    if (isPrimary) sendPort.send(NotifierEvent.loadPageMetadata);

    await filesHelperIn.saveImage(pathsOut[1], warped);
    if (isPrimary) sendPort.send(NotifierEvent.warpSaved);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(pathsOut[1]),
    );
    await filesHelperIn.saveImage(pathsOut[2], processed1);
    if (isPrimary) {
      sendPort.send(NotifierEvent.processed1Saved);
    }

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(pathsOut[1], borderCorrectionDepth),
    );
    await filesHelperIn.saveImage(pathsOut[3], processed2);
    if (isPrimary) sendPort.send(NotifierEvent.processed2Saved);

    // Update thumbnails:
    if (ratioIndexIn != null && orientationIn != null) {
      sendPort.send(NotifierEvent.reloadPagesThumbnails);
      sendPort.send(NotifierEvent.reloadDocsThumbnails);
    } else {
      sendPort.send(NotifierEvent.loadPagesThumbnails);
      sendPort.send(NotifierEvent.loadDocsThumbnailsAndInfo);
    }

    await writeScaledThumbnail(
      sendPort,
      pathsOut[3],
      filesHelperIn.screenWidth,
      overwrite: true,
    );
  }

  static Future<void> _processPageIsolate(
    (
      SendPort sendPort,
      FilesHelper filesHelperIn,
      bool isPrimary,
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
    bool isPrimary = data.$3;
    int docIndex = data.$4;
    int pageIndex = data.$5;
    String pathIn = data.$6;

    int? ratioIndexIn = data.$7;
    bool? orientationIn = data.$8;

    await _processPage(
      sendPort,
      filesHelperIn,
      isPrimary,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
    );
    sendPort.send('done');
  }

  Map<(int, int), Isolate> primaryIsolates = {};
  Map<(int, int), Isolate> secondaryIsolates = {};
  List<Completer> comleters = [];

  Future<void> killPrimaryIsolateOfPage(int docIndex, int pageIndex) async {
    var key = (docIndex, pageIndex);
    if (primaryIsolates.containsKey(key)) {
      (primaryIsolates[key]!).kill(priority: Isolate.immediate);
      primaryIsolates.remove(key);
    }
  }

  Future<void> killIsolatesOfPage(int docIndex, int pageIndex) async {
    var key = (docIndex, pageIndex);
    if (primaryIsolates.containsKey(key)) {
      (primaryIsolates[key]!).kill(priority: Isolate.immediate);
      primaryIsolates.remove(key);
    }
    if (secondaryIsolates.containsKey(key)) {
      (secondaryIsolates[key]!).kill(priority: Isolate.immediate);
      secondaryIsolates.remove(key);
    }
  }

  Future<void> killIsolatesOfDocument(int docIndex) async {
    List<(int, int)> primaryKeys = [];
    for (var key in primaryIsolates.keys) {
      if (key.$1 == docIndex) {
        primaryKeys.add(key);
      }
    }
    for (var key in primaryKeys) {
      (primaryIsolates[key]!).kill(priority: Isolate.immediate);
      primaryIsolates.remove(key);
    }

    List<(int, int)> secundaryKeys = [];
    for (var key in secondaryIsolates.keys) {
      if (key.$1 == docIndex) {
        secundaryKeys.add(key);
      }
    }
    for (var key in secundaryKeys) {
      (secondaryIsolates[key]!).kill(priority: Isolate.immediate);
      secondaryIsolates.remove(key);
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
    final primaryCompleter = Completer<void>();
    comleters.add(primaryCompleter);
    Isolate primaryIolate = await Isolate.spawn(_processPageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      true,
      docIndex,
      firstPageIndex,
      pathsIn[0],
      null,
      null,
    ));
    primaryIsolates[(docIndex, firstPageIndex)] = primaryIolate;
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
        primaryCompleter.complete();
        comleters.remove(primaryCompleter);
        //primaryIolate.kill();
        primaryIsolates.removeWhere((key, value) => value == primaryIolate);
      }
    });

    List<Future<dynamic>> beforeSecundary = [];
    beforeSecundary.add(Future.delayed(Duration(milliseconds: 1000)));
    beforeSecundary.add(primaryCompleter.future);

    // Remaining pages
    pathsIn.removeAt(0);
    if (pathsIn.isNotEmpty) {
      await Future.any(beforeSecundary);

      final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
      for (var (index, path) in pathsIn.indexed) {
        if (comleters.length >= maxIsolates) {
          await Future.any(comleters.map((c) => c.future));
        }

        ReceivePort secondaryPort = ReceivePort();
        final completer = Completer<void>();
        comleters.add(completer);
        Isolate isolate = await Isolate.spawn(_processPageIsolate, (
          secondaryPort.sendPort,
          filesHelper,
          false,
          docIndex,
          firstPageIndex + 1 + index,
          path,
          null,
          null,
        ));
        secondaryIsolates[(docIndex, firstPageIndex + 1 + index)] = isolate;
        secondaryPort.listen((message) {
          if (message is NotifierEvent) {
            globalNotifier.triggerEvent(message);
          } else if (message == 'done') {
            secondaryPort.close();
            completer.complete();
            comleters.remove(completer);
            //isolate.kill();
            secondaryIsolates.removeWhere((key, value) => value == isolate);
          }
        });
      }
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
    final primaryCompleter = Completer<void>();
    comleters.add(primaryCompleter);
    Isolate primaryIolate = await Isolate.spawn(_processPageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      true,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
    ));
    primaryIsolates[(docIndex, pageIndex)] = primaryIolate;
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
        primaryCompleter.complete();
        comleters.remove(primaryCompleter);
        //primaryIolate.kill();
        primaryIsolates.removeWhere((key, value) => value == primaryIolate);
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
      interpolation: img.Interpolation.linear,
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
