// function:
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show WidgetsBinding;
import 'package:flutter_image_compress/flutter_image_compress.dart'
    show FlutterImageCompress, CompressFormat;
import 'dart:io';
import 'dart:async';
// isolates:
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'dart:isolate' show ReceivePort, SendPort;
import 'package:docscanner/isolates_manager.dart';
// my packages:
import 'package:docscanner/opencv_helper.dart';
import 'package:docscanner/main.dart' show globalNotifier;
import 'package:docscanner/metadata_helper.dart';
import 'package:docscanner/app_globals.dart';

const List<String> versionNames = [
  "photo",
  "warped",
  "processed1",
  "processed2",
];

class ImageProcessingManager {
  Map<(int, int), TaskKiller> taskKillers = {};

  static void _processPageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      Uint8List? photoBytes,
      String? photoExtension,
      double? ratioValueIn,
      List<List<int>>? cornerPointsIn,
      int rotationIn,
      bool isInitial,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    int docIndex = data.$3;
    int pageIndex = data.$4;
    Uint8List? photoBytes = data.$5;
    String? photoExtension = data.$6;

    double? ratioValueIn = data.$7;
    List<List<int>>? cornerPointsIn = data.$8;
    int rotationIn = data.$9;
    bool isInitial = data.$10;
    AppGlobals g = data.$11;

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

    String photoPath;
    if (photoBytes != null && photoExtension != null) {
      // Write photo into storage
      photoPath = await g.filesHelper.writeImageRaw(
        docIndex,
        pageIndex,
        0,
        photoBytes,
        photoExtension,
      );
    } else {
      // Use existing version 0
      photoPath = await g.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        0,
        supressWarnings: true,
      );
      if (File(photoPath).existsSync() && File(photoPath).lengthSync() != 0) {
      } else {
        throw StateError("Error, _processPageIsolate: No photo");
      }
    }

    List<String> versionPaths = List.generate(4, (index) => "");
    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Delete old Thumbnail
    _deleteScaledThumbnail(pagePath);
    // Original
    versionPaths[0] = photoPath;
    // Re-use Shape
    String shapePath = await g.filesHelper.getPageShape(
      docIndex,
      pageIndex,
      supressWarnings: isInitial,
    );
    // don't use corrupted shape
    if (shapePath.isNotEmpty && File(shapePath).lengthSync() == 0) {
      shapePath = "";
    }

    if (shapePath.isNotEmpty && rotationIn != 0) {
      Uint8List rotatedShape = await cvHelper.rotateImage(
        shapePath,
        rotationIn,
      );

      shapePath = await g.filesHelper.savePageShape(
        docIndex,
        pageIndex,
        rotatedShape,
      );
    }

    // Warped + Metadata
    var warpedRet = await cvHelper.warpImage(
      ParamsWarpImage(
        versionPaths[0],
        shapePath,
        ratioValueIn: ratioValueIn,
        cornerPoints: cornerPointsIn,
      ),
    );

    Uint8List warped = warpedRet.$1;
    Uint8List shape = warpedRet.$2;
    if (shapePath.isEmpty) {
      g.filesHelper.savePageShape(docIndex, pageIndex, shape);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    double? ratioValue = warpedRet.$4;
    List<List<int>>? cornerPoints = warpedRet.$5;

    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );
    versionPaths[1] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      1,
      warped,
    );

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = await cvHelper.processImage1(
      ParamsProcessImage1(versionPaths[1]),
    );

    //versionPaths[2] =
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 2, processed1);

    // Processed2 basierend auf dem Warped-Bild
    Uint8List processed2 = await cvHelper.processImage2(
      ParamsProcessImage2(versionPaths[1], borderCorrectionDepth),
    );

    //versionPaths[3] =
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 3, processed2);

    // Update thumbnails:
    Future.microtask(() => sendPort.send(NotifierEvent.loadPagesThumbnails));
    sendPort.send(NotifierEvent.loadDocsThumbnails);
    if (isInitial) {
      int? thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        pageIndex,
        gIn: g,
        supressWarnings: true,
      );

      bool newThumbnail = await _scaleAndSaveThumbnailIsolate(
        sendPort,
        docIndex,
        pageIndex,
        thumbnailIndex,
        g,
        overwrite: !isInitial,
      );

      if (newThumbnail) {
        await MetadataHelper.writePageThumbnailIndex(
          docIndex,
          pageIndex,
          thumbnailIndex ?? ((g.proUnlocked == true) ? 3 : 2),
          gIn: g,
          supressWarnings: true,
        );
      }
    }

    sendPort.send("done");
    //Isolate.exit(sendPort, "done");
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

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    Uint8List pngBytes = data.$5;
    AppGlobals g = data.$6;

    // Thumbnail
    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      1,
      gIn: g,
      supressWarnings: true,
    );

    // Save Photo
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 0, pngBytes);
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);

    // Generate Metadata
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
    final matchingValue = cvHelper.matchAspectRatioAndOrientation(
      imgInfo.height / imgInfo.width,
    );
    double ratioValueIn = matchingValue;

    // Write Metadata
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValueIn,
      cornerPointsIn,
      gIn: g,
    );

    await _scaleAndSaveThumbnailIsolate(sendPort, docIndex, pageIndex, 0, g);

    sendPort.send("done");
  }

  static void _processPdfPageIsolatePart2(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      String photoPath,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    String photoPath = data.$5;
    AppGlobals g = data.$6;

    OpenCVHelper cvHelper = OpenCVHelper(g);
    List<int> borderCorrectionDepth = List<int>.generate(4, (_) => 0);

    // Warped
    String pagePath = await g.filesHelper.getPagePath(docIndex, pageIndex);
    String versionName = versionNames[1];
    String extension = photoPath.split(".").last;
    String versionPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$versionName.$extension";
    File(photoPath).copySync(versionPath);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = await cvHelper.processImage1(
      ParamsProcessImage1(photoPath),
    );
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 2, processed1);

    // Processed2 basierend auf dem Warped-Bild
    Uint8List processed2 = await cvHelper.processImage2(
      ParamsProcessImage2(photoPath, borderCorrectionDepth),
    );
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 3, processed2);

    sendPort.send("done");
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

    Uint8List? photoBytes;
    String? photoExtension;
    if (!isPhotoAlreadyInPage) {
      final imageRaw = await g.filesHelper.readImageRaw(photoPath);
      photoBytes = imageRaw.$1;
      photoExtension = imageRaw.$2;
    }

    final wrapperCompleter = Completer<void>();
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;

    TaskKiller killer = await IsolatesManager().runTask(
      _processPageIsolate,
      (
        port.sendPort,
        token,
        docIndex,
        pageIndex,
        photoBytes,
        photoExtension,
        ratioValueIn,
        cornerPointsIn,
        rotationIn,
        isInitial,
        g,
      ),
      prio: prio,
      onErrorFunction: (error, stack) async {
        dev.log("_processPageIsolate, onErrorFunction: $error $stack");
        if (!error.toString().contains("No photo")) {
          repairPage(docIndex, pageIndex);
        }
      },
    );

    taskKillers[(docIndex, pageIndex)] = killer;
    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == "done") {
        port.close();
        wrapperCompleter.complete();

        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
    await wrapperCompleter.future;
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

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == "done") {
        port.close();
        wrapperCompleter.complete();

        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
    await wrapperCompleter.future;

    final wrapperCompleter2 = Completer<void>();
    final port2 = ReceivePort();

    final photoPath = await g.filesHelper.getVersionPath(
      docIndex,
      pageIndex,
      0,
    );

    TaskKiller killer2 = await IsolatesManager().runTask(
      _processPdfPageIsolatePart2,
      (port2.sendPort, token, docIndex, pageIndex, photoPath, g),
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
      } else if (message == "done") {
        port2.close();
        wrapperCompleter2.complete();

        taskKillers.removeWhere((key, value) => value == killer2);
        killer2.kill();
      }
    });
    await wrapperCompleter2.future;
  }

  static Future<void> _repairPageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      double? ratioValueIn,
      List<List<int>>? cornerPointsIn,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort? sendPort = data.$1;

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;

    double? ratioValueIn = data.$5;
    List<List<int>>? cornerPointsIn = data.$6;
    AppGlobals g = data.$7;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Original
    var imagePaths = await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    List<String> versionPaths = imagePaths.$1;
    String shapePath = imagePaths.$2;
    String thumbnailPath = imagePaths.$3;

    final photoFile = File(versionPaths[0]);
    if (!photoFile.existsSync() || photoFile.lengthSync() < 9) {
      throw StateError("Error, _repairPageIsolate: No photo");
    }

    // Warped
    var warpedRet = await cvHelper.warpImage(
      ParamsWarpImage(
        versionPaths[0],
        shapePath,
        ratioValueIn: ratioValueIn,
        cornerPoints: cornerPointsIn,
        onlyCalculateBorder: versionPaths[1].isNotEmpty,
      ),
    );
    Uint8List warped = warpedRet.$1;
    Uint8List shape = warpedRet.$2;
    if (shapePath.isEmpty) {
      g.filesHelper.savePageShape(docIndex, pageIndex, shape);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    // Metadata
    double ratioValue = warpedRet.$4;
    List<List<int>> cornerPoints = warpedRet.$5;
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );

    if (versionPaths[1].isEmpty) {
      versionPaths[1] = await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        1,
        warped,
      );
    }

    // Processed1 basierend auf dem Warped-Bild
    if (versionPaths[2].isEmpty) {
      Uint8List processed1 = await cvHelper.processImage1(
        ParamsProcessImage1(versionPaths[1]),
      );
      versionPaths[2] = await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        2,
        processed1,
      );
    }

    // Processed2 basierend auf dem Warped-Bild
    if (versionPaths[3].isEmpty) {
      Uint8List processed2 = await cvHelper.processImage2(
        ParamsProcessImage2(versionPaths[1], borderCorrectionDepth),
      );
      versionPaths[3] = await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        3,
        processed2,
      );
    }

    // Update thumbnails:
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);

    if (thumbnailPath.isEmpty) {
      int? thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        pageIndex,
        gIn: g,
      );
      bool newThumbnail = await _scaleAndSaveThumbnailIsolate(
        sendPort,
        docIndex,
        pageIndex,
        thumbnailIndex,
        g,
        overwrite: false,
      );
      if (newThumbnail) {
        await MetadataHelper.writePageThumbnailIndex(
          docIndex,
          pageIndex,
          thumbnailIndex ?? (g.proUnlocked == true ? 3 : 2),
          gIn: g,
        );
      }
    }

    sendPort.send("done");
  }

  void killIsolatesOfPage(int docIndex, int pageIndex) {
    var key = (docIndex, pageIndex);
    if (taskKillers.containsKey(key)) {
      (taskKillers[key]!).kill();
      taskKillers.remove(key);
    }
  }

  void delayIsolatesOfPage(int docIndex, int pageIndex) {
    var key = (docIndex, pageIndex);
    if (taskKillers.containsKey(key)) {
      taskKillers[key]?.delay();
    }
  }

  void killIsolatesOfDocument(int docIndex) {
    List<(int, int)> keys = [];
    for (var key in taskKillers.keys) {
      if (key.$1 == docIndex) {
        keys.add(key);
      }
    }
    for (var key in keys) {
      taskKillers[key]!.kill();
      taskKillers.remove(key);
    }
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
      final docKeys = taskKillers.keys
          .where((key) => key.$1 == docIndex)
          .toList();
      final docIsolates = docKeys.map((key) => taskKillers[key]!).toList();

      if (docIsolates.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitAllIsolates() async {
    while (taskKillers.isNotEmpty) {
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
    _processPageWrapper(
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
        // small delay between starts
        await Future.delayed(Duration(milliseconds: 100));
        _processPageWrapper(
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
    killIsolatesOfPage(docIndex, pageIndex);
    Future.delayed(Duration(milliseconds: 100));
    _processPageWrapper(
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
    if (!File(
      await g.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        0,
        supressWarnings: true,
      ),
    ).existsSync()) {
      dev.log("repairPageIsolate: Doc $docIndex, Page $pageIndex: No photo");
      if (File(
        await g.filesHelper.getPagePath(
          docIndex,
          pageIndex,
          supressWarnings: true,
        ),
      ).existsSync()) {
        g.filesHelper.deleteImages(null, docIndex, pageIndexes: [pageIndex]);
      }
      return;
    }

    final repairCompleter = Completer<void>();
    final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
    final port = ReceivePort();

    // Read Matadata
    var processingMetadata = await g.metadataHelper.readPageProcessingMetadata(
      docIndex,
      pageIndex,
    );
    double? ratioValue = processingMetadata.$1;
    List<List<int>>? cornerPoints = processingMetadata.$2;

    while (taskKillers.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    RootIsolateToken token = RootIsolateToken.instance!;
    TaskKiller killer = await IsolatesManager().runTask(
      _repairPageIsolate,
      (port.sendPort, token, docIndex, pageIndex, ratioValue, cornerPoints, g),
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
      } else if (message == "done") {
        port.close();
        repairCompleter.complete();

        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
    await repairCompleter.future;
  }

  static Future<void> _rotatePageIsolate(
    (
      SendPort sendPort,
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

    int docIndex = data.$2;
    int pageIndex = data.$3;
    List<String> versionPaths = data.$4;
    int rotationIn = data.$5;
    int pageThumbnailIndexIn = data.$6;
    AppGlobals g = data.$7;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Delete old Thumbnail
    _deleteScaledThumbnail(
      await g.filesHelper.getPagePath(docIndex, pageIndex),
    );

    /// 1. save rotated photo

    final imgInfo = await AppGlobals.getImageInfo(versionPaths[0]);
    final Uint8List? pngBytes = await FlutterImageCompress.compressWithFile(
      versionPaths[0],
      minWidth: imgInfo!.width,
      minHeight: imgInfo.height,
      format: CompressFormat.png,
      quality: 100,
    );
    if (pngBytes == null) {
      throw StateError("photo $versionPaths[0] does not exist");
    }
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 0, pngBytes);

    /// 2. rotate processed -> save

    // Shape
    String? shapePath = await g.filesHelper.getPageShape(docIndex, pageIndex);
    if (shapePath.isEmpty && rotationIn != 0) {
      Uint8List rotatedShape = await cvHelper.rotateImage(
        shapePath,
        rotationIn,
      );
      shapePath = await g.filesHelper.savePageShape(
        docIndex,
        pageIndex,
        rotatedShape,
      );
    }

    // Warped
    Uint8List rotatedWarped = await cvHelper.rotateImage(
      versionPaths[1],
      rotationIn,
    );
    versionPaths[1] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      1,
      rotatedWarped,
    );

    // Processed1
    Uint8List rotatedP1 = await cvHelper.rotateImage(
      versionPaths[2],
      rotationIn,
    );
    versionPaths[2] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      2,
      rotatedP1,
    );

    // Processed2
    Uint8List rotatedP2 = await cvHelper.rotateImage(
      versionPaths[3],
      rotationIn,
    );
    versionPaths[3] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      3,
      rotatedP2,
    );

    // Updates
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);

    bool newThumbnail = await _scaleAndSaveThumbnailIsolate(
      sendPort,
      docIndex,
      pageIndex,
      pageThumbnailIndexIn,
      g,
      overwrite: false,
    );
    if (newThumbnail) {
      await MetadataHelper.writePageThumbnailIndex(
        docIndex,
        pageIndex,
        pageThumbnailIndexIn,
        gIn: g,
      );
    }

    sendPort.send("done");
  }

  Future<void> rotatePage(
    int docIndex,
    int pageIndex,
    List<String> versionPaths, //[0] is rotated
    int angle,
    int pageThumbnailIndexIn,
  ) async {
    final port = ReceivePort();
    final rotatePageCompleter = Completer<void>();

    TaskKiller killer = await IsolatesManager().runTask(_rotatePageIsolate, (
      port.sendPort,
      docIndex,
      pageIndex,
      versionPaths,
      angle,
      pageThumbnailIndexIn,
      g,
    ), prio: IsolatePriority.immediate);
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == "done") {
        port.close();
        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
    await rotatePageCompleter.future;
  }

  static Future<bool> _scaleAndSaveThumbnailIsolate(
    SendPort sendPort,
    int docIndex,
    int pageIndex,
    int? thumbnailIndex,
    AppGlobals gIn, {
    bool overwrite = true,
  }) async {
    thumbnailIndex ??= (gIn.proUnlocked == true ? 3 : 2);

    int screenWidth = gIn.filesHelper.screenWidth;
    String pagePath;
    String versionPath;
    try {
      pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
      versionPath = await gIn.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        thumbnailIndex,
      );
    } catch (e) {
      throw StateError(
        "Error, _scaleAndSaveThumbnail, getPagePath, getVersionPath: $e",
      );
    }

    String thumbnailPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_thumbnail.png";
    File versionFile = File(versionPath);
    File thumbnailFile = File(thumbnailPath);

    if (!versionFile.existsSync()) {
      throw StateError(
        "Error, _scaleAndSaveThumbnailIsolate: Doc $docIndex, Page $pageIndex, Version $thumbnailIndex does not exist",
      );
    }

    // if overwriting -> delete existing thumbnail file
    try {
      for (FileSystemEntity fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("thumbnail")) {
          String oldThumbnailPath = fse.path;
          if (overwrite) {
            //dev.log("Overwriting, writeScaledThumbnail: $pathIn");
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
    Uint8List scaled = await cvHelper.scaleImageToWidth(
      versionPath,
      (screenWidth * 0.927083333).toInt(),
    );

    try {
      // Save
      thumbnailFile.writeAsBytesSync(scaled); //img.encodePng(resized)
    } catch (e) {
      throw StateError("Error, writeScaledThumbnail, write: :$e");
    }

    try {
      // Update thumbnails:
      sendPort.send(NotifierEvent.loadPagesThumbnails);
      sendPort.send(NotifierEvent.loadDocsThumbnails);
    } catch (e) {
      throw StateError("Error, writeScaledThumbnail, notify: :$e");
    }

    return true;
  }

  static _deleteScaledThumbnail(String pagePath) {
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

    RootIsolateToken token = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;
    int thumbnailIndex = data.$5;
    AppGlobals gIn = data.$6;

    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    await _scaleAndSaveThumbnailIsolate(
      sendPort,
      docIndex,
      pageIndex,
      thumbnailIndex,
      gIn,
    );
    sendPort.send("done");
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

    final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
    final port = ReceivePort();

    while (taskKillers.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    TaskKiller killer;
    if (isNewIndex) {
      RootIsolateToken token = RootIsolateToken.instance!;
      killer = await IsolatesManager().runTask(_saveNewThumbnailIsolate, (
        port.sendPort,
        token,
        docIndex,
        pageIndex,
        thumbnailIndex,
        g,
      ), prio: IsolatePriority.regular);
    } else {
      port.close();
      return;
    }
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == "done") {
        port.close();
        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
  }
}
