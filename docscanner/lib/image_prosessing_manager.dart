// function:
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
// isolates:
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'dart:isolate' show ReceivePort, SendPort, Isolate;
import 'package:docscanner/isolates_manager.dart';
// my packages:
import 'package:docscanner/opencv_helper.dart';
import 'package:docscanner/main.dart' show globalNotifier;
import 'package:docscanner/metadata_helper.dart';
import 'package:docscanner/app_globals.dart';
import 'package:pdf_render/pdf_render.dart' as pdfr;

const List<String> versionNamesInternal = [
  "photo",
  "warped",
  "contrast",
  "processed1",
  "processed2",
  "processed3",
];

class ImageProcessingManager {
  Map<(int, int), TaskKiller> taskKillers = {};

  static void _processPageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      String photoPath,
      double? ratioValueIn,
      List<List<int>>? cornerPointsIn,
      int rotationIn,
      bool isInitial,
      bool isPhotoAlreadyInPage,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    int docIndex = data.$3;
    int pageIndex = data.$4;
    String photoPath = data.$5;

    double? ratioValueIn = data.$6;
    List<List<int>>? cornerPointsIn = data.$7;
    int rotationIn = data.$8;
    bool isInitial = data.$9;
    bool isPhotoAlreadyInPage = data.$10;
    AppGlobals g = data.$11;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    isolateExitPoint(kill);
    String pagePath = await g.filesHelper.getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: true,
    );
    if (!Directory(pagePath).existsSync()) {
      throw StateError(
        "Error, _processPageIsolate: pagePath $pagePath does not exist",
      );
    }

    // Delete old Thumbnail
    isolateExitPoint(kill);
    _deleteScaledThumbnail(pagePath);

    // Read Photo
    isolateExitPoint(kill);
    final imageRaw = g.filesHelper.readImageRaw(photoPath);
    Uint8List photoBytes = imageRaw.$1;
    String photoExtension = imageRaw.$2;
    if (!isPhotoAlreadyInPage) {
      // Write photo into storage
      isolateExitPoint(kill);
      await g.filesHelper.writeImageRaw(
        docIndex,
        pageIndex,
        0,
        photoBytes,
        photoExtension,
      );
    }

    // Read Shape, if it exists
    isolateExitPoint(kill);
    String shapePath = await g.filesHelper.getPageShape(
      docIndex,
      pageIndex,
      supressWarnings: isInitial,
    );
    Uint8List? shapeBytes;
    if (shapePath.isNotEmpty && File(shapePath).lengthSync() != 0) {
      isolateExitPoint(kill);
      shapeBytes = File(shapePath).readAsBytesSync();
    }
    // Rotate shape
    if (shapeBytes != null && rotationIn != 0) {
      isolateExitPoint(kill);
      shapeBytes = await cvHelper.rotateImage(shapeBytes, rotationIn);
    }

    // Warped + Metadata
    isolateExitPoint(kill);
    var warpedRet = await cvHelper.warpImage(
      ParamsWarpImage(
        photoBytes,
        shapeBytes,
        ratioValueIn: ratioValueIn,
        cornerPoints: cornerPointsIn,
      ),
    );
    Uint8List warpedBytes = warpedRet.$1;
    if (shapeBytes == null) {
      Uint8List shapeBytesWarped = warpedRet.$2;
      isolateExitPoint(kill);
      await g.filesHelper.savePageShape(docIndex, pageIndex, shapeBytesWarped);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    double? ratioValue = warpedRet.$4;
    List<List<int>>? cornerPoints = warpedRet.$5;

    isolateExitPoint(kill);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      1,
      warpedBytes,
      ".png",
    );

    // Kontrast basierend auf dem Warped-Bild
    isolateExitPoint(kill);
    Uint8List contrastBytes = await cvHelper.processImageContrast(
      ParamsProcessImage1(warpedBytes),
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      2,
      contrastBytes,
      ".png",
    );

    // Processed1 basierend auf dem Warped-Bild
    isolateExitPoint(kill);
    Uint8List processed1Bytes = await cvHelper.processImage1(
      ParamsProcessImage1(warpedBytes),
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      3,
      processed1Bytes,
      ".png",
    );

    // Processed2 basierend auf dem Warped-Bild
    isolateExitPoint(kill);
    Uint8List processed2Bytes;
    Uint8List processed3Bytes;
    (processed2Bytes, processed3Bytes) = await cvHelper.processImage2(
      ParamsProcessImage2(warpedBytes, borderCorrectionDepth),
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      4,
      processed2Bytes,
      ".png",
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      5,
      processed3Bytes,
      ".png",
    );

    // Update thumbnails:
    isolateExitPoint(kill);
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    isolateExitPoint(kill);
    int? thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
      docIndex,
      pageIndex,
      gIn: g,
      supressWarnings: true,
    );

    isolateExitPoint(kill);
    bool newThumbnail = await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      thumbnailIndex,
      g,
      overwrite: !isInitial,
    );

    if (newThumbnail && thumbnailIndex == null) {
      isolateExitPoint(kill);
      await MetadataHelper.writePageThumbnailIndex(
        docIndex,
        pageIndex,
        thumbnailIndex ??
            ((g.proUnlocked == true)
                ? g.defaultIndexes.$2
                : g.defaultIndexes.$1),
        gIn: g,
        supressWarnings: true,
      );
    }

    Isolate.exit(sendPort, "done");
  }

  static void isolateExitPoint(final bool kill) {
    if (kill) {
      Isolate.exit();
    }
  }

  static void _processPdfPageIsolatePart1(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      Uint8List pngBytes,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    Uint8List pngBytes = data.$5;
    AppGlobals g = data.$6;

    // Thumbnail
    isolateExitPoint(kill);
    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      1,
      gIn: g,
      supressWarnings: true,
    );

    // Save Photo
    isolateExitPoint(kill);
    sendPort.send(
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        0,
        pngBytes,
        ".png",
      ),
    );
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    // Generate Metadata
    isolateExitPoint(kill);
    final imgInfo = AppGlobals.getPngInfo(pngBytes);
    if (imgInfo == null) {
      throw StateError("Error, processPdfPage: can't decode Image.");
    }
    List<List<int>> cornerPointsIn = [
      [0, 0],
      [imgInfo.height - 1, 0],
      [0, imgInfo.width - 1],
      [imgInfo.height - 1, imgInfo.width - 1],
    ];
    OpenCVHelper cvHelper = OpenCVHelper(g);
    isolateExitPoint(kill);
    final matchingValue = cvHelper.matchAspectRatioAndOrientation(
      imgInfo.height / imgInfo.width,
    );
    double ratioValueIn = matchingValue;

    // Write Metadata
    isolateExitPoint(kill);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValueIn,
      cornerPointsIn,
      gIn: g,
    );

    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      0,
      g,
    );

    Isolate.exit(sendPort, "done");
  }

  static void _processPdfPageIsolatePart2(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      Uint8List photoBytes,
      String extension,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    Uint8List photoBytes = data.$5;
    String extension = data.$6;
    AppGlobals g = data.$7;

    OpenCVHelper cvHelper = OpenCVHelper(g);
    List<int> borderCorrectionDepth = List<int>.generate(4, (_) => 0);

    // Warped
    isolateExitPoint(kill);
    await g.filesHelper.writeImageRaw(
      docIndex,
      pageIndex,
      1,
      photoBytes,
      extension,
    );

    // Kontrast basierend auf dem Warped-Bild
    isolateExitPoint(kill);
    Uint8List contrastBytes = await cvHelper.processImageContrast(
      ParamsProcessImage1(photoBytes),
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      2,
      contrastBytes,
      ".png",
    );

    // Processed1 basierend auf dem Warped-Bild
    isolateExitPoint(kill);
    Uint8List processed1 = await cvHelper.processImage1(
      ParamsProcessImage1(photoBytes),
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      3,
      processed1,
      ".png",
    );

    // Processed2 basierend auf dem Warped-Bild
    isolateExitPoint(kill);
    Uint8List processed2Bytes;
    Uint8List processed3Bytes;
    (processed2Bytes, processed3Bytes) = await cvHelper.processImage2(
      ParamsProcessImage2(photoBytes, borderCorrectionDepth),
    );

    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      4,
      processed2Bytes,
      ".png",
    );
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      5,
      processed3Bytes,
      ".png",
    );

    Isolate.exit(sendPort, "done");
  }

  Future<void> _processPageWrapper(
    int docIndex,
    int pageIndex,
    String photoPath,
    double? ratioValueIn,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
    bool isInitial,
    bool isPhotoAlreadyInPage,
    IsolatePriority prio,
  ) async {
    if (photoPath.isEmpty) return;

    final port = ReceivePort();
    final token = RootIsolateToken.instance!;

    TaskKiller killer = await IsolatesManager().runTask(
      _processPageIsolate,
      (
        port.sendPort,
        token,
        docIndex,
        pageIndex,
        photoPath,
        ratioValueIn,
        cornerPointsIn,
        rotationIn,
        isInitial,
        isPhotoAlreadyInPage,
        g,
      ),
      portIn: port,
      prio: prio,
      onErrorFunction: (error, stack) async {
        dev.log("_processPageIsolate, onErrorFunction: $error $stack");
        if (!error.toString().contains("No photo")) {
          repairPage(docIndex, pageIndex);
        }
      },
    );

    taskKillers[(docIndex, pageIndex)] = killer;
    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
        if (message == NotifierEvent.loadPagesThumbnails) {
          if (pageIndex == 0) {
            await Future.delayed(Duration(milliseconds: 100));
            globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
          }
        }
      } else if (message is SendPort) {
        killer.setControlPort(message);
      } else if (message == "done") {
        taskKillers.removeWhere((key, value) => value == killer);
      }
    });
  }

  static Future<void> _repairPageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;

    AppGlobals g = data.$5;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    if (!File(
      await g.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        0,
        supressWarnings: true,
      ),
    ).existsSync()) {
      //dev.log("repairPageIsolate: Doc $docIndex, Page $pageIndex: No photo");
      if (File(
        await g.filesHelper.getPagePath(
          docIndex,
          pageIndex,
          supressWarnings: true,
        ),
      ).existsSync()) {
        g.filesHelper.deleteImages(null, docIndex, pageIndexes: [pageIndex]);
      }
      Isolate.exit();
    }
    // Read Matadata
    var processingMetadata = await g.metadataHelper.readPageProcessingMetadata(
      docIndex,
      pageIndex,
      gIn: g,
    );
    double? ratioValue = processingMetadata.$1;
    List<List<int>>? cornerPoints = processingMetadata.$2;

    // Original
    isolateExitPoint(kill);
    var imagePaths = await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    final List<String> versionPaths = imagePaths.$1;
    String shapePath = imagePaths.$2;
    String thumbnailPath = imagePaths.$3;

    isolateExitPoint(kill);
    final photoFile = File(versionPaths[0]);
    if (!photoFile.existsSync() || photoFile.lengthSync() < 9) {
      throw StateError("Error, _repairPageIsolate: No photo");
    }

    // Warped
    isolateExitPoint(kill);
    var warpedRet = await cvHelper.warpImage(
      ParamsWarpImage(
        File(versionPaths[0]).readAsBytesSync(),
        shapePath.isNotEmpty ? File(shapePath).readAsBytesSync() : null,
        ratioValueIn: ratioValue,
        cornerPoints: cornerPoints,
        onlyCalculateBorder: versionPaths[1].isNotEmpty,
      ),
    );
    Uint8List warpedBytes = warpedRet.$1;
    if (warpedBytes.lengthInBytes == 0) {
      if (versionPaths[1].isNotEmpty) {
        warpedBytes = File(versionPaths[1]).readAsBytesSync();
      } else {
        throw StateError("Error, _repairPageIsolate: No warped");
      }
    }
    Uint8List shapeBytesWarped = warpedRet.$2;
    isolateExitPoint(kill);
    if (shapePath.isEmpty) {
      g.filesHelper.savePageShape(docIndex, pageIndex, shapeBytesWarped);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    // Metadata
    ratioValue = warpedRet.$4;
    cornerPoints = warpedRet.$5;
    isolateExitPoint(kill);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );

    // Warped
    if (versionPaths[1].isEmpty) {
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        1,
        warpedBytes,
        ".png",
      );
    }

    // Kontrast basierend auf dem Warped-Bild
    if (versionPaths[2].isEmpty) {
      isolateExitPoint(kill);
      Uint8List contrastBytes = await cvHelper.processImageContrast(
        ParamsProcessImage1(warpedBytes),
      );
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        2,
        contrastBytes,
        ".png",
      );
    }

    // Processed1 basierend auf dem Warped-Bild
    if (versionPaths[3].isEmpty) {
      isolateExitPoint(kill);
      Uint8List processed1 = await cvHelper.processImage1(
        ParamsProcessImage1(warpedBytes),
      );
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        3,
        processed1,
        ".png",
      );
    }

    // Processed2 basierend auf dem Warped-Bild
    if (versionPaths[4].isEmpty || versionPaths[5].isEmpty) {
      isolateExitPoint(kill);
      Uint8List processed2Bytes;
      Uint8List processed3Bytes;
      (processed2Bytes, processed3Bytes) = await cvHelper.processImage2(
        ParamsProcessImage2(warpedBytes, borderCorrectionDepth),
      );
      // PRO
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        3,
        processed2Bytes,
        ".png",
      );
      // PRO 2
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        5,
        processed3Bytes,
        ".png",
      );
    }

    // Update thumbnails:
    isolateExitPoint(kill);
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    if (thumbnailPath.isEmpty) {
      isolateExitPoint(kill);
      int? thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        pageIndex,
        gIn: g,
      );
      isolateExitPoint(kill);
      bool newThumbnail = await _scaleAndSaveThumbnailInIsolate(
        sendPort,
        kill,
        docIndex,
        pageIndex,
        thumbnailIndex,
        g,
        overwrite: false,
      );
      if (newThumbnail) {
        isolateExitPoint(kill);
        await MetadataHelper.writePageThumbnailIndex(
          docIndex,
          pageIndex,
          thumbnailIndex ??
              (g.proUnlocked == true
                  ? g.defaultIndexes.$2
                  : g.defaultIndexes.$1),
          gIn: g,
        );
      }
    }

    Isolate.exit(sendPort, "done");
  }

  Future<void> killIsolatesOfPage(int docIndex, int pageIndex) async {
    var key = (docIndex, pageIndex);
    if (taskKillers.containsKey(key)) {
      await (taskKillers[key]!).kill();
      taskKillers.remove(key);
    }
  }

  void delayIsolatesOfPage(int docIndex, int pageIndex) {
    var key = (docIndex, pageIndex);
    if (taskKillers.containsKey(key)) {
      taskKillers[key]?.delay();
    }
  }

  Future<void> killIsolatesOfDocument(int docIndex) async {
    List<(int, int)> keys = [];
    for (var key in taskKillers.keys) {
      if (key.$1 == docIndex) {
        keys.add(key);
      }
    }
    List<Future<void>> killerFutures = [];
    for (var key in keys) {
      killerFutures.add(taskKillers[key]!.kill());
      taskKillers.remove(key);
    }
    await Future.wait(killerFutures);
  }

  void delayIsolatesOfDocument(int docIndex) {
    List<(int, int)> keys = [];
    for (var key in taskKillers.keys) {
      if (key.$1 == docIndex) {
        keys.add(key);
      }
    }
    for (var key in keys) {
      taskKillers[key]?.delay();
    }
  }

  Future<void> awaitIsolatesOfHigherIndexedDocuments(int docIndex) async {
    while (taskKillers.isNotEmpty) {
      taskKillers.removeWhere((key, value) => value.exited);
      final otherKeys = taskKillers.keys
          .where((key) => key.$1 > docIndex)
          .toList();
      final otherIsolates = otherKeys.map((key) => taskKillers[key]!).toList();

      if (otherIsolates.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexPage(int docIndex, pageIndex) async {
    while (taskKillers.isNotEmpty) {
      taskKillers.removeWhere((key, value) => value.exited);
      final otherKeys = taskKillers.keys
          .where((key) => key.$1 == docIndex && key.$2 > pageIndex)
          .toList();
      final higherTasks = otherKeys.map((key) => taskKillers[key]!).toList();

      if (higherTasks.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexPages(
    int docIndexIn,
    List<int> pageIndexesIn,
  ) async {
    final pageIndexes = List<int>.from(pageIndexesIn);
    int smallestIndex = pageIndexes.reduce(math.min);
    pageIndexes.remove(smallestIndex);
    while (taskKillers.isNotEmpty) {
      taskKillers.removeWhere((key, value) => value.exited);
      final otherKeys = taskKillers.keys
          .where((key) => key.$1 == docIndexIn && key.$2 > smallestIndex)
          .toList();
      for (var pageIndex in pageIndexes) {
        otherKeys.removeWhere((key) => key.$2 == pageIndex);
      }
      final higherTasks = otherKeys.map((key) => taskKillers[key]!).toList();

      if (higherTasks.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitAllIsolatesOfDocument(int docIndex) async {
    while (taskKillers.isNotEmpty) {
      taskKillers.removeWhere((key, value) => value.exited);
      final docKeys = taskKillers.keys
          .where((key) => key.$1 == docIndex)
          .toList();
      final docKillers = docKeys.map((key) => taskKillers[key]!).toList();

      if (docKillers.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitAllIsolates() async {
    while (taskKillers.isNotEmpty) {
      taskKillers.removeWhere((key, value) => value.exited);
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> processPages(
    int docIndex,
    int firstPageIndex,
    List<String> photoPathsIn,
    bool photosAlreadyInPages,
  ) async {
    if (photoPathsIn.isEmpty) return;

    // First page is opened in PagePreview -> more NotifierEvents
    await _processPageWrapper(
      docIndex,
      firstPageIndex,
      photoPathsIn[0],
      null,
      null,
      0,
      true,
      photosAlreadyInPages,
      IsolatePriority.immediate,
    );

    // Remaining pages
    photoPathsIn.removeAt(0);
    if (photoPathsIn.isNotEmpty) {
      for (var (index, path) in photoPathsIn.indexed) {
        await _processPageWrapper(
          docIndex,
          firstPageIndex + 1 + index,
          path,
          null,
          null,
          0,
          true,
          photosAlreadyInPages,
          IsolatePriority.regular,
        );
      }
    }
  }

  Future<void> reprocessPage(
    int docIndex,
    int pageIndex,
    String pathIn,
    double? ratioValueIn,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
  ) async {
    await killIsolatesOfPage(docIndex, pageIndex);
    await _processPageWrapper(
      docIndex,
      pageIndex,
      pathIn,
      ratioValueIn,
      cornerPointsIn,
      rotationIn,
      false,
      rotationIn == 0,
      IsolatePriority.immediate,
    );
  }

  Future<void> repairPage(int docIndex, int pageIndex) async {
    final repairCompleter = Completer<void>();
    final port = ReceivePort();
    RootIsolateToken token = RootIsolateToken.instance!;

    TaskKiller killer = await IsolatesManager().runTask(
      _repairPageIsolate,
      (port.sendPort, token, docIndex, pageIndex, g),

      portIn: port,
      prio: IsolatePriority.regular,
      onErrorFunction: (error, stack) {
        dev.log("_repairPageIsolate, onErrorFunction: $error $stack");
        g.filesHelper.deleteImages(null, docIndex, pageIndexes: [pageIndex]);
      },
    );
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
        if (message == NotifierEvent.loadPagesThumbnails) {
          if (pageIndex == 0) {
            await Future.delayed(Duration(milliseconds: 100));
            globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
          }
        }
      } else if (message is SendPort) {
        killer.setControlPort(message);
      } else if (message == "done") {
        repairCompleter.complete();
        taskKillers.removeWhere((key, value) => value == killer);
      }
    });
    await repairCompleter.future;
  }

  static Future<void> _rotatePageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      List<String> versionPaths, //[0] is potentially rotated
      int rotationIn,
      int pageThumbnailIndexIn,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    List<String> versionPaths = data.$5;
    int rotationIn = data.$6;
    int pageThumbnailIndexIn = data.$7;
    AppGlobals g = data.$8;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Delete old Thumbnail
    isolateExitPoint(kill);
    _deleteScaledThumbnail(
      await g.filesHelper.getPagePath(docIndex, pageIndex),
    );

    if (!File(versionPaths[0]).existsSync()) {
      throw StateError("photo ${versionPaths[0]} does not exist");
    }

    /// 1. save rotated photo
    isolateExitPoint(kill);
    final rotatedPhotoRaw = g.filesHelper.readImageRaw(versionPaths[0]);
    Uint8List rotatedPhotoBytes = rotatedPhotoRaw.$1;
    String rotatedPhotoExtension = rotatedPhotoRaw.$2;
    isolateExitPoint(kill);
    versionPaths[0] = await g.filesHelper.writeImageRaw(
      docIndex,
      pageIndex,
      0,
      rotatedPhotoBytes,
      rotatedPhotoExtension,
    );

    /// 2. rotate processed -> save

    // Shape
    isolateExitPoint(kill);
    String? shapePath = await g.filesHelper.getPageShape(docIndex, pageIndex);
    if (shapePath.isNotEmpty) {
      isolateExitPoint(kill);
      Uint8List shapeBytes = File(shapePath).readAsBytesSync();
      isolateExitPoint(kill);
      shapeBytes = await cvHelper.rotateImage(shapeBytes, rotationIn);
      isolateExitPoint(kill);
      shapePath = await g.filesHelper.savePageShape(
        docIndex,
        pageIndex,
        shapeBytes,
      );
    }
    // Warped, Contrast, Processed1, Processed2
    for (int i = 1; i < versionPaths.length; i++) {
      isolateExitPoint(kill);
      Uint8List bytes = await cvHelper.rotateImage(
        File(versionPaths[i]).readAsBytesSync(),
        rotationIn,
      );
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        i,
        bytes,
        ".png",
      );
    }

    // Updates
    isolateExitPoint(kill);
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    isolateExitPoint(kill);
    //bool newThumbnail =
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      pageThumbnailIndexIn,
      g,
      overwrite: false,
    );

    Isolate.exit(sendPort, "done");
  }

  Future<void> rotatePage(
    int docIndex,
    int pageIndex,
    List<String> versionPaths, //[0] is rotated
    int angle,
    int pageThumbnailIndexIn,
  ) async {
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;
    final rotatePageCompleter = Completer<void>();

    TaskKiller killer = await IsolatesManager().runTask(
      _rotatePageIsolate,
      (
        port.sendPort,
        token,
        docIndex,
        pageIndex,
        versionPaths,
        angle,
        pageThumbnailIndexIn,
        g,
      ),
      portIn: port,
      prio: IsolatePriority.immediate,
    );
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
        if (message == NotifierEvent.loadPagesThumbnails) {
          if (pageIndex == 0) {
            await Future.delayed(Duration(milliseconds: 100));
            globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
          }
        }
      } else if (message is SendPort) {
        killer.setControlPort(message);
      } else if (message == "done") {
        taskKillers.removeWhere((key, value) => value == killer);
        rotatePageCompleter.complete();
      }
    });
    await rotatePageCompleter.future;
  }

  static Future<bool> _scaleAndSaveThumbnailInIsolate(
    SendPort sendPort,
    bool kill,
    int docIndex,
    int pageIndex,
    int? thumbnailIndex,
    AppGlobals gIn, {
    bool overwrite = true,
  }) async {
    thumbnailIndex ??= (gIn.proUnlocked == true
        ? gIn.defaultIndexes.$2
        : gIn.defaultIndexes.$1);

    int screenWidth = gIn.filesHelper.screenWidth;
    String pagePath;
    String versionPath;
    try {
      isolateExitPoint(kill);
      pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
      versionPath = await gIn.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        thumbnailIndex,
      );
    } catch (e) {
      throw StateError(
        "Error, _scaleAndSaveThumbnailInIsolate, getPagePath, getVersionPath: $e",
      );
    }
    File versionFile = File(versionPath);
    if (versionPath == "" || !versionFile.existsSync()) {
      dev.log(
        "Error, _scaleAndSaveThumbnailInIsolate: Doc $docIndex, Page $pageIndex, Version $thumbnailIndex does not exist.",
      );
      return false;
    }

    String thumbnailPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_thumbnail.png";
    File thumbnailFile = File(thumbnailPath);
    isolateExitPoint(kill);
    Uint8List versionBytes = versionFile.readAsBytesSync();

    // if overwriting -> delete existing thumbnail file
    try {
      isolateExitPoint(kill);
      for (FileSystemEntity fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("thumbnail")) {
          String oldThumbnailPath = fse.path;
          if (overwrite) {
            //dev.log("Overwriting, writeScaledThumbnail: $pathIn");
            isolateExitPoint(kill);
            File(oldThumbnailPath).deleteSync();
          } else {
            dev.log("Thumbnail already exists, won't overwrite thumbnail.");
            return false;
          }
        }
      }
    } catch (e) {
      dev.log(
        "Warning, _scaleAndSaveThumbnailIsolate: Could not delete old thumbnail: $e",
      );
    }

    OpenCVHelper cvHelper = OpenCVHelper(gIn);
    isolateExitPoint(kill);
    Uint8List scaled = await cvHelper.scaleImageToWidth(
      versionBytes,
      (screenWidth * 0.927083333).toInt(),
    );

    try {
      // Save
      isolateExitPoint(kill);
      thumbnailFile.writeAsBytesSync(scaled); //img.encodePng(resized)
    } catch (e) {
      throw StateError("Error, writeScaledThumbnail, write: :$e");
    }

    try {
      // Update thumbnails:
      isolateExitPoint(kill);
      sendPort.send(NotifierEvent.loadPagesThumbnails);
    } catch (e) {
      throw StateError("Error, writeScaledThumbnail, notify: :$e");
    }

    return true;
  }

  static void _deleteScaledThumbnail(String pagePath) {
    for (FileSystemEntity fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.contains("thumbnail")) {
        try {
          File(fse.path).deleteSync();
        } catch (e) {
          dev.log("Warning, _deleteScaledThumbnail: $e");
        }
      }
    }
  }

  static Future<void> _saveNewThumbnailIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      int thumbnailIndex,
      AppGlobals gIn,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    RootIsolateToken token = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;
    int thumbnailIndex = data.$5;
    AppGlobals gIn = data.$6;

    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      thumbnailIndex,
      gIn,
    );
    Isolate.exit(sendPort, "done");
  }

  Future<void> saveNewThumbnail(
    int docIndex,
    int pageIndex,
    int thumbnailIndex, {
    bool tmpPro = false,
  }) async {
    if (thumbnailIndex == 0) return;
    bool isNewIndex = await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      thumbnailIndex,
      gIn: g,
      tmpPro: tmpPro,
    );

    final port = ReceivePort();
    TaskKiller killer;
    if (isNewIndex) {
      RootIsolateToken token = RootIsolateToken.instance!;
      killer = await IsolatesManager().runTask(
        _saveNewThumbnailIsolate,
        (port.sendPort, token, docIndex, pageIndex, thumbnailIndex, g),
        portIn: port,
        prio: IsolatePriority.regular,
      );
    } else {
      port.close();
      return;
    }
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
        if (message == NotifierEvent.loadPagesThumbnails) {
          if (pageIndex == 0) {
            await Future.delayed(Duration(milliseconds: 100));
            globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
          }
        }
      } else if (message is SendPort) {
        killer.setControlPort(message);
      } else if (message == "done") {
        taskKillers.removeWhere((key, value) => value == killer);
      }
    });
  }

  Future<(int, int)> pdfToDoc(String pdfPath, {int? addToDocWithIndex}) async {
    // Open and render PDF
    final doc = await pdfr.PdfDocument.openFile(pdfPath);
    final pageCount = doc.pageCount;
    // Create Page directories
    int docIndex;
    int firstPageIndex;
    if (addToDocWithIndex != null) {
      docIndex = addToDocWithIndex;
      firstPageIndex = await g.filesHelper.reserveNewPagesInDocment(
        docIndex,
        pageCount,
      );
    } else {
      var newDoc = await g.filesHelper.createNewDocument(pageCount);
      docIndex = newDoc.$1;
      firstPageIndex = newDoc.$2;
    }
    pdfProcessingFutures[docIndex] = _savePdfAsPages(
      firstPageIndex,
      pageCount,
      doc,
      docIndex,
    );
    // Creation Date
    final now = DateTime.now();
    g.metadataHelper.writeDocDate(
      docIndex,
      now.toString(),
      supressWarnings: true,
    );
    return (docIndex, firstPageIndex);
  }

  Map<int, Future<void>> pdfProcessingFutures = {};
  Future<bool> _pdfProcessingExitpoint(int docIndex, {int? pageIndex}) async {
    if ((await g.filesHelper.getMarkedDeletedDocs()).contains(docIndex) ||
        (pageIndex != null &&
            (await g.filesHelper.getMarkedDeletedPages(
              docIndex,
            )).contains(pageIndex))) {
      return true;
    }
    return false;
  }

  Future<void> _savePdfAsPages(
    int firstPageIndex,
    int pageCount,
    pdfr.PdfDocument doc,
    int docIndex,
  ) async {
    await Future.delayed(Duration(milliseconds: 100)); // wait for navigation
    if (await _pdfProcessingExitpoint(docIndex)) return;
    List<Future> futures = [];
    for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      if (await _pdfProcessingExitpoint(docIndex, pageIndex: pageIndex)) return;
      futures.add(
        _savePdfAsPageAsync(doc, docIndex, pageIndex, firstPageIndex),
      );
    }
    // Cleanup
    await Future.wait(futures);
    doc.dispose();
    Future.microtask(() async {
      await Future.delayed(Duration(microseconds: 100));
      pdfProcessingFutures.remove(docIndex);
    });
  }

  Future<void> _savePdfAsPageAsync(
    pdfr.PdfDocument doc,
    int docIndex,
    int pageIndex,
    int firstPageIndex,
  ) async {
    final page = await doc.getPage(pageIndex + 1);
    // render Page at 300 DPI (max 4048 pixel)
    const targetDpi = 300;
    const deafaultAssumedDpi = 72;
    final dpiScale = targetDpi / deafaultAssumedDpi;
    const maxSize = 4048;
    final pageSize = page.width > page.height ? page.width : page.height;
    final limitingScale = (maxSize / pageSize * dpiScale).clamp(
      double.minPositive,
      1.0,
    );
    if (await _pdfProcessingExitpoint(
      docIndex,
      pageIndex: pageIndex + firstPageIndex,
    )) {
      return;
    }
    final renderedPage = await page.render(
      width: (page.width * limitingScale * dpiScale).toInt(),
      height: (page.height * limitingScale * dpiScale).toInt(),
    );
    // -> Uint8List
    final ui.Image uiImage = await renderedPage.createImageDetached();
    final ByteData? byteData = await uiImage.toByteData(
      format: ui.ImageByteFormat.png, // first to png, then to png
    );
    if (byteData == null) {
      throw Exception("Failed to get byte data from image");
    }
    final pngBytes = byteData.buffer.asUint8List();
    // Processing
    if (await _pdfProcessingExitpoint(
      docIndex,
      pageIndex: pageIndex + firstPageIndex,
    )) {
      return;
    }
    processPdfPage(docIndex, pageIndex + firstPageIndex, pngBytes);
  }

  Future<void> processPdfPage(
    int docIndex,
    int pageIndex,
    Uint8List pngBytes,
  ) async {
    if (pngBytes.isEmpty) return;

    final wrapperCompleter = Completer<void>();
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;

    TaskKiller killer = await IsolatesManager().runTask(
      _processPdfPageIsolatePart1,
      (port.sendPort, token, docIndex, pageIndex, pngBytes, g),
      portIn: port,
      prio: IsolatePriority.quick,
      onErrorFunction: (error, stack) async {
        dev.log(
          "_processPdfPageIsolateThumbnail, onErrorFunction: $error $stack",
        );
        if (!error.toString().contains("No photo")) {
          repairPage(docIndex, pageIndex);
        }
      },
    );
    taskKillers[(docIndex, pageIndex)] = killer;

    String? photoPath;
    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
        if (message == NotifierEvent.loadPagesThumbnails) {
          if (pageIndex == 0) {
            await Future.delayed(Duration(milliseconds: 100));
            globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
          }
        }
      } else if (message is SendPort) {
        killer.setControlPort(message);
      } else if (message is String) {
        if (message == "done") {
          wrapperCompleter.complete();
          taskKillers.removeWhere((key, value) => value == killer);
        } else {
          photoPath = message;
        }
      }
    });
    await wrapperCompleter.future;

    final wrapperCompleter2 = Completer<void>();
    final port2 = ReceivePort();

    String extension = photoPath!.split(".").last;
    TaskKiller killer2 = await IsolatesManager().runTask(
      _processPdfPageIsolatePart2,
      (port2.sendPort, token, docIndex, pageIndex, pngBytes, extension, g),

      portIn: port,
      prio: IsolatePriority.late,
      onErrorFunction: (error, stack) async {
        dev.log(
          "_processPdfPageIsolateFilters, onErrorFunction: $error $stack",
        );
        if (!error.toString().contains("No photo")) {
          repairPage(docIndex, pageIndex);
        }
      },
    );
    taskKillers[(docIndex, pageIndex)] = killer2;

    port2.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message is SendPort) {
        killer2.setControlPort(message);
      } else if (message == "done") {
        wrapperCompleter2.complete();

        taskKillers.removeWhere((key, value) => value == killer2);
        killer2.kill();
      }
    });
    await wrapperCompleter2.future;
  }
}
