// function:
import 'dart:developer' as dev;
import 'dart:isolate';
import 'package:docscanner/metadata_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
// my packages:
import 'package:docscanner/main.dart';
import 'package:docscanner/opencv_helper.dart';
import 'package:docscanner/files_helper.dart';

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
      FilesHelper filesHelperIn,
      bool isPrimary,
      int docIndex,
      int pageIndex,
      String newPicturePath,
      int? ratioIndexIn,
      int? orientationIndexIn,
      int? pageThumbnailIndex,
      List<List<int>>? cornerPointsIn,
      bool? proUnlockedIn,
      int rotationIn,
      bool isInitial,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    bool isPrimary = data.$3;
    int docIndex = data.$4;
    int pageIndex = data.$5;
    String newPicturePath = data.$6;

    int? ratioIndexIn = data.$7;
    int? orientationIndexIn = data.$8;
    int? pageThumbnailIndexIn = data.$9;
    List<List<int>>? cornerPointsIn = data.$10;
    bool? proUnlockedIn = data.$11;
    int rotationIn = data.$12;
    bool isInitial = data.$13;
    if (pageThumbnailIndexIn == 0) {
      throw StateError('thumbnail cant be the picture');
    }

    OpenCVHelper cvHelper = OpenCVHelper();
    List<String> versionPaths = List.generate(4, (index) => "");

    // Original
    versionPaths[0] = newPicturePath;
    // Re-use Shape
    String shapePath = await filesHelperIn.getPageShape(
      docIndex,
      pageIndex,
      supresswarning: isInitial,
    );
    if (shapePath.isNotEmpty && rotationIn != 0) {
      Uint8List rotatedShape = cvHelper.rotateImage(shapePath, rotationIn);
      shapePath = await filesHelperIn.savePageShape(
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
        inRatioIndex: ratioIndexIn,
        orientation: orientationIndexIn,
        cornerPoints: cornerPointsIn,
      ),
    );
    Uint8List warped = warpedRet.$1;
    Uint8List shape = warpedRet.$2;
    if (shapePath.isEmpty) {
      filesHelperIn.savePageShape(docIndex, pageIndex, shape);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    // Metadata
    int ratioIndex = warpedRet.$4;
    int orientationIndex = warpedRet.$5;
    List<List<int>> cornerPoints = warpedRet.$6;
    await MetadataHelper.writePageMetadata(
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIndex,
      (proUnlockedIn == true) ? 3 : 2,
      cornerPoints,
      filesHelperIn: filesHelperIn,
    );
    if (isPrimary) sendPort.send(NotifierEvent.loadPageMetadata);

    versionPaths[1] = await filesHelperIn.savePageVersion(
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
    versionPaths[2] = await filesHelperIn.savePageVersion(
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
    versionPaths[3] = await filesHelperIn.savePageVersion(
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
      versionPaths[pageThumbnailIndexIn ?? ((proUnlockedIn == true) ? 3 : 2)],
      filesHelperIn.screenWidth,
      overwrite: true,
    );

    sendPort.send('done');
  }

  Future<void> processPageWrapper(
    bool isPrimary,
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
    int? orientationIndexIn,
    int? pageThumbnailIndex,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
    bool isInitial, {
    Future<dynamic>? awaitBeforeIsolate,
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
    String newPhotoPath = await filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      0,
      picture,
      null,
    );

    final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;
    ReceivePort port = ReceivePort();
    await awaitBeforeIsolate;
    Isolate isolate = await Isolate.spawn(_processPageIsolate, (
      port.sendPort,
      filesHelper,
      isPrimary,
      docIndex,
      pageIndex,
      newPhotoPath,
      ratioIndexIn,
      orientationIndexIn,
      pageThumbnailIndex,
      cornerPointsIn,
      proUnlocked,
      rotationIn,
      isInitial,
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
        capabilities.removeAt(index);

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
      FilesHelper filesHelperIn,
      int docIndex,
      int pageIndex,
      int? ratioIndexIn,
      int? orientationIndexIn,
      int? pageThumbnailIndex,
      List<List<int>>? cornerPointsIn,
      bool? proUnlockedIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;

    int? ratioIndexIn = data.$5;
    int? orientationIndexIn = data.$6;
    int? pageThumbnailIndexIn = data.$7;
    List<List<int>>? cornerPointsIn = data.$8;
    bool? proUnlockedIn = data.$9;

    if (pageThumbnailIndexIn == 0) {
      throw StateError('thumbnail cant be the picture');
    }

    OpenCVHelper cvHelper = OpenCVHelper();

    // Original
    var imagePaths = await filesHelperIn.getImagePathsForPage(
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
        inRatioIndex: ratioIndexIn,
        orientation: orientationIndexIn,
        cornerPoints: cornerPointsIn,
        onlyCalculateBorder: versionPaths[1].isNotEmpty,
      ),
    );
    Uint8List warped = warpedRet.$1;
    Uint8List shape = warpedRet.$2;
    if (shapePath.isEmpty) {
      filesHelperIn.savePageShape(docIndex, pageIndex, shape);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    // Metadata
    int ratioIndex = warpedRet.$4;
    int orientationIndex = warpedRet.$5;
    List<List<int>> cornerPoints = warpedRet.$6;
    await MetadataHelper.writePageMetadata(
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIndex,
      (proUnlockedIn == true) ? 3 : 2,
      cornerPoints,
      filesHelperIn: filesHelperIn,
    );

    if (versionPaths[1].isEmpty) {
      versionPaths[1] = await filesHelperIn.savePageVersion(
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
      versionPaths[2] = await filesHelperIn.savePageVersion(
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
      versionPaths[3] = await filesHelperIn.savePageVersion(
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
        versionPaths[pageThumbnailIndexIn ?? ((proUnlockedIn == true) ? 3 : 2)],
        filesHelperIn.screenWidth,
        overwrite: true,
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
    Future<void> primaryFuture = processPageWrapper(
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

    List<Future<dynamic>> beforeSecundary = [];
    beforeSecundary.add(Future.delayed(Duration(seconds: 10)));
    beforeSecundary.add(primaryFuture);

    // Remaining pages
    pathsIn.removeAt(0);
    if (pathsIn.isNotEmpty) {
      final int maxIsolates = Platform.numberOfProcessors >= 4 ? 3 : 2;

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
          awaitBeforeIsolate: Future.any(beforeSecundary),
        );
        // just a small delay
        if (isolates.length >= maxIsolates) {
          await Future.delayed(Duration(milliseconds: 500));
        } else {
          await Future.delayed(Duration(milliseconds: 50));
        }
      }
    }
  }

  Future<void> reprocessPage(
    int docIndex,
    int pageIndex,
    String pathIn,
    int? ratioIndexIn,
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
      ratioIndexIn,
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
    var metadata = await metadataHelper.readPageMetadata(docIndex, pageIndex);
    int? ratioIndex = metadata.$1;
    int? orientationIndex = metadata.$2;
    int? thumbnailIndex = metadata.$3;
    List<List<int>>? cornerPoints = metadata.$4;

    Isolate isolate = await Isolate.spawn(_repairPageIsolate, (
      port.sendPort,
      filesHelper,
      docIndex,
      pageIndex,
      ratioIndex,
      orientationIndex,
      thumbnailIndex,
      cornerPoints,
      proUnlocked,
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
        capabilities.removeAt(index);

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
      FilesHelper filesHelperIn,
      int docIndex,
      int pageIndex,
      List<String> versionPaths, //[0] is potentially rotated
      int rotationIn,
      int pageThumbnailIndexIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;
    List<String> versionPaths = data.$5;
    int rotationIn = data.$6;
    int pageThumbnailIndexIn = data.$7;

    OpenCVHelper cvHelper = OpenCVHelper();

    /// 1. save rotated picture

    File rotatedPictureFile = File(versionPaths[0]);
    Uint8List rotatedPicture;
    if (rotatedPictureFile.existsSync()) {
      rotatedPicture = rotatedPictureFile.readAsBytesSync();
    } else {
      throw StateError('rotated picture does not exist');
    }
    await filesHelperIn.savePageVersion(
      docIndex,
      pageIndex,
      0,
      rotatedPicture,
      sendPort,
    );

    /// 2. rotate processed -> save

    // Shape
    String? shapePath = await filesHelperIn.getPageShape(docIndex, pageIndex);
    if (shapePath.isEmpty && rotationIn != 0) {
      Uint8List rotatedShape = cvHelper.rotateImage(shapePath, rotationIn);
      shapePath = await filesHelperIn.savePageShape(
        docIndex,
        pageIndex,
        rotatedShape,
      );
    }

    // Warped
    Uint8List rotatedWarped = cvHelper.rotateImage(versionPaths[1], rotationIn);
    versionPaths[1] = await filesHelperIn.savePageVersion(
      docIndex,
      pageIndex,
      1,
      rotatedWarped,
      sendPort,
    );

    // Processed1
    Uint8List rotatedP1 = cvHelper.rotateImage(versionPaths[2], rotationIn);
    versionPaths[2] = await filesHelperIn.savePageVersion(
      docIndex,
      pageIndex,
      2,
      rotatedP1,
      sendPort,
    );

    // Processed2
    Uint8List rotatedP2 = cvHelper.rotateImage(versionPaths[3], rotationIn);
    versionPaths[3] = await filesHelperIn.savePageVersion(
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
      filesHelperIn.screenWidth,
      overwrite: true,
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
      filesHelper,
      docIndex,
      pageIndex,
      versionPaths,
      angle,
      pageThumbnailIndexIn,
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
        capabilities.removeAt(index);

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
    bool overwrite = false,
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
      FilesHelper filesHelperIn,
      int docIndex,
      int pageIndex,
      int thumbnailIndex,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;
    int thumbnailIndex = data.$5;

    var imagePaths = await filesHelperIn.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    List<String> versionPaths = imagePaths.$1;
    await _saveScaledThumbnail(
      sendPort,
      versionPaths[thumbnailIndex],
      filesHelperIn.screenWidth,
      overwrite: true,
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
    Isolate isolate = await Isolate.spawn(_applyThumbnailIsolate, (
      port.sendPort,
      filesHelper,
      docIndex,
      pageIndex,
      thumbnailIndex,
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
        capabilities.removeAt(index);

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
