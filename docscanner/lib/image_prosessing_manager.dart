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
  List<Capability?> capabilities = [];

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

    List<String> versionPaths = List.generate(4, (index) => "");
    OpenCVHelper cvHelper = OpenCVHelper(g);

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
    await MetadataHelper.writePageMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      orientationIndex,
      (g.proUnlocked == true) ? 3 : 2,
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

    await _saveScaledThumbnail(
      sendPort,
      versionPaths[pageThumbnailIndexIn ?? ((g.proUnlocked == true) ? 3 : 2)],
      g.filesHelper.screenWidth,
      overwrite: !isPrimary,
    );

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
    bool isInitial, {
    Future<dynamic>? priorFuture,
  }) async {
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

    // await prior future if too many isolates are running
    if (priorFuture != null) {
      bool isPriorDone = false;
      priorFuture.then((_) => isPriorDone = true);
      while (!isPriorDone && isolates.length >= maxIsolates) {
        await Future.delayed(Duration(milliseconds: 95));
      }
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

    Capability? cap;
    if (isolates.length + 1 >= maxIsolates) {
      cap = Capability();
      isolate.pause(cap);
    }
    isolates[(docIndex, pageIndex)] = isolate;
    capabilities.add(cap);

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        wrapperCompleter.complete();

        int index = isolates.values.toList().indexOf(isolate);
        isolates.removeWhere((key, value) => value == isolate);
        if (index != -1) capabilities.removeAt(index);
        isolate.kill();

        // Resume next paused isolate
        for (int i = 0; i < isolates.length; i++) {
          if (capabilities[i] != null) {
            isolates.values.elementAt(i).resume(capabilities[i]!);
            capabilities[i] = null;
            break;
          }
        }
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
      int? pageThumbnailIndex,
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
    int? pageThumbnailIndexIn = data.$7;
    List<List<int>>? cornerPointsIn = data.$8;
    AppGlobals g = data.$9;

    if (pageThumbnailIndexIn == 0) {
      throw StateError('thumbnail cant be the picture');
    }

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
    await MetadataHelper.writePageMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      orientationIndex,
      (g.proUnlocked == true) ? 3 : 2,
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
      await _saveScaledThumbnail(
        sendPort,
        versionPaths[pageThumbnailIndexIn ?? ((g.proUnlocked == true) ? 3 : 2)],
        g.filesHelper.screenWidth,
      );
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
    Future primaryFuture = processPageWrapper(
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

    Future priorFuture = primaryFuture;

    // Remaining pages
    pathsIn.removeAt(0);
    if (pathsIn.isNotEmpty) {
      for (var (index, path) in pathsIn.indexed) {
        Future newFuture = processPageWrapper(
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
          priorFuture: priorFuture,
        );
        priorFuture = newFuture;
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
    var metadata = await g.metadataHelper.readPageMetadata(docIndex, pageIndex);
    double? ratioValue = metadata.$1;
    int? orientationIndex = metadata.$2;
    int? thumbnailIndex = metadata.$3;
    List<List<int>>? cornerPoints = metadata.$4;

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
      thumbnailIndex,
      cornerPoints,
      g,
    ));

    Capability? cap;
    if (isolates.length + 1 >= maxIsolates) {
      cap = Capability();
      isolate.pause(cap);
    }
    isolates[(docIndex, pageIndex)] = isolate;
    capabilities.add(cap);

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();
        repairCompleter.complete();

        int index = isolates.values.toList().indexOf(isolate);
        isolates.removeWhere((key, value) => value == isolate);
        if (index != -1) capabilities.removeAt(index);
        isolate.kill();

        // Resume next paused isolate
        for (int i = 0; i < isolates.length; i++) {
          if (capabilities[i] != null) {
            isolates.values.elementAt(i).resume(capabilities[i]!);
            capabilities[i] = null;
            break;
          }
        }
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

    await _saveScaledThumbnail(
      sendPort,
      versionPaths[pageThumbnailIndexIn],
      g.filesHelper.screenWidth,
    );

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

    Isolate primaryIsolate = await Isolate.spawn(_rotatePageIsolate, (
      port.sendPort,
      docIndex,
      pageIndex,
      versionPaths,
      angle,
      pageThumbnailIndexIn,
      g,
    ));
    isolates[(docIndex, pageIndex)] = primaryIsolate;
    capabilities.add(null);

    port.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();

        int index = isolates.values.toList().indexOf(primaryIsolate);
        isolates.removeWhere((key, value) => value == primaryIsolate);
        if (index != -1) capabilities.removeAt(index);

        // Resume next paused isolate
        for (int i = 0; i < isolates.length; i++) {
          if (capabilities[i] != null) {
            isolates.values.elementAt(i).resume(capabilities[i]!);
            capabilities[i] = null;
            break;
          }
        }
      }
    });
    await primaryCompleter.future;
  }

  static Future<void> _saveScaledThumbnail(
    SendPort? sendPort,
    String pathIn,
    int screenWidth, {
    bool overwrite = true,
  }) async {
    String pagePath = p.dirname(pathIn);
    String pathOut =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_thumbnail.png";
    File fileIn = File(pathIn);
    File fileOut = File(pathOut);

    if (!fileIn.existsSync()) {
      dev.log("Error, writeScaledThumbnail: $pathIn does not exist");
      return;
    } else {
      for (FileSystemEntity fse in Directory(pagePath).listSync()) {
        if (fse.path.contains("thumbnail")) {
          String oldThumbnailPath = fse.path;
          if (overwrite) {
            //dev.log("Overwriting, writeScaledThumbnail: $pathIn");
            File(oldThumbnailPath).deleteSync();
          } else {
            dev.log("Thumbnail already exists, won't overwrite thumbnail.");
            return;
          }
        }
      }
    }
    // Read
    Uint8List imageBytes = await fileIn.readAsBytes();
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
    fileOut.writeAsBytesSync(img.encodePng(resized));

    // Update thumbnails:
    if (sendPort == null) {
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
      globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
    } else {
      sendPort.send(NotifierEvent.loadPagesThumbnails);
      sendPort.send(NotifierEvent.loadDocsThumbnails);
    }
  }

  static Future<void> _applyThumbnailIsolate(
    (
      SendPort sendPort,
      int docIndex,
      int pageIndex,
      int thumbnailIndex,
      AppGlobals g,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    int docIndex = data.$2;
    int pageIndex = data.$3;
    int thumbnailIndex = data.$4;
    AppGlobals g = data.$5;

    var imagePaths = await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    List<String> versionPaths = imagePaths.$1;
    await _saveScaledThumbnail(
      sendPort,
      versionPaths[thumbnailIndex],
      g.filesHelper.screenWidth,
    );
    sendPort.send('done');
  }

  Future<void> applyThumbnail(
    int docIndex,
    int pageIndex,
    int thumbnailIndex,
  ) async {
    final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
    ReceivePort port = ReceivePort();

    while (isolates.length >= maxIsolates) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    Isolate isolate = await Isolate.spawn(_applyThumbnailIsolate, (
      port.sendPort,
      docIndex,
      pageIndex,
      thumbnailIndex,
      g,
    ));

    Capability? cap;
    if (isolates.length + 1 >= maxIsolates) {
      cap = Capability();
      isolate.pause(cap);
    }
    isolates[(docIndex, pageIndex)] = isolate;
    capabilities.add(cap);

    port.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        port.close();

        int index = isolates.values.toList().indexOf(isolate);
        isolates.removeWhere((key, value) => value == isolate);
        if (index != -1) capabilities.removeAt(index);

        // Resume next paused isolate
        for (int i = 0; i < isolates.length; i++) {
          if (capabilities[i] != null) {
            isolates.values.elementAt(i).resume(capabilities[i]!);
            capabilities[i] = null;
            break;
          }
        }
      }
    });
  }
}
