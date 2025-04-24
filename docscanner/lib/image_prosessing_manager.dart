// function:
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:isolate';
import 'package:docscanner/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
// my packages:
import 'opencv_helper.dart';
import 'package:docscanner/files_helper.dart';

const List<String> versionNames = [
  "picture",
  "warped",
  "processed1",
  "processed2",
];

class ImageProcessingManager {
  Map<(int, int), Isolate> primaryIsolates = {};
  Map<(int, int), Isolate> secundaryIsolates = {};
  List<Completer> comleters = [];

  static Future<void> _processPageIsolate(
    (
      SendPort sendPort,
      FilesHelper filesHelperIn,
      bool isPrimary,
      int docIndex,
      int pageIndex,
      String pathIn,
      int? ratioIndexIn,
      int? orientationIndexIn,
      int? pageThumbnailIndex,
      List<List<int>>? cornerPointsIn,
      bool? proUnlockedIn,
      int rotationIn,
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
    int? orientationIndexIn = data.$8;
    int? pageThumbnailIndexIn = data.$9;
    List<List<int>>? cornerPointsIn = data.$10;
    bool? proUnlockedIn = data.$11;
    int rotationIn = data.$12;
    if (pageThumbnailIndexIn == 0) {
      throw StateError('thumbnail cant be the picture');
    }

    OpenCVHelper cvHelper = OpenCVHelper();
    List<String> versionPaths = List.generate(4, (index) => "");

    // Original
    File pictureFile = File(pathIn);
    Uint8List picture;
    if (pictureFile.existsSync()) {
      picture = pictureFile.readAsBytesSync();
    } else {
      throw StateError('picture does not exist');
    }
    versionPaths[0] = await filesHelperIn.savePageVersion(
      docIndex,
      pageIndex,
      0,
      picture,
      isPrimary ? sendPort : null,
    );

    // Re-use Shape
    String? shapePath = await filesHelperIn.getPageShape(docIndex, pageIndex);
    if (shapePath != null && rotationIn != 0) {
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
    if (shapePath == null) {
      filesHelperIn.savePageShape(docIndex, pageIndex, shape);
    }
    List<int> borderCorrectionDepth = warpedRet.$3;
    // Metadata
    int ratioIndex = warpedRet.$4;
    int orientationIndex = warpedRet.$5;
    List<List<int>> cornerPoints = warpedRet.$6;
    await writePageMetadata(
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
    if (secundaryIsolates.containsKey(key)) {
      (secundaryIsolates[key]!).kill(priority: Isolate.immediate);
      secundaryIsolates.remove(key);
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
    for (var key in secundaryIsolates.keys) {
      if (key.$1 == docIndex) {
        secundaryKeys.add(key);
      }
    }
    for (var key in secundaryKeys) {
      (secundaryIsolates[key]!).kill(priority: Isolate.immediate);
      secundaryIsolates.remove(key);
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
    Isolate primaryIsolate = await Isolate.spawn(_processPageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      true,
      docIndex,
      firstPageIndex,
      pathsIn[0],
      null,
      null,
      null,
      null,
      proUnlocked,
      0,
    ));
    primaryIsolates[(docIndex, firstPageIndex)] = primaryIsolate;
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
        primaryCompleter.complete();
        comleters.remove(primaryCompleter);
        //primaryIsolate.kill();
        primaryIsolates.removeWhere((key, value) => value == primaryIsolate);
      } else if (message is File) {
        imageCache.evict(FileImage(message), includeLive: true);
        globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
        globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
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

        ReceivePort secundaryPort = ReceivePort();
        final completer = Completer<void>();
        comleters.add(completer);
        Isolate isolate = await Isolate.spawn(_processPageIsolate, (
          secundaryPort.sendPort,
          filesHelper,
          false,
          docIndex,
          firstPageIndex + 1 + index,
          path,
          null,
          null,
          null,
          null,
          proUnlocked,
          0,
        ));
        secundaryIsolates[(docIndex, firstPageIndex + 1 + index)] = isolate;
        secundaryPort.listen((message) {
          if (message is NotifierEvent) {
            globalNotifier.triggerEvent(message);
          } else if (message == 'done') {
            secundaryPort.close();
            completer.complete();
            comleters.remove(completer);
            //isolate.kill();
            secundaryIsolates.removeWhere((key, value) => value == isolate);
          } else if (message is File) {
            imageCache.evict(FileImage(message), includeLive: true);
            globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
            globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
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
    int? orientationIn,
    int? pageThumbnailIndex,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
  ) async {
    ReceivePort primaryPort = ReceivePort();
    final primaryCompleter = Completer<void>();
    comleters.add(primaryCompleter);
    Isolate primaryIsolate = await Isolate.spawn(_processPageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      true,
      docIndex,
      pageIndex,
      pathIn,
      ratioIndexIn,
      orientationIn,
      pageThumbnailIndex,
      cornerPointsIn,
      proUnlocked,
      rotationIn,
    ));
    primaryIsolates[(docIndex, pageIndex)] = primaryIsolate;
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
        primaryCompleter.complete();
        comleters.remove(primaryCompleter);
        //primaryIsolate.kill();
        primaryIsolates.removeWhere((key, value) => value == primaryIsolate);
      } else if (message is File) {
        imageCache.evict(FileImage(message), includeLive: true);
        globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
        globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
      }
    });
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
    if (shapePath != null && rotationIn != 0) {
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
    ReceivePort primaryPort = ReceivePort();
    final primaryCompleter = Completer<void>();
    comleters.add(primaryCompleter);
    Isolate primaryIsolate = await Isolate.spawn(_rotatePageIsolate, (
      primaryPort.sendPort,
      filesHelper,
      docIndex,
      pageIndex,
      versionPaths,
      angle,
      pageThumbnailIndexIn,
    ));
    primaryIsolates[(docIndex, pageIndex)] = primaryIsolate;
    primaryPort.listen((message) {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        primaryPort.close();
        primaryCompleter.complete();
        comleters.remove(primaryCompleter);
        //primaryIsolate.kill();
        primaryIsolates.removeWhere((key, value) => value == primaryIsolate);
      } else if (message is File) {
        imageCache.evict(FileImage(message), includeLive: true);
        globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
        globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
      }
    });
    await primaryCompleter.future;
  }

  static Future<void> writePageMetadata(
    int docIndex,
    int pageIndex,
    int? ratioIndex,
    int? orientationIndex,
    int? thumbnailIndex,
    List<List<int>>? cornerPoints, {
    FilesHelper? filesHelperIn,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Write
      if (ratioIndex != null) metadata["apectRatio"] = ratioIndex.toString();
      metadata["orientation"] =
          orientationIndex == 0 ? "portrait" : "landscape";
      metadata["thumbnail"] =
          versionNames[thumbnailIndex != null && thumbnailIndex != 0
              ? thumbnailIndex
              : ((proUnlocked == true) ? 3 : 2)];
      if (cornerPoints != null) metadata["corners"] = cornerPoints;
      await file.writeAsString(jsonEncode(metadata));
      if (filesHelperIn != null) {
        // if started outside of isolate
        globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
      }
    } catch (e) {
      dev.log("Error, writePageMetadata: $e");
    }
  }

  static Future<(int?, int?, int?, List<List<int>>?)> readPageMetadata(
    int docIndex,
    int pageIndex, {
    bool supressWarning = false,
  }) async {
    int? ratioIndex;
    int? orientationIndex;
    int? thumbnailIndex;
    List<List<int>>? cornerPoints;

    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
        ratioIndex = int.parse(metadata["apectRatio"]);
        String orientationString = metadata["orientation"];
        orientationIndex =
            (orientationString == "portrait" || orientationString == "")
                ? 0
                : 1;
        String? thumbnailString = metadata["thumbnail"];
        if (thumbnailString != null) {
          thumbnailIndex = versionNames.indexOf(thumbnailString);
          if (thumbnailIndex == 0) {
            throw StateError('metadata: thumbnail cant be the picture');
          }
          cornerPoints =
              (metadata["corners"] as List)
                  .map<List<int>>(
                    (e) => (e as List).map((v) => v as int).toList(),
                  )
                  .toList();
        }
        return (ratioIndex, orientationIndex, thumbnailIndex, cornerPoints);
      } catch (e) {
        dev.log("Error, readPageMetadata: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageMetadata: Metadata does not exist for $pagePath",
      );
    }
    return (ratioIndex, orientationIndex, thumbnailIndex, cornerPoints);
  }

  static Future<void> writePageThumbnailIndex(
    int docIndex,
    int pageIndex,
    int thumbnailIndex,
  ) async {
    bool updateThumbnail = false; // is new and not picture
    String newThumbnailName = versionNames[thumbnailIndex];
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Read
      if (await file.exists()) {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } else {
        dev.log(
          "Error, writePageThumbnailIndex: metadata File does not exist (Page $pageIndex, Document $docIndex)",
        );
        return;
      }
      if ((metadata["thumbnail"] != null
                  ? versionNames.indexOf(metadata["thumbnail"])
                  : ((proUnlocked == true) ? 3 : 2)) !=
              thumbnailIndex &&
          thumbnailIndex != 0) {
        updateThumbnail = true;
      }

      // Write
      if (updateThumbnail) {
        metadata["thumbnail"] = newThumbnailName;
        await file.writeAsString(jsonEncode(metadata));
      }
    } catch (e) {
      dev.log("Error, writePageThumbnailIndex: $e");
    }
    if (updateThumbnail) {
      imageProcessingManager.applySelectedThumbnail(docIndex, pageIndex);
    }
  }

  static Future<void> writePageCornerPoints(
    int docIndex,
    int pageIndex,
    List<List<int>> cornerPoints,
  ) async {
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Read
      if (await file.exists()) {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } else {
        dev.log(
          "Error, writePageCornerPoints: metadata File does not exist (Page $pageIndex, Document $docIndex)",
        );
      }

      // Write
      metadata["corners"] = cornerPoints;
      await file.writeAsString(jsonEncode(metadata));
      globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
    } catch (e) {
      dev.log("Error, writePageCornerPoints: $e");
    }
  }

  static Future<int?> readPageRatioIndex(
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
        dev.log("Error, readPageRatioIndex: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageRatioIndex: Metadata does not exist for $pagePath",
      );
    }
    return null;
  }

  static Future<int?> readPageOrientationIndex(
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
        dev.log("Error, readPageOrientationIndex: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageOrientationIndex: Metadata does not exist for $pagePath",
      );
    }
    return null;
  }

  static Future<int> readPageThumbnailIndex(
    int docIndex,
    int pageIndex, {
    FilesHelper? filesHelperIn,
    bool supressWarning = false,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        String? thumbnailString = metadata["thumbnail"];

        if (thumbnailString != null) {
          int? retInt = versionNames.indexOf(thumbnailString);
          if (retInt == 0) {
            throw StateError('metadata: thumbnail cant be the picture');
          } else {
            return retInt;
          }
        }
      } catch (e) {
        dev.log("Error, readPageThumbnailIndex: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageThumbnailIndex: Metadata does not exist for $pagePath",
      );
    }
    return (proUnlocked == true) ? 3 : 2;
  }

  static Future<List<List<int>>> readPageCornerPoints(
    int docIndex,
    int pageIndex, {
    FilesHelper? filesHelperIn,
    bool supressWarning = false,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
        List<List<int>> cornerPoints =
            (metadata["corners"] as List)
                .map<List<int>>(
                  (e) => (e as List).map((v) => v as int).toList(),
                )
                .toList();
        return cornerPoints;
      } catch (e) {
        dev.log("Error, readPageThumbnailIndex: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageThumbnailIndex: Metadata does not exist for $pagePath",
      );
    }
    return [];
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
      String? oldThumbnailPath;
      for (FileSystemEntity fse in Directory(pagePath).listSync()) {
        if (fse.path.contains("thumbnail")) {
          oldThumbnailPath = fse.path;
          break;
        }
      }
      if (oldThumbnailPath != null) {
        if (overwrite) {
          //dev.log("Overwriting, writeScaledThumbnail: $pathIn");
          File(oldThumbnailPath).deleteSync();
          if (sendPort != null) {
            sendPort.send(File(oldThumbnailPath));
          } else {
            imageCache.evict(
              FileImage(File(oldThumbnailPath)),
              includeLive: true,
            );
          }
        } else {
          dev.log("Thumbnail already exists, won't overwrite thumbnail.");
          return;
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

  static Future<void> _applySelectedThumbnailIsolate(
    (SendPort sendPort, FilesHelper filesHelperIn, int docIndex, int pageIndex)
    data,
  ) async {
    SendPort sendPort = data.$1;
    FilesHelper filesHelperIn = data.$2;
    int docIndex = data.$3;
    int pageIndex = data.$4;

    int? thumbnailIndex = await ImageProcessingManager.readPageThumbnailIndex(
      docIndex,
      pageIndex,
      filesHelperIn: filesHelperIn,
    );
    final versionsPaths = await filesHelperIn.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    await _saveScaledThumbnail(
      sendPort,
      versionsPaths[thumbnailIndex],
      filesHelperIn.screenWidth,
      overwrite: true,
    );
    sendPort.send('done');
  }

  Future<void> applySelectedThumbnail(int docIndex, int pageIndex) async {
    ReceivePort secundaryPort = ReceivePort();
    final secundaryCompleter = Completer<void>();
    comleters.add(secundaryCompleter);
    Isolate secundaryIsolate = await Isolate.spawn(
      _applySelectedThumbnailIsolate,
      (secundaryPort.sendPort, filesHelper, docIndex, pageIndex),
    );
    secundaryIsolates[(docIndex, pageIndex)] = secundaryIsolate;
    secundaryPort.listen((message) async {
      if (message is NotifierEvent) {
        globalNotifier.triggerEvent(message);
      } else if (message == 'done') {
        secundaryPort.close();
        secundaryCompleter.complete();
        comleters.remove(secundaryCompleter);
        //secundaryIsolate.kill();
        secundaryIsolates.removeWhere(
          (key, value) => value == secundaryIsolate,
        );
      } else if (message is File) {
        imageCache.evict(FileImage(message), includeLive: true);
        globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
        globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
      }
    });
  }
}
