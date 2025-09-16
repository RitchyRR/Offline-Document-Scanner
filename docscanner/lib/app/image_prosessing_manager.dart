import 'dart:developer' as dev;
import 'dart:math' as math;
import 'package:docscanner/app/files_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart'
    show FlutterImageCompress, CompressFormat;
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:image/image.dart' as img;
// isolates:
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'dart:isolate' show ReceivePort, SendPort, Isolate;
import 'package:docscanner/app/isolates_manager.dart';
// my packages:
import 'package:docscanner/main.dart' show globalNotifier;
import 'package:docscanner/app/metadata_helper.dart';
import 'package:docscanner/app/app_globals.dart';
// ffi:
import 'package:docscanner/ffi/opencv_bindings.dart' as cvb;

const List<String> versionNamesInternal = [
  "photo",
  "warped",
  "contrast",
  "processed1",
  "processed2",
  "processed3",
];

class ImageProcessingManager {
  List<((int, int), TaskKiller)> taskKillers = [];

  static void _processPageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      String photoPath,
      double? ratioValueIn,
      List<List<int>>? cornerPointsIn,
      bool isPhotoAlreadyInPage,
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
    String photoPath = data.$5;

    double? ratioValueIn = data.$6;
    List<List<int>>? cornerPointsIn = data.$7;
    bool isPhotoAlreadyInPage = data.$8;
    bool isInitial = data.$9;
    AppGlobals g = data.$10;

    List<Future<void>> futures = [];

    final int initialThumbnailIndex;

    //OpenCVHelper cvHelper = OpenCVHelper(g);
    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
    imageProcessor.setAvailableAspectRatios(g.availableAspectRatios);

    // Photo
    if (isPhotoAlreadyInPage) {
      imageProcessor.loadPhoto(photoPath);
    } else {
      await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 0);
      imageProcessor.importPhoto(
        photoPath,
        await g.filesHelper.createVersionPath(docIndex, pageIndex, 0),
      );
    }

    (
      initialThumbnailIndex,
      futures,
    ) = await _processPageIsolateThumbnailVersion(
      sendPort,
      docIndex,
      pageIndex,
      photoPath,
      ratioValueIn,
      cornerPointsIn,
      //rotationIn,
      isInitial,
      g,
      imageProcessor,
      futures,
    );

    futures = await _processPageIsolateFilters(
      sendPort,
      docIndex,
      pageIndex,
      initialThumbnailIndex,
      g,
      imageProcessor,
      futures,
    );

    await Future.wait(futures);
    imageProcessor.dispose();
    Isolate.exit(sendPort, "done");
  }

  static Future<(int, List<Future<void>>)> _processPageIsolateThumbnailVersion(
    SendPort sendPort,
    int docIndex,
    int pageIndex,
    String photoPath,
    double? ratioValueIn,
    List<List<int>>? cornerPointsIn,
    //int rotationIn,
    bool isInitial,
    AppGlobals g,
    final cvb.ImageProcessor imageProcessor,
    List<Future<void>> futures,
  ) async {
    // Control Port for exiting gracefully
    bool kill = false;
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    // Delete Thumbnail
    futures.add(_deleteThumbnailInIsolate(docIndex, pageIndex, g));

    await isolateExitPoint(kill, futures: futures);
    String pagePath = await g.filesHelper.getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: true,
    );
    if (!Directory(pagePath).existsSync()) {
      throw StateError(
        "Error, _processPageIsolateThumbnailVersion: pagePath $pagePath does not exist",
      );
    }

    // Warped
    double ratioValue;
    List<List<int>>? cornerPoints;
    await isolateExitPoint(kill, futures: futures);
    await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 1);
    await isolateExitPoint(kill, futures: futures);
    (ratioValue, cornerPoints) = imageProcessor.warpImage(
      await g.filesHelper.createVersionPath(docIndex, pageIndex, 1),
      ratioValueIn,
      cornerPointsIn,
    );

    // Metadata
    await isolateExitPoint(kill, futures: futures);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );

    // initialThumbnailIndex
    final int initialThumbnailIndex;
    await isolateExitPoint(kill, futures: futures);
    int? readThumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
      docIndex,
      pageIndex,
      gIn: g,
      supressWarnings: true,
    );
    if (readThumbnailIndex == null) {
      initialThumbnailIndex = g.defaultIndex;
      await isolateExitPoint(kill, futures: futures);
      futures.add(
        MetadataHelper.writePageThumbnailIndex(
          docIndex,
          pageIndex,
          initialThumbnailIndex,
          gIn: g,
          supressWarnings: true,
        ),
      );
    } else {
      initialThumbnailIndex = readThumbnailIndex;
    }

    // First process (default) Thumbnail version
    Future<void> processThumbnailVersion() async {
      if (initialThumbnailIndex > 1) {
        await isolateExitPoint(kill, futures: futures);
        g.filesHelper.deleteExistingVersion(
          docIndex,
          pageIndex,
          initialThumbnailIndex,
        );
        await isolateExitPoint(kill, futures: futures);
        switch (initialThumbnailIndex) {
          case 2:
            // Contrast
            await isolateExitPoint(kill, futures: futures);
            imageProcessor.contrastFilter(
              await g.filesHelper.createVersionPath(
                docIndex,
                pageIndex,
                initialThumbnailIndex,
              ),
            );
            break;
          case 3:
            // Document
            await isolateExitPoint(kill, futures: futures);
            imageProcessor.documentFilter(
              await g.filesHelper.createVersionPath(
                docIndex,
                pageIndex,
                initialThumbnailIndex,
              ),
            );
            break;
          case 4:
          case 5:
            await isolateExitPoint(kill, futures: futures);
            g.filesHelper.deleteExistingVersion(
              docIndex,
              pageIndex,
              initialThumbnailIndex == 4 ? 5 : 4,
            );
            // PRO
            await isolateExitPoint(kill, futures: futures);
            int filterIndex = versionNamesInternal.indexOf("processed2");
            imageProcessor.proFilter(
              await g.filesHelper.createVersionPath(
                docIndex,
                pageIndex,
                filterIndex,
              ),
            );
            // PRO 2
            await isolateExitPoint(kill, futures: futures);
            filterIndex = versionNamesInternal.indexOf("processed3");
            imageProcessor.proColorFilter(
              await g.filesHelper.createVersionPath(
                docIndex,
                pageIndex,
                filterIndex,
              ),
            );
            break;
          default:
        }
        await isolateExitPoint(kill, futures: futures);
      }
    }

    await processThumbnailVersion();

    futures.add(
      _compressVersion(docIndex, pageIndex, initialThumbnailIndex, gIn: g),
    );

    // Update thumbnails:
    await isolateExitPoint(kill, futures: futures);
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    return (initialThumbnailIndex, futures);
  }

  static Future<List<Future<void>>> _processPageIsolateFilters(
    SendPort sendPort,
    int docIndex,
    int pageIndex,
    int initialThumbnailIndex,
    AppGlobals g,
    final cvb.ImageProcessor imageProcessor,
    List<Future<void>> futures,
  ) async {
    // Control Port for exiting gracefully
    bool kill = false;
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    // Contrast
    await isolateExitPoint(kill, futures: futures);
    int filterIndex = versionNamesInternal.indexOf("contrast");
    if (initialThumbnailIndex != filterIndex) {
      g.filesHelper.deleteExistingVersion(docIndex, pageIndex, filterIndex);
      await isolateExitPoint(kill, futures: futures);
      imageProcessor.contrastFilter(
        await g.filesHelper.createVersionPath(docIndex, pageIndex, filterIndex),
      );
    }
    // Document
    await isolateExitPoint(kill, futures: futures);
    filterIndex = versionNamesInternal.indexOf("processed1");
    if (initialThumbnailIndex != filterIndex) {
      g.filesHelper.deleteExistingVersion(docIndex, pageIndex, filterIndex);
      await isolateExitPoint(kill, futures: futures);
      imageProcessor.documentFilter(
        await g.filesHelper.createVersionPath(docIndex, pageIndex, filterIndex),
      );
    }
    // PRO
    await isolateExitPoint(kill, futures: futures);
    filterIndex = versionNamesInternal.indexOf("processed2");
    if (initialThumbnailIndex != filterIndex &&
        initialThumbnailIndex != versionNamesInternal.indexOf("processed3")) {
      g.filesHelper.deleteExistingVersion(docIndex, pageIndex, filterIndex);
      await isolateExitPoint(kill, futures: futures);
      imageProcessor.proFilter(
        await g.filesHelper.createVersionPath(docIndex, pageIndex, filterIndex),
      );
      // PRO 2
      await isolateExitPoint(kill, futures: futures);
      filterIndex = versionNamesInternal.indexOf("processed3");
      g.filesHelper.deleteExistingVersion(docIndex, pageIndex, filterIndex);
      await isolateExitPoint(kill, futures: futures);
      imageProcessor.proColorFilter(
        await g.filesHelper.createVersionPath(docIndex, pageIndex, filterIndex),
      );
    }

    // Set New Thumbnail
    await isolateExitPoint(kill, futures: futures);
    await Future.wait(futures);
    await isolateExitPoint(kill, futures: futures);
    futures.add(
      _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, g),
    );

    return futures;
  }

  static Future<void> isolateExitPoint(
    final bool kill, {
    List<Future<void>> futures = const [],
  }) async {
    if (kill) {
      await Future.wait(futures);
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
    if (!isInitial) {
      await saveOldVersionFileNames(
        docIndex,
        pageIndex,
        isPhotoAlreadyInPage: isPhotoAlreadyInPage,
      );
    }

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
        isPhotoAlreadyInPage,
        isInitial,
        g,
      ),
      portIn: port,
      prio: prio,
      onErrorFunction: (error, stack) async {
        dev.log("_processPageIsolate, onErrorFunction: $error $stack");
        if (!error.toString().contains("No photo")) {
          repairPage(docIndex, pageIndex);
        } else {
          g.filesHelper.deleteImages(null, docIndex, pageIndexes: [pageIndex]);
        }
      },
    );
    taskKillers.add(((docIndex, pageIndex), killer));

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
        taskKillers.removeWhere((element) => element.$2 == killer);
        completer.complete();
      }
    });
    await completer.future;

    await _compressPage(docIndex, pageIndex);
  }

  Future<void> saveOldVersionFileNames(
    int docIndex,
    int pageIndex, {
    bool isPhotoAlreadyInPage = false,
  }) async {
    List<String> versionPaths;
    (versionPaths, _) = await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    List<String> fileNames = [];
    for (var (versionIndex, path) in versionPaths.indexed) {
      fileNames.add(
        path.isEmpty || isPhotoAlreadyInPage && versionIndex == 0
            ? ""
            : path.substring(path.lastIndexOf("/") + 1, path.lastIndexOf(".")),
      );
    }
    await MetadataHelper.writeOldVersionFileNames(
      docIndex,
      pageIndex,
      fileNames,
    );
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

    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();

    List<String>? oldVersionFileNames =
        await MetadataHelper.readOldPageFileNames(docIndex, pageIndex, gIn: g);

    String photoPath = await g.filesHelper.getVersionPath(
      docIndex,
      pageIndex,
      0,
      supressWarnings: true,
    );
    // Photo
    if (!File(photoPath).existsSync()) {
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

    await isolateExitPoint(kill);
    var imagePaths = await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    );
    final List<String> versionPaths = imagePaths.$1;
    String thumbnailPath = imagePaths.$2;

    bool versionOutdatedOrMissing(int versionIndex) {
      return versionPaths[versionIndex].isEmpty ||
          (oldVersionFileNames != null &&
              oldVersionFileNames[versionIndex].isNotEmpty &&
              versionPaths[versionIndex].contains(
                oldVersionFileNames[versionIndex],
              ));
    }

    await isolateExitPoint(kill);
    final photoFile = File(versionPaths[0]);
    if (!photoFile.existsSync() || photoFile.lengthSync() < 9) {
      throw StateError("Error, _repairPageIsolate: No photo");
    }
    imageProcessor.loadPhoto(versionPaths[0]);

    // Warped
    if (versionOutdatedOrMissing(1) ||
        (ratioValue == null || cornerPoints == null)) {
      await isolateExitPoint(kill);
      await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 1);
      await isolateExitPoint(kill);
      versionPaths[1] = await g.filesHelper.createVersionPath(
        docIndex,
        pageIndex,
        versionNamesInternal.indexOf("warped"),
      );
      await isolateExitPoint(kill);
      (ratioValue, cornerPoints) = imageProcessor.warpImage(
        versionPaths[1],
        ratioValue,
        cornerPoints,
      );
    } else {
      imageProcessor.loadWarped(versionPaths[1]);
    }

    // Metadata
    await isolateExitPoint(kill);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );

    // Contrast
    if (versionOutdatedOrMissing(2)) {
      await isolateExitPoint(kill);
      await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 2);
      await isolateExitPoint(kill);
      versionPaths[2] = await g.filesHelper.createVersionPath(
        docIndex,
        pageIndex,
        versionNamesInternal.indexOf("contrast"),
      );
      await isolateExitPoint(kill);
      imageProcessor.contrastFilter(versionPaths[2]);
    }

    // Document
    if (versionOutdatedOrMissing(3)) {
      await isolateExitPoint(kill);
      await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 3);
      await isolateExitPoint(kill);
      versionPaths[3] = await g.filesHelper.createVersionPath(
        docIndex,
        pageIndex,
        versionNamesInternal.indexOf("processed1"),
      );
      await isolateExitPoint(kill);
      imageProcessor.documentFilter(versionPaths[3]);
    }

    // PRO
    bool proLoaded = false;
    if (versionOutdatedOrMissing(4)) {
      await isolateExitPoint(kill);
      await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 4);
      await isolateExitPoint(kill);
      versionPaths[4] = await g.filesHelper.createVersionPath(
        docIndex,
        pageIndex,
        versionNamesInternal.indexOf("processed2"),
      );
      await isolateExitPoint(kill);
      imageProcessor.proFilter(versionPaths[4]);
      proLoaded = true;
    }

    // PRO 2
    if (versionOutdatedOrMissing(5)) {
      await isolateExitPoint(kill);
      if (!proLoaded) imageProcessor.loadPro(versionPaths[4]);
      await isolateExitPoint(kill);
      await g.filesHelper.deleteExistingVersion(docIndex, pageIndex, 5);
      await isolateExitPoint(kill);
      versionPaths[5] = await g.filesHelper.createVersionPath(
        docIndex,
        pageIndex,
        versionNamesInternal.indexOf("processed3"),
      );
      await isolateExitPoint(kill);
      imageProcessor.proColorFilter(versionPaths[5]);
    }

    imageProcessor.dispose();

    // Update thumbnails:
    await isolateExitPoint(kill);
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    // Set New Thumbnail
    if (thumbnailPath.isEmpty) {
      await isolateExitPoint(kill);
      await _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, g);
    }

    Isolate.exit(sendPort, "done");
  }

  Future<void> killIsolatesOfPage(int docIndex, int pageIndex) async {
    if (taskKillers.isEmpty) return;
    var key = (docIndex, pageIndex);
    final limited = taskKillers.where((element) => element.$1 == key).toList();
    for (var taskKiller in limited) {
      taskKiller.$2.kill();
    }
    await awaitIsolatesOfPage(docIndex, pageIndex);
  }

  void changePrioForIsolatesOfPage(
    int docIndex,
    int pageIndex,
    IsolatePriority newPrio,
  ) {
    if (taskKillers.isEmpty) return;
    var key = (docIndex, pageIndex);
    final limited = taskKillers.where((element) => element.$1 == key);
    for (var taskKiller in limited) {
      taskKiller.$2.changePrio(newPrio);
    }
  }

  Future<void> killIsolatesOfDocument(int docIndex) async {
    if (taskKillers.isEmpty) return;
    List<Future<void>> killerFutures = [];
    final limited = taskKillers
        .where((element) => element.$1.$1 == docIndex)
        .toList();
    for (var taskKiller in limited) {
      killerFutures.add(taskKiller.$2.kill());
    }
    await Future.wait(killerFutures);
    await awaitIsolatesOfDocument(docIndex);
  }

  void changePrioForIsolatesOfDocument(int docIndex, IsolatePriority newPrio) {
    if (taskKillers.isEmpty) return;
    final limited = taskKillers.where((element) => element.$1.$1 == docIndex);
    for (var taskKiller in limited) {
      taskKiller.$2.changePrio(newPrio);
    }
  }

  Future<void> awaitIsolatesOfHigherIndexedDocuments(int docIndex) async {
    while (taskKillers.isNotEmpty) {
      int remainingCount = 0;
      final limited = taskKillers
          .where((element) => element.$1.$1 > docIndex)
          .toList();
      for (var taskKiller in limited) {
        if (taskKiller.$2.exited) {
          taskKillers.remove(taskKiller);
        } else {
          remainingCount++;
        }
      }
      if (remainingCount == 0) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfPage(int docIndex, int pageIndex) async {
    bool mayExit = false;
    while (taskKillers.isNotEmpty) {
      int remainingCount = 0;
      final limited = taskKillers
          .where(
            (element) =>
                element.$1.$1 == docIndex && element.$1.$2 == pageIndex,
          )
          .toList();
      for (var taskKiller in limited) {
        if (taskKiller.$2.exited) {
          taskKillers.remove(taskKiller);
        } else {
          remainingCount++;
        }
      }
      if (remainingCount == 0) {
        if (mayExit) {
          return;
        } else {
          mayExit = true;
        }
      } else {
        mayExit = false;
      }
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexPage(
    int docIndex,
    int pageIndex,
  ) async {
    while (taskKillers.isNotEmpty) {
      int remainingCount = 0;
      final limited = taskKillers
          .where(
            (element) => element.$1.$1 == docIndex && element.$1.$2 > pageIndex,
          )
          .toList();
      for (var taskKiller in limited) {
        if (taskKiller.$2.exited) {
          taskKillers.remove(taskKiller);
        } else {
          remainingCount++;
        }
      }
      if (remainingCount == 0) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfHigherIndexPages(
    int docIndexIn,
    List<int> pageIndexesIn,
  ) async {
    if (taskKillers.isEmpty) return;
    final pageIndexes = List<int>.from(pageIndexesIn);
    int smallestIndex = pageIndexes.reduce(math.min);
    pageIndexes.remove(smallestIndex);
    while (taskKillers.isNotEmpty) {
      int remainingCount = 0;
      final limited = taskKillers
          .where(
            (element) =>
                element.$1.$1 == docIndexIn &&
                element.$1.$2 > smallestIndex &&
                !pageIndexesIn.contains(element.$1.$2),
          )
          .toList();
      for (var taskKiller in limited) {
        if (taskKiller.$2.exited) {
          taskKillers.remove(taskKiller);
        } else {
          remainingCount++;
        }
      }
      if (remainingCount == 0) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitIsolatesOfDocument(int docIndex) async {
    while (taskKillers.isNotEmpty) {
      int remainingCount = 0;
      final limited = taskKillers
          .where((element) => element.$1.$1 == docIndex)
          .toList();
      for (var taskKiller in limited) {
        if (taskKiller.$2.exited) {
          taskKillers.remove(taskKiller);
        } else {
          remainingCount++;
        }
      }
      if (remainingCount == 0) return;
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  Future<void> awaitAllIsolates() async {
    while (taskKillers.isNotEmpty) {
      taskKillers.removeWhere((element) => element.$2.exited);
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
    taskKillers.add(((docIndex, pageIndex), killer));

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
        taskKillers.removeWhere((element) => element.$2 == killer);
      }
    });
    await repairCompleter.future;

    await _compressPage(docIndex, pageIndex);
  }

  static Future<void> _rotatePageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      int docIndex,
      int pageIndex,
      String rotatedPhotoPath,
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

    List<Future<void>> futures = [];

    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    String rotatedPhotoPath = data.$5;
    int rotationIn = data.$6;
    AppGlobals g = data.$7;

    if (!File(rotatedPhotoPath).existsSync()) {
      throw StateError("photo $rotatedPhotoPath does not exist");
    }

    // Delete Thumbnail
    futures.add(_deleteThumbnailInIsolate(docIndex, pageIndex, g));

    /// 1. save rotated photo
    await isolateExitPoint(kill);
    futures.add(
      g.filesHelper.writeImageRaw(
        docIndex,
        pageIndex,
        0,
        rotatedPhotoPath,
        gIn: g,
      ),
    );

    bool isImportedPdf = await MetadataHelper.readPageImportedPdf(
      docIndex,
      pageIndex,
      supressWarnings: true,
      gIn: g,
    );

    List<String> versionPaths = (await g.filesHelper.getImagePathsForPage(
      docIndex,
      pageIndex,
    )).$1;

    /// 2. rotate processed -> save
    if (!isImportedPdf) {
      final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
      // Warped, Contrast, Processed1, Processed2
      for (int i = 1; i < versionPaths.length; i++) {
        Future<void> rotateVersion() async {
          await isolateExitPoint(kill);
          if (!File(versionPaths[i]).existsSync()) {
            dev.log("Error, ${versionPaths[i]} does not exist");
          }
          imageProcessor.rotateImage(
            versionPaths[i],
            await g.filesHelper.createVersionPath(docIndex, pageIndex, i),
            rotationIn,
          );
        }

        futures.add(rotateVersion());
      }

      // Delete prior Image
      await Future.wait(futures);
      imageProcessor.dispose();
      for (var priorPath in versionPaths) {
        await isolateExitPoint(kill);
        if (File(priorPath).existsSync()) {
          await File(priorPath).delete();
        }
      }
    }

    // Update Thumbnail
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    // Set New Thumbnail
    await isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, g);

    Isolate.exit(sendPort, "done");
  }

  Future<void> rotatePage(
    int docIndex,
    int pageIndex,
    String rotatedPhotoPath,
    final int angle,
  ) async {
    // Save current (to be outdated) filenames to metadata
    await saveOldVersionFileNames(docIndex, pageIndex);

    final port = ReceivePort();
    final token = RootIsolateToken.instance!;
    final rotatePageCompleter = Completer<void>();

    await killIsolatesOfPage(docIndex, pageIndex);

    TaskKiller killer = await IsolatesManager().runTask(
      _rotatePageIsolate,
      (port.sendPort, token, docIndex, pageIndex, rotatedPhotoPath, angle, g),
      portIn: port,
      prio: IsolatePriority.immediate,
    );
    taskKillers.add(((docIndex, pageIndex), killer));

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
        taskKillers.removeWhere((element) => element.$2 == killer);
        rotatePageCompleter.complete();
      }
    });
    await rotatePageCompleter.future;

    await _compressPage(docIndex, pageIndex);
  }

  static Future<bool> _scaleAndSaveThumbnailInIsolate(
    SendPort sendPort,
    int docIndex,
    int pageIndex,
    AppGlobals gIn,
  ) async {
    bool kill = false;
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });
    // Overwrites controlPort, so it has to be last in Isolate,
    // or the Isolate has to send its controlPort anew

    // Get thumbnailIndex from metadata, else set it in metadata
    int? metadataThumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
      docIndex,
      pageIndex,
      gIn: gIn,
      supressWarnings: true,
    );
    int thumbnailIndex = metadataThumbnailIndex ?? gIn.defaultIndex;
    if (metadataThumbnailIndex == null) {
      await isolateExitPoint(kill);
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
      await isolateExitPoint(kill);
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
      await isolateExitPoint(kill);
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
            await isolateExitPoint(kill);
            File(oldThumbnailPath).deleteSync();
          }
        }
      }
    } catch (e) {
      dev.log(
        "Warning, _scaleAndSaveThumbnailIsolate: Could not delete old thumbnail: $e",
      );
    }

    await isolateExitPoint(kill);
    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
    await isolateExitPoint(kill);
    int newWidth = (screenWidth * 0.927083333).toInt();
    String thumbnailPath = "$pagePath/${versionFileName}_thumbnail.png";
    imageProcessor.scaleImageToWidth(versionPath, thumbnailPath, newWidth);
    imageProcessor.dispose();

    try {
      // Update thumbnails:
      await isolateExitPoint(kill);
      sendPort.send(NotifierEvent.loadPagesThumbnails);
    } catch (e) {
      throw StateError("Error, writeScaledThumbnail, notify: :$e");
    }

    return true;
  }

  static Future<void> _deleteThumbnailInIsolate(
    int docIndex,
    int pageIndex,
    AppGlobals gIn,
  ) async {
    String pagePath;
    try {
      pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    } catch (e) {
      throw StateError(
        "Error, _scaleAndSaveThumbnailInIsolate, getPagePath, getVersionPath: $e",
      );
    }
    try {
      for (FileSystemEntity fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("thumbnail")) {
          File(fse.path).deleteSync();
        }
      }
    } catch (e) {
      dev.log(
        "Warning, _scaleAndSaveThumbnailIsolate: Could not delete old thumbnail: $e",
      );
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

    await isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, gIn);

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

    taskKillers.add(((docIndex, pageIndex), killer));

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
        taskKillers.removeWhere((element) => element.$2 == killer);
        completer.complete();
      }
    });
    await completer.future;
  }

  Future<(int, int)> importPdf(String pdfPath, {int? addToDocWithIndex}) async {
    // Open and render PDF
    final pdfrx.PdfDocument doc = await pdfrx.PdfDocument.openFile(pdfPath);
    final int pageCount = doc.pages.length;
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
    // Render PDF -> Pages
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
    pdfrx.PdfDocument doc,
    int docIndex,
  ) async {
    await Future.delayed(Duration(milliseconds: 100)); // wait for navigation
    if (await _pdfProcessingExitpoint(docIndex)) return;

    List<Future> futures = [];
    final List<pdfrx.PdfPage> pdfPages = doc.pages;
    for (final (pageIndex, pdfPage) in pdfPages.indexed) {
      if (await _pdfProcessingExitpoint(docIndex, pageIndex: pageIndex)) return;
      futures.add(_renderPdfPage(pdfPage, docIndex, pageIndex, firstPageIndex));
    }

    // Cleanup
    await Future.wait(futures);
    doc.dispose();
    Future.microtask(() async {
      await Future.delayed(Duration(microseconds: 100));
      pdfProcessingFutures.remove(docIndex);
    });
  }

  Future<void> _renderPdfPage(
    pdfrx.PdfPage page,
    int docIndex,
    int pageIndex,
    int firstPageIndex,
  ) async {
    // render Page at 300 DPI (max 4048 pixel)
    const targetDpi = 300;
    const defaultAssumedDpi = 72;
    final dpiScale = targetDpi / defaultAssumedDpi;
    const maxSize = AppGlobals.maxPhotoSize;
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
      fullWidth: (page.width * limitingScale * dpiScale),
      fullHeight: (page.height * limitingScale * dpiScale),
    );
    // Uint8List, PNG
    final img.Image pageImage = renderedPage!.createImageNF();
    final Uint8List pngBytes = Uint8List.fromList(img.encodePng(pageImage));
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
    taskKillers.add(((docIndex, pageIndex), killer));

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
        taskKillers.removeWhere((element) => element.$2 == killer);
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
    await isolateExitPoint(kill);
    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      0,
      gIn: g,
      supressWarnings: true,
    );

    // Save Photo
    await isolateExitPoint(kill);
    await g.filesHelper.savePageVersion(
      docIndex,
      pageIndex,
      0,
      pngBytes,
      ".png",
    );
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    // Generate Metadata
    await isolateExitPoint(kill);
    final imgInfo = AppGlobals.getPngInfo(pngBytes);
    if (imgInfo == null) {
      throw StateError("Error, processPdfPage: can't decode Image.");
    }
    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
    await isolateExitPoint(kill);
    imageProcessor.setAvailableAspectRatios(g.availableAspectRatios);
    final matchingAspectRatio = imageProcessor.matchAspectRatioAndOrientation(
      imgInfo.height / imgInfo.width,
    );
    imageProcessor.dispose();

    // Write Metadata
    await isolateExitPoint(kill);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      matchingAspectRatio,
      null,
      gIn: g,
    );

    await isolateExitPoint(kill);
    await MetadataHelper.writePageThumbnailIndex(
      docIndex,
      pageIndex,
      0,
      gIn: g,
    );
    await isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, g);

    Isolate.exit(sendPort, "done");
  }

  Future<(List<String>, List<double>)> scaleImagesToMaxDpi(
    int docIndex,
    List<int> pageIndexes,
    int? versionIndexIn,
    int? maxDpi,
  ) async {
    List<String> imagePaths = await g.filesHelper.getImagePaths(
      pageIndexes,
      versionIndexIn,
      docIndex,
    );
    List<int> pagesDpis;
    List<double> widthsInInches;
    (pagesDpis, widthsInInches) = await g.filesHelper.getPdfPageDpis(
      docIndex,
      pageIndexes: pageIndexes,
      versionIndex: versionIndexIn,
    );
    if (maxDpi == null) return (imagePaths, widthsInInches);

    final tmpDir = await getTemporaryDirectory();
    List<Future> futures = [];
    if (pageIndexes.isEmpty) {
      pageIndexes = List.generate(imagePaths.length, (index) => index);
    }
    for (var (i, pageIndex) in pageIndexes.indexed) {
      if (pagesDpis[i] > maxDpi) {
        final int versionIndex =
            await MetadataHelper.readPageThumbnailIndex(docIndex, pageIndex) ??
            g.defaultIndex;
        final scaledImagePath =
            "${tmpDir.path}/scaled_${docIndex}_${pageIndex}_DPI_$maxDpi.png";

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
            maxDpi,
            widthsInInches[i],
            g,
          ),
          portIn: port,
          prio: IsolatePriority.quick,
        );
        taskKillers.add(((docIndex, pageIndex), killer));

        imagePaths[i] = scaledImagePath;
        final completer = Completer<void>();
        futures.add(completer.future);
        port.listen((message) async {
          if (message is SendPort) {
            killer.setControlPort(message);
          } else if (message == "done") {
            completer.complete();
            taskKillers.removeWhere((element) => element.$2 == killer);
          }
        });
      }
    }

    await Future.wait(futures);
    return (imagePaths, widthsInInches);
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
      await isolateExitPoint(kill);
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

    // Scale
    await isolateExitPoint(kill);
    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
    await isolateExitPoint(kill);
    int newWidth = (widthInInches * toDpi).toInt();
    imageProcessor.scaleImageToWidth(versionPath, scaledImagePath, newWidth);
    imageProcessor.dispose();

    Isolate.exit(sendPort, "done");
  }

  List<TaskKiller> rotatePhotoKillers = [];
  Future<List<String>> rotatePhotoInTmpDir(
    String photoPath,
    int docIndex,
    int pageIndex,
  ) async {
    final List<String> roatedFilePaths = [];
    for (int rotation = 90; rotation <= 270; rotation += 90) {
      final tmpDir = await getTemporaryDirectory();
      roatedFilePaths.add("${tmpDir.path}/rotated_$rotation.png");

      if (!File(roatedFilePaths.last).existsSync()) {
        final port = ReceivePort();

        TaskKiller killer = await IsolatesManager().runTask(
          _rotatePhotoInTmpDirIsolate,
          (port.sendPort, photoPath, roatedFilePaths.last, rotation),
          portIn: port,
          prio: IsolatePriority.quick,
        );
        rotatePhotoKillers.add(killer);
        taskKillers.add(((docIndex, pageIndex), killer));

        port.listen((message) async {
          if (message is SendPort) {
            killer.setControlPort(message);
          } else if (message == "done") {
            rotatePhotoKillers.removeWhere((element) => element == killer);
            taskKillers.removeWhere((element) => element.$2 == killer);
          }
        });
      }
    }

    return roatedFilePaths;
  }

  static Future<void> _rotatePhotoInTmpDirIsolate(
    (SendPort sendPort, String photoPath, String rotatedFilePath, int angle)
    data,
  ) async {
    SendPort sendPort = data.$1;
    // Control Port for exiting gracefully
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    bool kill = false;
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    String photoPath = data.$2;
    String rotatedFilePath = data.$3;
    int angle = data.$4;

    await isolateExitPoint(kill);
    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
    await isolateExitPoint(kill);
    imageProcessor.rotateImage(
      photoPath,
      rotatedFilePath,
      angle,
      hideUncompressedSuffix: true,
    );
    imageProcessor.dispose();

    Isolate.exit(sendPort, "done");
  }

  Future<void> deleteRotatedPhotos() async {
    List<String> paths = [];
    final tmpDir = await getTemporaryDirectory();
    for (var angle = 90; angle <= 270; angle += 90) {
      paths.add("${tmpDir.path}/rotated_$angle.png");
    }
    FilesHelper.deleteImagePaths(paths);
    for (var killer in rotatePhotoKillers) {
      killer.kill();
      taskKillers.removeWhere((element) => element.$2 == killer);
    }
    rotatePhotoKillers.clear();
  }

  static Future<bool> _compressAndReplacePng({
    required String uncompressedPath,
    required String compressedPath,
    int minCompressQuality = 0,
  }) async {
    try {
      final uncompressedFile = File(uncompressedPath);
      if (!await uncompressedFile.exists()) {
        return false;
      }

      // Temporary filename in same directory
      // Avoids polling from reading the image while still writing
      final dir = Directory(p.dirname(compressedPath));
      final tmpName =
          'tmp_${DateTime.now().millisecondsSinceEpoch}${p.extension(compressedPath)}';
      final tmpPath = p.join(dir.path, tmpName);
      final tmpFile = File(tmpPath);

      final resultBytes = await FlutterImageCompress.compressWithFile(
        uncompressedPath,
        quality: minCompressQuality,
        format: CompressFormat.png,
        minWidth: AppGlobals.maxPhotoSize,
        minHeight: AppGlobals.maxPhotoSize,
      );

      if (resultBytes == null) {
        throw Exception(
          "Error, _compressAndReplacePng: compressWithFile failed",
        );
      }

      await tmpFile.writeAsBytes(resultBytes);
      await tmpFile.rename(compressedPath);
      await uncompressedFile.delete();

      return true;
    } catch (e) {
      dev.log('Error, compressAndReplacePng: $e');
      return false;
    }
  }

  static Future<void> _compressVersion(
    int docIndex,
    int pageIndex,
    int versionIndex, {
    AppGlobals? gIn,
  }) async {
    gIn ??= g;
    final String uncompressedPath = await gIn.filesHelper.getVersionPath(
      docIndex,
      pageIndex,
      versionIndex,
    );
    if (uncompressedPath.isEmpty) {
      throw Exception("Error: compressVersion does not exist");
    }
    if (!uncompressedPath.contains("_uncompressed")) return;
    final String compressedPath = uncompressedPath.replaceFirst(
      "_uncompressed",
      "",
    );
    await _compressAndReplacePng(
      uncompressedPath: uncompressedPath,
      compressedPath: compressedPath,
    );
  }

  static Future<void> _compressPageIsolate(
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
    RootIsolateToken token = data.$2;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    int docIndex = data.$3;
    int pageIndex = data.$4;
    AppGlobals g = data.$5;

    // Control Port for exiting gracefully
    bool kill = false;
    final controlPort = ReceivePort();
    sendPort.send(controlPort.sendPort);
    controlPort.listen((msg) {
      if (msg == "kill") {
        kill = true;
      }
    });

    String pagePath = await g.filesHelper.getPagePath(docIndex, pageIndex);
    List<Future<void>> futures = [];
    bool anyChange = false;
    try {
      List<FileSystemEntity> versionsFSE = (Directory(pagePath).listSync()
        ..sort((a, b) => a.path.compareTo(b.path)));
      for (var fse in versionsFSE) {
        if (fse.path.contains("_uncompressed")) {
          final String compressedPath = fse.path.replaceFirst(
            "_uncompressed",
            "",
          );
          await isolateExitPoint(kill, futures: futures);
          futures.add(
            _compressAndReplacePng(
              uncompressedPath: fse.path,
              compressedPath: compressedPath,
            ),
          );
          anyChange = true;
        }
      }
    } catch (e) {
      dev.log("Warning, compressPage failed: $e");
    }
    await Future.wait(futures);

    if (anyChange) {
      // Update thumbnails:
      await isolateExitPoint(kill, futures: futures);
      sendPort.send(NotifierEvent.loadPagesThumbnails);
    }

    Isolate.exit(sendPort, "done");
  }

  Future<void> _compressPage(int docIndex, int pageIndex) async {
    final completer = Completer<void>();
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;
    TaskKiller killer = await IsolatesManager().runTask(
      _compressPageIsolate,
      (port.sendPort, token, docIndex, pageIndex, g),
      portIn: port,
      prio: IsolatePriority.late,
      onErrorFunction: (error, stack) async {
        dev.log("_compressPage, onErrorFunction: $error $stack");
      },
    );
    taskKillers.add(((docIndex, pageIndex), killer));

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
        taskKillers.removeWhere((element) => element.$2 == killer);
        completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> compressAll() async {
    final docsCount = await g.filesHelper.getDocumentsCount();
    for (var docIndex = 0; docIndex < docsCount; docIndex++) {
      final pagesCount = await g.filesHelper.getPagesCount(docIndex);
      for (var pageIndex = 0; pageIndex < pagesCount; pageIndex++) {
        _compressPage(docIndex, pageIndex);
      }
    }
  }
}
