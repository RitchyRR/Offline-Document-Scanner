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
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
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
    if (shapePath.isNotEmpty && File(shapePath).existsSync()) {
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
      shapeBytes = warpedRet.$2;
      isolateExitPoint(kill);
      await g.filesHelper.savePageShape(docIndex, pageIndex, shapeBytes);
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

    final int initialThumbnailIndex =
        await MetadataHelper.readPageThumbnailIndex(
          docIndex,
          pageIndex,
          gIn: g,
          supressWarnings: true,
        ) ??
        g.defaultIndex;

    // First process (default) Thumbnail version
    isolateExitPoint(kill);
    Uint8List thumbnailVersionBytes = warpedBytes;
    Uint8List? processed2Bytes;
    switch (initialThumbnailIndex) {
      case 2:
        // Contrast
        isolateExitPoint(kill);
        thumbnailVersionBytes = await cvHelper.processImageContrast(
          ParamsProcessImage1(warpedBytes),
        );
        break;
      case 3:
        // Document
        isolateExitPoint(kill);
        thumbnailVersionBytes = await cvHelper.processImageDocument(
          ParamsProcessImage1(warpedBytes),
        );
        break;
      case 4:
        // PRO
        isolateExitPoint(kill);
        processed2Bytes = thumbnailVersionBytes = await cvHelper
            .processImagePro(
              ParamsProcessImage2(warpedBytes, borderCorrectionDepth),
            );
        break;
      case 5:
        isolateExitPoint(kill);
        thumbnailVersionBytes = await cvHelper.processImagePro(
          ParamsProcessImage2(warpedBytes, borderCorrectionDepth),
        );
        // PRO 2
        isolateExitPoint(kill);
        Uint8List processed3Bytes = await cvHelper.processImagePro2(
          ParamsProcessImage3(warpedBytes, thumbnailVersionBytes),
        );
        await g.filesHelper.savePageVersion(
          docIndex,
          pageIndex,
          5,
          processed3Bytes,
          ".png",
        );
        break;
    }
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      initialThumbnailIndex == 5 ? 4 : initialThumbnailIndex,
      thumbnailVersionBytes,
      ".png",
    );

    // Update thumbnails:
    isolateExitPoint(kill);
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    // Kontrast
    isolateExitPoint(kill);
    if (initialThumbnailIndex != 2) {
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

    // Dokument
    isolateExitPoint(kill);
    if (initialThumbnailIndex != 3) {
      Uint8List processed1Bytes = await cvHelper.processImageDocument(
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
    }

    // PRO
    isolateExitPoint(kill);
    if (initialThumbnailIndex != 4 && initialThumbnailIndex != 5) {
      processed2Bytes = await cvHelper.processImagePro(
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
    }

    // PRO 2
    isolateExitPoint(kill);
    if (initialThumbnailIndex != 5) {
      Uint8List processed3Bytes = await cvHelper.processImagePro2(
        ParamsProcessImage3(warpedBytes, processed2Bytes!),
      );
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        5,
        processed3Bytes,
        ".png",
      );
    }

    // Delete old Thumbnail
    isolateExitPoint(kill);
    _deleteScaledThumbnail(pagePath);
    // Set New Thumbnail
    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      g,
    );
    Isolate.exit(sendPort, "done");
  }

  static void isolateExitPoint(final bool kill) {
    if (kill) {
      Isolate.exit();
    }
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

    // Save current (to be outdated) filenames to metadata
    await saveOldVersionFileNames(docIndex, pageIndex);

    final completer = Completer<void>();
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
        completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> saveOldVersionFileNames(int docIndex, int pageIndex) async {
    List<String> versionPaths;
    (versionPaths, _, _) = await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    List<String> fileNames = [];
    for (var path in versionPaths) {
      fileNames.add(
        path.isEmpty
            ? ""
            : path.substring(path.lastIndexOf("/") + 1, path.lastIndexOf(".")),
      );
    }
    MetadataHelper.writeOldVersionFileNames(docIndex, pageIndex, fileNames);
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

    List<String>? oldVersionFileNames =
        await MetadataHelper.readOldPageFileNames(docIndex, pageIndex, gIn: g);

    // Photo
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
    if (versionPaths[1].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[1].contains(oldVersionFileNames[1]))) {
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        1,
        warpedBytes,
        ".png",
      );
    }

    // Contrast
    if (versionPaths[2].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[2].contains(oldVersionFileNames[2]))) {
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

    // Document
    if (versionPaths[3].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[3].contains(oldVersionFileNames[3]))) {
      isolateExitPoint(kill);
      Uint8List processed1 = await cvHelper.processImageDocument(
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

    // PRO
    Uint8List? processed2Bytes;
    if (versionPaths[4].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[4].contains(oldVersionFileNames[4]))) {
      isolateExitPoint(kill);
      processed2Bytes = await cvHelper.processImagePro(
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
    }

    // PRO 2
    if (versionPaths[5].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[5].contains(oldVersionFileNames[5]))) {
      isolateExitPoint(kill);
      processed2Bytes ??= File(versionPaths[4]).readAsBytesSync();
      isolateExitPoint(kill);
      Uint8List processed3Bytes = await cvHelper.processImagePro2(
        ParamsProcessImage3(warpedBytes, processed2Bytes),
      );
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
    // Set New Thumbnail
    if (thumbnailPath.isEmpty) {
      isolateExitPoint(kill);
      await _scaleAndSaveThumbnailInIsolate(
        sendPort,
        kill,
        docIndex,
        pageIndex,
        g,
      );
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
    final int rotationIn,
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
    AppGlobals g = data.$7;

    OpenCVHelper cvHelper = OpenCVHelper(g);

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

    bool isImportedPdf = await MetadataHelper.readPageImportedPdf(
      docIndex,
      pageIndex,
      supressWarnings: true,
      gIn: g,
    );

    /// 2. rotate processed -> save
    if (!isImportedPdf) {
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
    }

    // Update Thumbnail
    isolateExitPoint(kill);
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    // Delete old Thumbnail
    isolateExitPoint(kill);
    _deleteScaledThumbnail(
      await g.filesHelper.getPagePath(docIndex, pageIndex),
    );
    // Set New Thumbnail
    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      g,
    );

    Isolate.exit(sendPort, "done");
  }

  Future<void> rotatePage(
    int docIndex,
    int pageIndex,
    List<String> versionPaths, //[0] is rotated
    final int angle,
    int pageThumbnailIndexIn,
  ) async {
    // Save current (to be outdated) filenames to metadata
    await saveOldVersionFileNames(docIndex, pageIndex);

    final port = ReceivePort();
    final token = RootIsolateToken.instance!;
    final rotatePageCompleter = Completer<void>();

    TaskKiller killer = await IsolatesManager().runTask(
      _rotatePageIsolate,
      (port.sendPort, token, docIndex, pageIndex, versionPaths, angle, g),
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
    AppGlobals gIn,
  ) async {
    // Get thumbnailIndex from metadata, else set it in metadata
    int? metadataThumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
      docIndex,
      pageIndex,
      gIn: gIn,
      supressWarnings: true,
    );
    int thumbnailIndex = metadataThumbnailIndex ?? gIn.defaultIndex;
    if (metadataThumbnailIndex == null) {
      isolateExitPoint(kill);
      await MetadataHelper.writePageThumbnailIndex(
        docIndex,
        pageIndex,
        thumbnailIndex,
        gIn: gIn,
      );
    }

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
        "Warning, _scaleAndSaveThumbnailInIsolate: Doc $docIndex, Page $pageIndex, Version $thumbnailIndex does not exist (yet?).",
      );
      return false;
    }

    final String versionFileName = versionPath.substring(
      versionPath.lastIndexOf("/") + 1,
      versionPath.lastIndexOf("."),
    );

    // if overwriting -> delete existing thumbnail file
    try {
      isolateExitPoint(kill);
      for (FileSystemEntity fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("thumbnail")) {
          String oldThumbnailPath = fse.path;
          if (oldThumbnailPath.contains(versionFileName)) {
            // Is same
            return false;
          } else {
            // Overwrite
            isolateExitPoint(kill);
            File(oldThumbnailPath).deleteSync();
          }
        }
      }
    } catch (e) {
      dev.log(
        "Warning, _scaleAndSaveThumbnailIsolate: Could not delete old thumbnail: $e",
      );
    }

    String thumbnailPath = "$pagePath/${versionFileName}_thumbnail.png";
    File thumbnailFile = File(thumbnailPath);
    isolateExitPoint(kill);
    Uint8List versionBytes = versionFile.readAsBytesSync();

    isolateExitPoint(kill);
    OpenCVHelper cvHelper = OpenCVHelper(gIn);
    isolateExitPoint(kill);
    Uint8List scaledBytes;
    int newWidth = (screenWidth * 0.927083333).toInt();
    int newHeight;
    (scaledBytes, newHeight) = await cvHelper.scaleImageToWidth(
      versionBytes,
      newWidth,
    );

    isolateExitPoint(kill);
    final Uint8List compressedPngBytes =
        await FlutterImageCompress.compressWithList(
          scaledBytes,
          minWidth: newWidth,
          minHeight: newHeight,
          format: CompressFormat.png,
          quality: 1,
        );

    try {
      // Save
      isolateExitPoint(kill);
      thumbnailFile.writeAsBytesSync(compressedPngBytes);
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
    AppGlobals gIn = data.$5;

    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      gIn,
    );
    Isolate.exit(sendPort, "done");
  }

  Future<void> setNewThumbnail(
    int docIndex,
    int pageIndex,
    int thumbnailIndex, {
    bool tmpPro = false,
  }) async {
    if (thumbnailIndex == 0) return;

    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      thumbnailIndex,
    );

    final port = ReceivePort();
    RootIsolateToken token = RootIsolateToken.instance!;
    TaskKiller killer = await IsolatesManager().runTask(
      _saveNewThumbnailIsolate,
      (port.sendPort, token, docIndex, pageIndex, g),
      portIn: port,
      prio: IsolatePriority.regular,
    );

    taskKillers[(docIndex, pageIndex)] = killer;

    final completer = Completer<void>();
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
        completer.complete();
      }
    });
    await completer.future;
  }

  Future<(int, int)> importPdf(String pdfPath, {int? addToDocWithIndex}) async {
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
        importedPdf: true,
      );
    } else {
      var newDoc = await g.filesHelper.createNewDocument(
        pageCount,
        importedPdf: true,
      );
      docIndex = newDoc.$1;
      firstPageIndex = newDoc.$2;
    }
    pdfProcessingFutures[docIndex] = _convertPdfToPages(
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

  Future<void> _convertPdfToPages(
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
      futures.add(_convertPdfToPage(doc, docIndex, pageIndex, firstPageIndex));
    }
    // Cleanup
    await Future.wait(futures);
    doc.dispose();
    Future.microtask(() async {
      await Future.delayed(Duration(microseconds: 100));
      pdfProcessingFutures.remove(docIndex);
    });
  }

  Future<void> _convertPdfToPage(
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
    _processPdfPage(docIndex, pageIndex + firstPageIndex, pngBytes);
  }

  Future<void> _processPdfPage(
    int docIndex,
    int pageIndex,
    Uint8List pngBytes,
  ) async {
    if (pngBytes.isEmpty) return;

    final wrapperCompleter = Completer<void>();
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;

    TaskKiller killer = await IsolatesManager().runTask(
      _processPdfPageIsolate,
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
        wrapperCompleter.complete();
        taskKillers.removeWhere((key, value) => value == killer);
      }
    });
    await wrapperCompleter.future;
  }

  static void _processPdfPageIsolate(
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
      0,
      gIn: g,
      supressWarnings: true,
    );

    // Save Photo
    isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      0,
      pngBytes,
      ".png",
    );
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    // Generate Metadata
    isolateExitPoint(kill);
    final imgInfo = AppGlobals.getPngInfo(pngBytes);
    if (imgInfo == null) {
      throw StateError("Error, processPdfPage: can't decode Image.");
    }
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
      null,
      gIn: g,
    );

    isolateExitPoint(kill);
    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      0,
      gIn: g,
    );
    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(
      sendPort,
      kill,
      docIndex,
      pageIndex,
      g,
    );

    Isolate.exit(sendPort, "done");
  }

  Future<String> scaleImageToDpi(
    int docIndex,
    int pageIndex,
    int versionIndex,
    int toDPI,
    double widthInInches,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final scaledImagePath =
        "${tmpDir.path}/scaled_${docIndex}_${pageIndex}_DPI_$toDPI.png";

    final port = ReceivePort();
    TaskKiller killer;
    RootIsolateToken token = RootIsolateToken.instance!;

    killer = await IsolatesManager().runTask(
      _scaleImageToDpiIsolate,
      (
        port.sendPort,
        token,
        docIndex,
        pageIndex,
        versionIndex,
        scaledImagePath,
        toDPI,
        widthInInches,
        g,
      ),
      portIn: port,
      prio: IsolatePriority.quick,
    );

    taskKillers[(docIndex, pageIndex)] = killer;

    final completer = Completer<void>();
    port.listen((message) async {
      if (message is SendPort) {
        killer.setControlPort(message);
      } else if (message == "done") {
        completer.complete();
        taskKillers.removeWhere((key, value) => value == killer);
      }
    });
    await completer.future;
    return scaledImagePath;
  }

  static void _scaleImageToDpiIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      int versionIndex,
      String scaledImagePath,
      int toDpi,
      double widthInInches,
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
    int versionIndex = data.$5;

    String scaledImagePath = data.$6;
    int toDpi = data.$7;
    double widthInInches = data.$8;

    AppGlobals g = data.$9;

    String versionPath;
    try {
      isolateExitPoint(kill);
      versionPath = await g.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        versionIndex,
      );
    } catch (e) {
      throw StateError(
        "Error, _scaleImageIsolate, getPagePath, getVersionPath: $e",
      );
    }
    File versionFile = File(versionPath);
    if (versionPath == "" || !versionFile.existsSync()) {
      throw StateError(
        "Error, _scaleImageIsolate: Doc $docIndex, Page $pageIndex, Version $versionIndex does not exist.",
      );
    }

    File scaledIamgeFile = File(scaledImagePath);
    isolateExitPoint(kill);
    Uint8List versionBytes = versionFile.readAsBytesSync();

    isolateExitPoint(kill);
    OpenCVHelper cvHelper = OpenCVHelper(g);
    // Scale
    isolateExitPoint(kill);
    Uint8List scaledBytes;
    int newWidth = (widthInInches * toDpi).toInt();
    int newHeight;
    (scaledBytes, newHeight) = await cvHelper.scaleImageToWidth(
      versionBytes,
      newWidth,
    );

    isolateExitPoint(kill);
    final Uint8List compressedPngBytes =
        await FlutterImageCompress.compressWithList(
          scaledBytes,
          minWidth: newWidth,
          minHeight: newHeight,
          format: CompressFormat.png,
          quality: 1,
        );

    try {
      // Save
      isolateExitPoint(kill);
      scaledIamgeFile.writeAsBytesSync(compressedPngBytes);
    } catch (e) {
      throw StateError("Error, writeScaledThumbnail, write: :$e");
    }

    Isolate.exit(sendPort, "done");
  }
}
