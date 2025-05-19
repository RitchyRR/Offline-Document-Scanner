// function:
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
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
      String newPhotoPath,
      double? ratioValueIn,
      int? orientationIndexIn,
      int? pageThumbnailIndex,
      List<List<int>>? cornerPointsIn,
      int rotationIn,
      bool isInitial,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    int docIndex = data.$3;
    int pageIndex = data.$4;
    String newPhotoPath = data.$5;

    double? ratioValueIn = data.$6;
    int? orientationIndexIn = data.$7;
    int? pageThumbnailIndexIn = data.$8;
    List<List<int>>? cornerPointsIn = data.$9;
    int rotationIn = data.$10;
    bool isInitial = data.$11;
    if (pageThumbnailIndexIn == 0) {
      throw StateError('Error, _processPageIsolate: photo cant be thumbnail');
    }
    AppGlobals g = data.$12;
    if (!File(newPhotoPath).existsSync() ||
        File(newPhotoPath).lengthSync() == 0) {
      final actualPhotoPath = await g.filesHelper.getVersionPath(
        docIndex,
        pageIndex,
        0,
      );
      if (File(actualPhotoPath).existsSync() ||
          File(actualPhotoPath).lengthSync() == 0) {
        newPhotoPath = actualPhotoPath;
        dev.log(
          "Warning, _processPageIsolate: newPhotoPath was the wrong path, continuing with real path",
        );
      } else {
        StateError('Error, _processPageIsolate: no photo');
      }
    }
    int thumbnailIndex =
        pageThumbnailIndexIn ?? ((g.proUnlocked == true) ? 3 : 2);

    List<String> versionPaths = List.generate(4, (index) => "");
    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Delete old Thumbnail
    _deleteScaledThumbnail(sendPort, path.dirname(newPhotoPath));
    // Original
    versionPaths[0] = newPhotoPath;
    // Re-use Shape
    String shapePath = await g.filesHelper.getPageShape(
      docIndex,
      pageIndex,
      supressWarnings: isInitial,
    );
    if (shapePath.isNotEmpty && rotationIn != 0) {
      Uint8List rotatedShape = cvHelper.rotateImage(shapePath, rotationIn);
      shapePath = await g.filesHelper.savePageShape(
        docIndex,
        pageIndex,
        rotatedShape,
      );
    }

    // Warped + Metadata
    var warpedRet = cvHelper.warpImage(
      ParamsWarpImage(
        versionPaths[0],
        shapePath,
        ratioValueIn: ratioValueIn,
        orientation: orientationIndexIn,
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
    int? orientationIndex = warpedRet.$5;
    List<List<int>>? cornerPoints = warpedRet.$6;

    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      orientationIndex,
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
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(versionPaths[1]),
    );
    versionPaths[2] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      2,
      processed1,
    );

    // Processed2 basierend auf dem Warped-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(versionPaths[1], borderCorrectionDepth),
    );
    versionPaths[3] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      3,
      processed2,
    );

    // Update thumbnails:
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);
    if (isInitial) {
      bool newThumbnail = await _scaleAndSaveThumbnail(
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
          thumbnailIndex,
          gIn: g,
        );
      }
    }

    sendPort.send('done');
  }

  static void _processPdfPageIsolateThumbnail(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      Uint8List photoBytes,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    Uint8List photoBytes = data.$5;
    AppGlobals g = data.$6;

    // Save Photo
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 0, photoBytes);

    // Generate Metadata
    final imgInfo = AppGlobals.getImageInfo(photoBytes);
    if (imgInfo == null) {
      throw StateError("Error, processPdfPage: can't decode Image.");
    }
    List<List<int>> cornerPointsIn = [
      [0, 0],
      [imgInfo.height - 1, 0],
      [0, imgInfo.width - 1],
      [imgInfo.height - 1, imgInfo.width - 1],
    ];
    int orientationIndexIn = imgInfo.height >= imgInfo.width ? 0 : 1;
    OpenCVHelper cvHelper = OpenCVHelper(g);
    final ratioData = cvHelper.matchAspectRatioAndOrientation(
      imgInfo.height / imgInfo.width,
      null,
      orientationIndexIn,
    );
    double ratioValueIn = ratioData.$1;

    // Write Metadata
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValueIn,
      orientationIndexIn,
      cornerPointsIn,
      gIn: g,
    );
    // Thumbnail
    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      1,
      gIn: g,
    );
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);
    await _scaleAndSaveThumbnail(sendPort, docIndex, pageIndex, 0, g);

    sendPort.send('done');
  }

  static void _processPdfPageIsolateFilters(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      Uint8List photoBytes,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    Uint8List photoBytes = data.$5;
    AppGlobals g = data.$6;

    // Warped
    String warpedPath = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      1,
      photoBytes,
    );

    OpenCVHelper cvHelper = OpenCVHelper(g);
    List<int> borderCorrectionDepth = List<int>.generate(4, (_) => 0);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = cvHelper.processImage1(
      ParamsProcessImage1(warpedPath),
    );
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 2, processed1);

    // Processed2 basierend auf dem Warped-Bild
    Uint8List processed2 = cvHelper.processImage2(
      ParamsProcessImage2(warpedPath, borderCorrectionDepth),
    );
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 3, processed2);

    sendPort.send('done');
  }

  Future<void> _processPageWrapper(
    int docIndex,
    int pageIndex,
    String photoPath,
    double? ratioValueIn,
    int? orientationIndexIn,
    int? pageThumbnailIndex,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
    bool isInitial,
    bool isPhotoAlreadyInPage,
    IsolatePriority prio,
  ) async {
    if (photoPath.isEmpty) return;

    if (!isPhotoAlreadyInPage) {
      // Save Photo
      File photoFile = File(photoPath);
      Uint8List photo;
      if (photoFile.existsSync()) {
        photo = photoFile.readAsBytesSync();
      } else {
        throw StateError('photo does not exist');
      }
      photoPath = await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        0,
        photo,
      );
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
        photoPath,
        ratioValueIn,
        orientationIndexIn,
        pageThumbnailIndex,
        cornerPointsIn,
        rotationIn,
        isInitial,
        g,
      ),
      prio: prio,
      onErrorFunction: (error, stack) async {
        repairPage(docIndex, pageIndex);
      },
    );

    taskKillers[(docIndex, pageIndex)] = killer;
    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
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
    Uint8List photoBytes,
  ) async {
    if (photoBytes.isEmpty) return;

    final wrapperCompleter = Completer<void>();
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;

    TaskKiller killer = await IsolatesManager().runTask(
      _processPdfPageIsolateThumbnail,
      (port.sendPort, token, docIndex, pageIndex, photoBytes, g),
      prio: IsolatePriority.immediate,
      onErrorFunction: (error, stack) async {
        repairPage(docIndex, pageIndex);
      },
    );
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        wrapperCompleter.complete();

        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
    await wrapperCompleter.future;

    final wrapperCompleter2 = Completer<void>();
    final port2 = ReceivePort();

    killer = await IsolatesManager().runTask(
      _processPdfPageIsolateFilters,
      (port2.sendPort, token, docIndex, pageIndex, photoBytes, g),
      prio: IsolatePriority.late,
      onErrorFunction: (error, stack) async {
        repairPage(docIndex, pageIndex);
      },
    );
    taskKillers[(docIndex, pageIndex)] = killer;

    port2.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port2.close();
        wrapperCompleter2.complete();

        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
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
      int? orientationIndexIn,
      List<List<int>>? cornerPointsIn,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;

    double? ratioValueIn = data.$5;
    int? orientationIndexIn = data.$6;
    List<List<int>>? cornerPointsIn = data.$7;
    AppGlobals g = data.$8;

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
      throw StateError('Error, _repairPageIsolate: no photo');
    }

    // Warped
    var warpedRet = cvHelper.warpImage(
      ParamsWarpImage(
        versionPaths[0],
        shapePath,
        ratioValueIn: ratioValueIn,
        orientation: orientationIndexIn,
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
    int orientationIndex = warpedRet.$5;
    List<List<int>> cornerPoints = warpedRet.$6;
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      orientationIndex,
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
      Uint8List processed1 = cvHelper.processImage1(
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
      Uint8List processed2 = cvHelper.processImage2(
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
      int thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        pageIndex,
        gIn: g,
      );
      bool newThumbnail = await _scaleAndSaveThumbnail(
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
          thumbnailIndex,
          gIn: g,
        );
      }
    }

    sendPort.send('done');
  }

  Future<void> killIsolatesOfPage(int docIndex, int pageIndex) async {
    var key = (docIndex, pageIndex);
    if (taskKillers.containsKey(key)) {
      (taskKillers[key]!).kill();
      taskKillers.remove(key);
    }
  }

  Future<void> delayIsolatesOfPage(int docIndex, int pageIndex) async {
    var key = (docIndex, pageIndex);
    if (taskKillers.containsKey(key)) {
      taskKillers[key]?.delay();
    }
  }

  Future<void> killIsolatesOfDocument(int docIndex) async {
    List<(int, int)> secundaryKeys = [];
    for (var key in taskKillers.keys) {
      if (key.$1 == docIndex) {
        secundaryKeys.add(key);
      }
    }
    for (var key in secundaryKeys) {
      taskKillers[key]!.kill();
      taskKillers.remove(key);
    }
  }

  Future<void> delayIsolatesOfDocument(int docIndex) async {
    List<(int, int)> secundaryKeys = [];
    for (var key in taskKillers.keys) {
      if (key.$1 == docIndex) {
        secundaryKeys.add(key);
      }
    }
    for (var key in secundaryKeys) {
      taskKillers[key]?.delay();
      await Future.delayed(Duration(milliseconds: 20));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexedDocuments(int docIndex) async {
    while (taskKillers.isNotEmpty) {
      final otherKeys =
          taskKillers.keys.where((key) => key.$1 > docIndex).toList();
      final otherIsolates = otherKeys.map((key) => taskKillers[key]!).toList();

      if (otherIsolates.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexPage(int docIndex, pageIndex) async {
    while (taskKillers.isNotEmpty) {
      final otherKeys =
          taskKillers.keys
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
      final otherKeys =
          taskKillers.keys
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
      final docKeys =
          taskKillers.keys.where((key) => key.$1 == docIndex).toList();
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
    int? orientationIn,
    int? pageThumbnailIndex,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
  ) async {
    _processPageWrapper(
      docIndex,
      pageIndex,
      pathIn,
      ratioValueIn,
      orientationIn,
      pageThumbnailIndex,
      cornerPointsIn,
      rotationIn,
      false,
      false,
      IsolatePriority.immediate,
    );
  }

  Future<void> repairPage(int docIndex, int pageIndex) async {
    final repairCompleter = Completer<void>();
    final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
    ReceivePort port = ReceivePort();

    // Read Matadata
    var processingMetadata = await g.metadataHelper.readPageProcessingMetadata(
      docIndex,
      pageIndex,
    );
    double? ratioValue = processingMetadata.$1;
    int? orientationIndex = processingMetadata.$2;
    List<List<int>>? cornerPoints = processingMetadata.$3;

    while (taskKillers.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    RootIsolateToken token = RootIsolateToken.instance!;
    TaskKiller killer = await IsolatesManager().runTask(
      _repairPageIsolate,
      (
        port.sendPort,
        token,
        docIndex,
        pageIndex,
        ratioValue,
        orientationIndex,
        cornerPoints,
        g,
      ),
      prio: IsolatePriority.regular,
      onErrorFunction: (error, stack) {
        dev.log("Error, _repairPageIsolate -> deleting page: $error $stack");
        g.filesHelper.deleteImages(null, docIndex, pageIndexes: [pageIndex]);
      },
    );
    taskKillers[(docIndex, pageIndex)] = killer;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
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
    SendPort sendPort = data.$1;
    int docIndex = data.$2;
    int pageIndex = data.$3;
    List<String> versionPaths = data.$4;
    int rotationIn = data.$5;
    int pageThumbnailIndexIn = data.$6;
    AppGlobals g = data.$7;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Delete old Thumbnail
    _deleteScaledThumbnail(
      sendPort,
      await g.filesHelper.getPagePath(docIndex, pageIndex),
    );

    /// 1. save rotated photo

    File rotatedPhotoFile = File(versionPaths[0]);
    Uint8List rotatedPhoto;
    if (rotatedPhotoFile.existsSync()) {
      rotatedPhoto = rotatedPhotoFile.readAsBytesSync();
    } else {
      throw StateError('rotated photo does not exist');
    }
    await g.filesHelper.savePageVersion(docIndex, pageIndex, 0, rotatedPhoto);

    /// 2. rotate processed -> save

    // Shape
    String? shapePath = await g.filesHelper.getPageShape(docIndex, pageIndex);
    if (shapePath.isEmpty && rotationIn != 0) {
      Uint8List rotatedShape = cvHelper.rotateImage(shapePath, rotationIn);
      shapePath = await g.filesHelper.savePageShape(
        docIndex,
        pageIndex,
        rotatedShape,
      );
    }

    // Warped
    Uint8List rotatedWarped = cvHelper.rotateImage(versionPaths[1], rotationIn);
    versionPaths[1] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      1,
      rotatedWarped,
    );

    // Processed1
    Uint8List rotatedP1 = cvHelper.rotateImage(versionPaths[2], rotationIn);
    versionPaths[2] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      2,
      rotatedP1,
    );

    // Processed2
    Uint8List rotatedP2 = cvHelper.rotateImage(versionPaths[3], rotationIn);
    versionPaths[3] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      3,
      rotatedP2,
    );

    // Updates
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);

    bool newThumbnail = await _scaleAndSaveThumbnail(
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

    sendPort.send('done');
  }

  Future<void> rotatePage(
    int docIndex,
    int pageIndex,
    List<String> versionPaths, //[0] is rotated
    int angle,
    int pageThumbnailIndexIn,
  ) async {
    ReceivePort port = ReceivePort();
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
      } else if (message == 'done') {
        port.close();
        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
    await rotatePageCompleter.future;
  }

  static Future<bool> _scaleAndSaveThumbnail(
    SendPort? sendPort,
    int docIndex,
    int pageIndex,
    int thumbnailIndex,
    AppGlobals gIn, {
    bool overwrite = true,
  }) async {
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
      dev.log("Error, writeScaledThumbnail: $versionPath does not exist");
      return false;
    } else {
      for (FileSystemEntity fse
          in Directory(pagePath).listSync()
            ..sort((a, b) => a.path.compareTo(b.path))) {
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
    }
    // Read
    img.Image? selectedVersion;
    try {
      Uint8List imageBytes = versionFile.readAsBytesSync();
      selectedVersion = img.decodeNamedImage(versionPath, imageBytes);
    } catch (e) {
      dev.log("Error, writeScaledThumbnail, decode: :$e");
    }
    if (selectedVersion == null) {
      throw StateError("selectedVersion used for thumbnail does not exist");
    }

    img.Image resized;
    try {
      // Resize
      resized = img.copyResize(
        selectedVersion,
        width:
            (screenWidth.toDouble() * 0.927083333)
                .toInt(), // thumbnail width in Pages Widget
        maintainAspect: true,
        interpolation: img.Interpolation.linear,
      );
    } catch (e) {
      dev.log("Error, writeScaledThumbnail, resize: :$e");
      throw StateError("$e");
    }

    try {
      // Save
      thumbnailFile.writeAsBytesSync(img.encodePng(resized));
    } catch (e) {
      dev.log("Error, writeScaledThumbnail, write: :$e");
    }

    try {
      // Update thumbnails:
      if (sendPort == null) {
        globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
        globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
      } else {
        sendPort.send(NotifierEvent.loadPagesThumbnails);
        sendPort.send(NotifierEvent.loadDocsThumbnails);
      }
    } catch (e) {
      dev.log("Error, writeScaledThumbnail, notify: :$e");
    }

    return true;
  }

  static Future<void> _deleteScaledThumbnail(
    SendPort? sendPort,
    String pagePath,
  ) async {
    for (FileSystemEntity fse
        in Directory(pagePath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.contains("thumbnail")) {
        String oldThumbnailPath = fse.path;
        await File(oldThumbnailPath).delete();
      }
    }
  }

  static Future<void> _saveNewThumbnailIsolate(
    (
      SendPort sendPort,
      int docIndex,
      int pageIndex,
      int thumbnailIndex,
      AppGlobals gIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    int docIndex = data.$2;
    int pageIndex = data.$3;
    int thumbnailIndex = data.$4;
    AppGlobals gIn = data.$5;

    await _scaleAndSaveThumbnail(
      sendPort,
      docIndex,
      pageIndex,
      thumbnailIndex,
      gIn,
    );
    sendPort.send('done');
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
    ReceivePort port = ReceivePort();

    while (taskKillers.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    TaskKiller killer;
    if (isNewIndex) {
      killer = await IsolatesManager().runTask(_saveNewThumbnailIsolate, (
        port.sendPort,
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
      } else if (message == 'done') {
        port.close();
        taskKillers.removeWhere((key, value) => value == killer);
        killer.kill();
      }
    });
  }
}
