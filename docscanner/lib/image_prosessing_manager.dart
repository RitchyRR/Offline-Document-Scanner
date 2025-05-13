// function:
import 'dart:developer' as dev;
import 'dart:isolate';
import 'package:docscanner/app_globals.dart';
import 'package:docscanner/metadata_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
// my packages:
import 'package:docscanner/opencv_helper.dart';
import 'package:docscanner/main.dart' show globalNotifier;

const List<String> versionNames = [
  "picture",
  "warped",
  "processed1",
  "processed2",
];

class ImageProcessingManager {
  Map<(int, int), Isolate> isolates = {};

  static Future<void> _processPageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      bool isPrimary,
      int docIndex,
      int pageIndex,
      String newPicturePath,
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
    bool isPrimary = data.$3;
    int docIndex = data.$4;
    int pageIndex = data.$5;
    String newPicturePath = data.$6;

    double? ratioValueIn = data.$7;
    int? orientationIndexIn = data.$8;
    int? pageThumbnailIndexIn = data.$9;
    List<List<int>>? cornerPointsIn = data.$10;
    int rotationIn = data.$11;
    bool isInitial = data.$12;
    if (pageThumbnailIndexIn == 0) {
      throw StateError('thumbnail cant be the picture');
    }
    AppGlobals g = data.$13;
    int thumbnailIndex =
        pageThumbnailIndexIn ?? ((g.proUnlocked == true) ? 3 : 2);

    List<String> versionPaths = List.generate(4, (index) => "");
    OpenCVHelper cvHelper = OpenCVHelper(g);

    // Delete old Thumbnail
    _deleteScaledThumbnail(sendPort, p.dirname(newPicturePath));
    // Original
    versionPaths[0] = newPicturePath;
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

    // Warped
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
    if (isPrimary) sendPort.send(NotifierEvent.loadPageMetadata);

    versionPaths[1] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      1,
      warped,
      isPrimary ? sendPort : null,
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
      isPrimary ? sendPort : null,
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
      isPrimary ? sendPort : null,
    );

    // Update thumbnails:
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);

    bool newThumbnail = await _scaleAndSaveThumbnail(
      sendPort,
      docIndex,
      pageIndex,
      thumbnailIndex,
      g,
      overwrite: !isPrimary,
    );

    if (newThumbnail) {
      await MetadataHelper.writePageThumbnailIndex(
        docIndex,
        pageIndex,
        thumbnailIndex,
        gIn: g,
      );
    }

    sendPort.send('done');
  }

  Future<void> processPageWrapper(
    bool isPrimary,
    int docIndex,
    int pageIndex,
    String pathIn,
    double? ratioValueIn,
    int? orientationIndexIn,
    int? pageThumbnailIndex,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
    bool isInitial,
  ) async {
    if (pathIn.isEmpty) return;
    final wrapperCompleter = Completer<void>();

    // Save Photo
    File pictureFile = File(pathIn);
    Uint8List picture;
    if (pictureFile.existsSync()) {
      picture = pictureFile.readAsBytesSync();
    } else {
      throw StateError('picture does not exist');
    }
    String newPhotoPath = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      0,
      picture,
      null,
    );

    final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
    ReceivePort port = ReceivePort();

    while (isolates.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 95));
    }

    RootIsolateToken token = RootIsolateToken.instance!;
    Isolate isolate = await Isolate.spawn(_processPageIsolate, (
      port.sendPort,
      token,
      isPrimary,
      docIndex,
      pageIndex,
      newPhotoPath,
      ratioValueIn,
      orientationIndexIn,
      pageThumbnailIndex,
      cornerPointsIn,
      rotationIn,
      isInitial,
      g,
    ));
    isolates[(docIndex, pageIndex)] = isolate;

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        wrapperCompleter.complete();

        isolates.removeWhere((key, value) => value == isolate);
        isolate.kill();
      }
    });
    await wrapperCompleter.future;
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
        null,
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
        null,
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
        null,
      );
    }

    // Update thumbnails:
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    sendPort.send(NotifierEvent.loadDocsThumbnails);

    if (thumbnailPath.isEmpty) {
      int thumbnailIndex = ((g.proUnlocked == true) ? 3 : 2);
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
    if (isolates.containsKey(key)) {
      (isolates[key]!).kill(priority: Isolate.immediate);
      isolates.remove(key);
    }
  }

  Future<void> killIsolatesOfDocument(int docIndex) async {
    List<(int, int)> secundaryKeys = [];
    for (var key in isolates.keys) {
      if (key.$1 == docIndex) {
        secundaryKeys.add(key);
      }
    }
    for (var key in secundaryKeys) {
      (isolates[key]!).kill(priority: Isolate.immediate);
      isolates.remove(key);
    }
  }

  Future<void> awaitIsolatesOfHigherIndexedDocuments(int docIndex) async {
    while (isolates.isNotEmpty) {
      final otherKeys =
          isolates.keys.where((key) => key.$1 > docIndex).toList();
      final otherIsolates = otherKeys.map((key) => isolates[key]!).toList();

      if (otherIsolates.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexedPages(
    int docIndex,
    int pageIndex,
  ) async {
    while (isolates.isNotEmpty) {
      final otherKeys =
          isolates.keys
              .where((key) => key.$1 == docIndex && key.$2 > pageIndex)
              .toList();
      final otherIsolates = otherKeys.map((key) => isolates[key]!).toList();

      if (otherIsolates.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitAllIsolatesOfDocument(int docIndex) async {
    while (isolates.isNotEmpty) {
      final docKeys = isolates.keys.where((key) => key.$1 == docIndex).toList();
      final docIsolates = docKeys.map((key) => isolates[key]!).toList();

      if (docIsolates.isEmpty) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitAllIsolates() async {
    while (isolates.isNotEmpty) {
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> processPages(
    int docIndex,
    int firstPageIndex,
    List<String> pathsIn,
  ) async {
    if (pathsIn.isEmpty) return;

    // First page is opened in PagePreview -> more NotifierEvents
    processPageWrapper(
      true,
      docIndex,
      firstPageIndex,
      pathsIn[0],
      null,
      null,
      null,
      null,
      0,
      true,
    );

    // Remaining pages
    pathsIn.removeAt(0);
    if (pathsIn.isNotEmpty) {
      for (var (index, path) in pathsIn.indexed) {
        processPageWrapper(
          false,
          docIndex,
          firstPageIndex + 1 + index,
          path,
          null,
          null,
          null,
          null,
          0,
          true,
        );
        // small delay between starts
        await Future.delayed(Duration(milliseconds: 20));
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
    processPageWrapper(
      true,
      docIndex,
      pageIndex,
      pathIn,
      ratioValueIn,
      orientationIn,
      pageThumbnailIndex,
      cornerPointsIn,
      rotationIn,
      false,
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

    while (isolates.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    RootIsolateToken token = RootIsolateToken.instance!;
    Isolate isolate = await Isolate.spawn(_repairPageIsolate, (
      port.sendPort,
      token,
      docIndex,
      pageIndex,
      ratioValue,
      orientationIndex,
      cornerPoints,
      g,
    ));
    isolates[(docIndex, pageIndex)] = isolate;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        repairCompleter.complete();

        isolates.removeWhere((key, value) => value == isolate);
        isolate.kill();
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

    /// 1. save rotated picture

    File rotatedPictureFile = File(versionPaths[0]);
    Uint8List rotatedPicture;
    if (rotatedPictureFile.existsSync()) {
      rotatedPicture = rotatedPictureFile.readAsBytesSync();
    } else {
      throw StateError('rotated picture does not exist');
    }
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      0,
      rotatedPicture,
      sendPort,
    );

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
      sendPort,
    );

    // Processed1
    Uint8List rotatedP1 = cvHelper.rotateImage(versionPaths[2], rotationIn);
    versionPaths[2] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      2,
      rotatedP1,
      sendPort,
    );

    // Processed2
    Uint8List rotatedP2 = cvHelper.rotateImage(versionPaths[3], rotationIn);
    versionPaths[3] = await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      3,
      rotatedP2,
      sendPort,
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
    final primaryCompleter = Completer<void>();

    Isolate isolate = await Isolate.spawn(_rotatePageIsolate, (
      port.sendPort,
      docIndex,
      pageIndex,
      versionPaths,
      angle,
      pageThumbnailIndexIn,
      g,
    ));
    isolates[(docIndex, pageIndex)] = isolate;

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        isolates.removeWhere((key, value) => value == isolate);
      }
    });
    await primaryCompleter.future;
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
    String pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    String versionPath = await gIn.filesHelper.getVersionPath(
      docIndex,
      pageIndex,
      thumbnailIndex,
    );
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
    Uint8List imageBytes = await versionFile.readAsBytes();
    img.Image? selectedVersion = img.decodeImage(imageBytes);
    if (selectedVersion == null) {
      throw StateError("selectedVersion used for thumbnail does not exist");
    }
    // Resize
    img.Image resized = img.copyResize(
      selectedVersion,
      width:
          (screenWidth.toDouble() * 0.927083333)
              .toInt(), // thumbnail width in Pages Widget
      maintainAspect: true,
      interpolation: img.Interpolation.linear,
    );

    // Save
    thumbnailFile.writeAsBytesSync(img.encodePng(resized));

    // Update thumbnails:
    if (sendPort == null) {
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
      globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
    } else {
      sendPort.send(NotifierEvent.loadPagesThumbnails);
      sendPort.send(NotifierEvent.loadDocsThumbnails);
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

    while (isolates.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    Isolate isolate;
    if (isNewIndex) {
      isolate = await Isolate.spawn(_saveNewThumbnailIsolate, (
        port.sendPort,
        docIndex,
        pageIndex,
        thumbnailIndex,
        g,
      ));
    } else {
      port.close();
      return;
    }
    isolates[(docIndex, pageIndex)] = isolate;

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        isolates.removeWhere((key, value) => value == isolate);
      }
    });
  }
}
