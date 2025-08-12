// function:
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:docscanner/app/files_helper.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
// isolates:
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'dart:isolate' show ReceivePort, SendPort, Isolate;
import 'package:docscanner/app/isolates_manager.dart';
// my packages:
import 'package:docscanner/app/opencv_helper.dart';
import 'package:docscanner/app/main.dart' show globalNotifier, versionNames;
import 'package:docscanner/app/metadata_helper.dart';
import 'package:docscanner/app/app_globals.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:pdf_render/pdf_render.dart' as pdfr;
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
    String photoPath = data.$5;

    double? ratioValueIn = data.$6;
    List<List<int>>? cornerPointsIn = data.$7;
    int rotationIn = data.$8;
    bool isInitial = data.$9;
    AppGlobals g = data.$10;

    OpenCVHelper cvHelper = OpenCVHelper(g);

    List<Future<void>> ioFutures = [];
    List<Future<void>> filterFutures = [];

    final int initialThumbnailIndex;

    (
      initialThumbnailIndex,
      ioFutures,
      filterFutures,
    ) = await _processPageIsolateThumbnailVersion(
      sendPort,
      docIndex,
      pageIndex,
      photoPath,
      ratioValueIn,
      cornerPointsIn,
      rotationIn,
      isInitial,
      g,
      cvHelper,
      ioFutures,
      filterFutures,
    );

    (ioFutures, filterFutures) = await _processPageIsolateFilters(
      sendPort,
      docIndex,
      pageIndex,
      initialThumbnailIndex,
      g,
      cvHelper,
      ioFutures,
      filterFutures,
    );

    await Future.wait(filterFutures);
    await Future.wait(ioFutures);
    Isolate.exit(sendPort, "done");
  }

  static Future<(int, List<Future<void>>, List<Future<void>>)>
  _processPageIsolateThumbnailVersion(
    SendPort sendPort,
    int docIndex,
    int pageIndex,
    String photoPath,
    double? ratioValueIn,
    List<List<int>>? cornerPointsIn,
    int rotationIn,
    bool isInitial,
    AppGlobals g,
    OpenCVHelper cvHelper,
    List<Future<void>> ioFutures,
    List<Future<void>> filterFutures,
  ) async {
    List<Future<void>> ioFutures = [];
    List<Future<void>> filterFutures = [];

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
    ioFutures.add(_deleteThumbnailInIsolate(docIndex, pageIndex, g));

    await isolateExitPoint(kill, ioFutures: ioFutures);
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
    await isolateExitPoint(kill, ioFutures: ioFutures);
    //var warpedRet =
    filterFutures.add(
      cvb.warpImage(
        photoPath,
        await g.filesHelper.createVersionPath(docIndex, pageIndex, 1),
      ),
    );
    //Uint8List warpedBytes = warpedRet.$1;
    //double ratioValue = warpedRet.$2;
    //List<List<int>>? cornerPoints = warpedRet.$3;
    List<List<int>>? cornerPoints;

    await isolateExitPoint(kill, ioFutures: ioFutures);
    //ioFutures.add(
    //  g.filesHelper.savePageVersion(
    //    docIndex,
    //    pageIndex,
    //    1,
    //    warpedBytes,
    //    ".png",
    //  ),
    //);

    // initialThumbnailIndex
    final int initialThumbnailIndex = 1;
    await isolateExitPoint(kill, ioFutures: ioFutures);
    //int? readThumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
    //  docIndex,
    //  pageIndex,
    //  gIn: g,
    //  supressWarnings: true,
    //);
    //if (readThumbnailIndex == null) {
    //  initialThumbnailIndex = g.defaultIndex;
    //  await isolateExitPoint(kill, ioFutures: ioFutures);
    //  ioFutures.add(
    //    MetadataHelper.writePageThumbnailIndex(
    //      docIndex,
    //      pageIndex,
    //      initialThumbnailIndex,
    //      gIn: g,
    //      supressWarnings: true,
    //    ),
    //  );
    //} else {
    //  initialThumbnailIndex = readThumbnailIndex;
    //}

    // First process (default) Thumbnail version
    Future<void> processThumbnailVersion() async {
      if (initialThumbnailIndex > 1) {
        await isolateExitPoint(kill, ioFutures: ioFutures);
        final Uint8List? thumbnailVersionBytes;
        switch (initialThumbnailIndex) {
          case 2:
            // Contrast
            await isolateExitPoint(kill, ioFutures: ioFutures);
            thumbnailVersionBytes = await cvHelper.processImageContrast();
            break;
          case 3:
            // Document
            await isolateExitPoint(kill, ioFutures: ioFutures);
            thumbnailVersionBytes = await cvHelper.processImageDocument();
            break;
          case 4:
          case 5:
            // PRO
            await isolateExitPoint(kill, ioFutures: ioFutures);
            Uint8List processed2Bytes = await cvHelper.processImagePro();
            // PRO 2
            await isolateExitPoint(kill, ioFutures: ioFutures);
            thumbnailVersionBytes = await cvHelper.processImagePro2();
            ioFutures.add(
              g.filesHelper.savePageVersion(
                docIndex,
                pageIndex,
                4,
                processed2Bytes,
                ".png",
              ),
            );
            break;
          default:
            thumbnailVersionBytes = null;
        }
        await isolateExitPoint(kill, ioFutures: ioFutures);
        if (thumbnailVersionBytes != null) {
          ioFutures.add(
            g.filesHelper.savePageVersion(
              docIndex,
              pageIndex,
              initialThumbnailIndex == 4 ? 5 : initialThumbnailIndex,
              thumbnailVersionBytes,
              ".png",
            ),
          );
        }
      }
    }

    //filterFutures.add(processThumbnailVersion());

    // Update thumbnails:
    await isolateExitPoint(kill, ioFutures: ioFutures);
    sendPort.send(NotifierEvent.loadPagesThumbnails);

    // Metadata
    await isolateExitPoint(kill, ioFutures: ioFutures);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      math.sqrt2, //ratioValue,
      cornerPoints,
      gIn: g,
    );

    return (initialThumbnailIndex, ioFutures, filterFutures);
  }

  static Future<(List<Future<void>>, List<Future<void>>)>
  _processPageIsolateFilters(
    SendPort sendPort,
    int docIndex,
    int pageIndex,
    int initialThumbnailIndex,
    AppGlobals g,
    OpenCVHelper cvHelper,
    List<Future<void>> ioFutures,
    List<Future<void>> filterFutures,
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

    //// Kontrast
    //await isolateExitPoint(kill, ioFutures: ioFutures);
    //if (initialThumbnailIndex != 2) {
    //  Future<void> processContrastFilter() async {
    //    Uint8List contrastBytes = await cvHelper.processImageContrast();
    //    await isolateExitPoint(kill, ioFutures: ioFutures);
    //    ioFutures.add(
    //      g.filesHelper.savePageVersion(
    //        docIndex,
    //        pageIndex,
    //        2,
    //        contrastBytes,
    //        ".png",
    //      ),
    //    );
    //  }
    //
    //  filterFutures.add(processContrastFilter());
    //}
    //
    //// Dokument
    //await isolateExitPoint(kill, ioFutures: ioFutures);
    //if (initialThumbnailIndex != 3) {
    //  Future<void> processDocumentFilter() async {
    //    Uint8List processed1Bytes = await cvHelper.processImageDocument();
    //    await isolateExitPoint(kill, ioFutures: ioFutures);
    //    ioFutures.add(
    //      g.filesHelper.savePageVersion(
    //        docIndex,
    //        pageIndex,
    //        3,
    //        processed1Bytes,
    //        ".png",
    //      ),
    //    );
    //  }
    //
    //  filterFutures.add(processDocumentFilter());
    //}
    //
    //if (initialThumbnailIndex != 4 && initialThumbnailIndex != 5) {
    //  Future<void> processPROFilters() async {
    //    // PRO
    //    await isolateExitPoint(kill, ioFutures: ioFutures);
    //    Uint8List processed2Bytes = await cvHelper.processImagePro();
    //    await isolateExitPoint(kill, ioFutures: ioFutures);
    //    ioFutures.add(
    //      g.filesHelper.savePageVersion(
    //        docIndex,
    //        pageIndex,
    //        4,
    //        processed2Bytes,
    //        ".png",
    //      ),
    //    );
    //
    //    // PRO 2
    //    await isolateExitPoint(kill, ioFutures: ioFutures);
    //    Uint8List processed3Bytes = await cvHelper.processImagePro2();
    //    await isolateExitPoint(kill, ioFutures: ioFutures);
    //    ioFutures.add(
    //      g.filesHelper.savePageVersion(
    //        docIndex,
    //        pageIndex,
    //        5,
    //        processed3Bytes,
    //        ".png",
    //      ),
    //    );
    //  }
    //
    //  filterFutures.add(processPROFilters());
    //}

    // Set New Thumbnail
    await isolateExitPoint(kill, ioFutures: ioFutures);
    await Future.wait(ioFutures);
    await isolateExitPoint(kill, ioFutures: ioFutures);
    ioFutures.add(
      _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, g),
    );

    return (ioFutures, filterFutures);
  }

  static Future<void> isolateExitPoint(
    final bool kill, {
    List<Future<void>> ioFutures = const [],
  }) async {
    if (kill) {
      await Future.wait(ioFutures);
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
    await saveOldVersionFileNames(
      docIndex,
      pageIndex,
      isPhotoAlreadyInPage: isPhotoAlreadyInPage,
    );

    // Photo
    final imageRaw = g.filesHelper.readImageRaw(photoPath);
    Uint8List photoBytes = imageRaw.$1;
    String photoExtension = imageRaw.$2;
    if (!isPhotoAlreadyInPage) {
      await g.filesHelper.writeImageRaw(
        docIndex,
        pageIndex,
        0,
        photoBytes,
        photoExtension,
        gIn: g,
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
        rotationIn,
        isInitial,
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
    String thumbnailPath = imagePaths.$2;

    isolateExitPoint(kill);
    final photoFile = File(versionPaths[0]);
    if (!photoFile.existsSync() || photoFile.lengthSync() < 9) {
      throw StateError("Error, _repairPageIsolate: No photo");
    }

    // Warped
    Uint8List? warpedBytes;
    if (versionPaths[1].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[1].contains(oldVersionFileNames[1])) ||
        (ratioValue == null || cornerPoints == null)) {
      isolateExitPoint(kill);
      var warpedRet = await cvHelper.warpImage(
        File(versionPaths[0]).readAsBytesSync(),
        ratioValueIn: ratioValue,
        cornerPoints: cornerPoints,
        onlyCalculateBorder: versionPaths[1].isNotEmpty,
      );
      warpedBytes = warpedRet.$1;
      isolateExitPoint(kill);
      await g.filesHelper.savePageVersion(
        docIndex,
        pageIndex,
        1,
        warpedBytes,
        ".png",
      );

      // Metadata
      ratioValue = warpedRet.$2;
      cornerPoints = warpedRet.$3;
    } else {
      warpedBytes = File(versionPaths[1]).readAsBytesSync();
      cvHelper.setWarped(warpedBytes);
    }

    // Metadata
    isolateExitPoint(kill);
    await MetadataHelper.writePageProcessingMetadata(
      docIndex,
      pageIndex,
      ratioValue,
      cornerPoints,
      gIn: g,
    );

    // Contrast
    if (versionPaths[2].isEmpty ||
        (oldVersionFileNames != null &&
            versionPaths[2].contains(oldVersionFileNames[2]))) {
      isolateExitPoint(kill);
      Uint8List contrastBytes = await cvHelper.processImageContrast();
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
      Uint8List processed1 = await cvHelper.processImageDocument();
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
      processed2Bytes = await cvHelper.processImagePro();
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
      cvHelper.setProecessed2(processed2Bytes);
      isolateExitPoint(kill);
      Uint8List processed3Bytes = await cvHelper.processImagePro2();
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
      taskKillers.remove(taskKiller);
    }
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
      taskKillers.remove(taskKiller);
    }
    await Future.wait(killerFutures);
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

  Future<void> awaitIsolatesOfHigherIndexPage(int docIndex, pageIndex) async {
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

  Future<void> awaitAllIsolatesOfDocument(int docIndex) async {
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

    List<Future<void>> futures = [];

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

    // Delete Thumbnail
    futures.add(_deleteThumbnailInIsolate(docIndex, pageIndex, g));

    /// 1. save rotated photo
    isolateExitPoint(kill);
    final rotatedPhotoRaw = g.filesHelper.readImageRaw(versionPaths[0]);
    Uint8List rotatedPhotoBytes = rotatedPhotoRaw.$1;
    String rotatedPhotoExtension = rotatedPhotoRaw.$2;
    isolateExitPoint(kill);
    futures.add(
      g.filesHelper.writeImageRaw(
        docIndex,
        pageIndex,
        0,
        rotatedPhotoBytes,
        rotatedPhotoExtension,
        gIn: g,
      ),
    );

    bool isImportedPdf = await MetadataHelper.readPageImportedPdf(
      docIndex,
      pageIndex,
      supressWarnings: true,
      gIn: g,
    );

    /// 2. rotate processed -> save
    if (!isImportedPdf) {
      // Warped, Contrast, Processed1, Processed2
      for (int i = 1; i < versionPaths.length; i++) {
        Future<void> rotateVersion() async {
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

        futures.add(rotateVersion());
      }
    }

    // Update Thumbnail
    isolateExitPoint(kill);
    Future.wait(futures);
    sendPort.send(NotifierEvent.loadPagesThumbnails);
    // Set New Thumbnail
    isolateExitPoint(kill);
    await _scaleAndSaveThumbnailInIsolate(sendPort, docIndex, pageIndex, g);

    Isolate.exit(sendPort, "done");
  }

  Future<void> rotatePage(
    int docIndex,
    int pageIndex,
    List<String> versionPaths, //[0] is rotated
    final int angle,
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

    isolateExitPoint(kill);
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
    pdfr.PdfDocument doc,
    int docIndex,
  ) async {
    await Future.delayed(Duration(milliseconds: 100)); // wait for navigation
    if (await _pdfProcessingExitpoint(docIndex)) return;
    List<Future> futures = [];
    for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      await saveOldVersionFileNames(docIndex, pageIndex);
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
    const defaultAssumedDpi = 72;
    final dpiScale = targetDpi / defaultAssumedDpi;
    const maxSize = 4962; // 600 PDI for A4
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

  static Future<Uint8List?> scaleImageToMaxSize(
    final Uint8List imgBytes,
    final String fileExtension, {
    AppGlobals? gIn,
    final int maxSize =
        4962, // 2481: 300 DPI for A4 -> double for distance from camera
  }) async {
    gIn ??= g;
    final imgInfo = await AppGlobals.getImageBytesInfo(imgBytes, fileExtension);
    if (imgInfo == null) return null;

    final int imgWidth = imgInfo.width;
    final int imgHeight = imgInfo.height;
    if (imgWidth < maxSize && imgHeight < maxSize) return null;

    int newWidth = maxSize;
    if (imgWidth < imgHeight) {
      newWidth = maxSize * imgWidth ~/ imgHeight;
    }

    OpenCVHelper cvHelper = OpenCVHelper(gIn);
    Uint8List scaledBytes;
    (scaledBytes, _) = await cvHelper.scaleImageToWidth(imgBytes, newWidth);
    return scaledBytes;
  }

  List<TaskKiller> rotatePhotoKillers = [];
  Future<List<String>> rotatePhoto(
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
          _rotatePhotoIsolate,
          (port.sendPort, photoPath, roatedFilePaths.last, rotation, g),
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

  static Future<void> _rotatePhotoIsolate(
    (
      SendPort sendPort,
      String imagePath,
      String rotatedFilePath,
      int angle,
      AppGlobals gIn,
    )
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

    String imagePath = data.$2;
    String rotatedFilePath = data.$3;
    int angle = data.$4;
    AppGlobals gIn = data.$5;

    isolateExitPoint(kill);
    OpenCVHelper cvHelper = OpenCVHelper(gIn);
    isolateExitPoint(kill);
    Uint8List imageBytes = await File(imagePath).readAsBytes();
    isolateExitPoint(kill);
    Uint8List rotatedBytes = await cvHelper.rotateImage(imageBytes, angle);
    isolateExitPoint(kill);
    File(rotatedFilePath).writeAsBytesSync(rotatedBytes);
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
}
