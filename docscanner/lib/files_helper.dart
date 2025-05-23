import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
// pdf:
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pdfw;
import 'package:pdf_render/pdf_render.dart' as pdfr;
// isolates:
import 'dart:isolate' show ReceivePort, SendPort;
import 'package:docscanner/isolates_manager.dart';
// my packages:
import 'package:docscanner/image_prosessing_manager.dart';
import 'package:docscanner/main.dart'
    show globalNotifier, imageProcessingManager, isTmpExternal;
import 'package:docscanner/metadata_helper.dart';
import 'package:docscanner/opencv_helper.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
import 'app_globals.dart' show AppGlobals, NotifierEvent, g;

class FilesHelper {
  late String docsPath = "";
  int screenWidth;
  final List<List<int>> _markedDeletedPages = [];
  final List<int> _markedDeletedDocs = [];

  Future<List<int>> getMarkedDeletedPages(int docIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("markedDeletedPages");
    List<List<int>> decoded = _markedDeletedPages;
    if (jsonString != null && jsonString != "[]") {
      decoded = (jsonDecode(jsonString) as List<dynamic>)
          .map<List<int>>((e) => List<int>.from(e as List))
          .toList();
    }
    _markedDeletedPages.clear();
    _markedDeletedPages.addAll(decoded);
    return _markedDeletedPages[docIndex];
  }

  _addMarkedDeletedPage(int docIndex, int pageIndex) async {
    if (_markedDeletedPages[docIndex].contains(pageIndex)) return;
    final prefs = await SharedPreferences.getInstance();
    while (_markedDeletedPages.length <= docIndex) {
      _markedDeletedPages.add([]);
    }
    _markedDeletedPages[docIndex].add(pageIndex);
    _markedDeletedPages[docIndex].sort();
    _markedDeletedPages[docIndex] = _markedDeletedPages[docIndex].reversed
        .toList();
    final jsonString = jsonEncode(_markedDeletedPages);
    prefs.setString("markedDeletedPages", jsonString);
    globalNotifier.triggerEvent(NotifierEvent.imagesDeleted);
  }

  _removeMarkedDeletedPage(int docIndex, int pageIndex) async {
    final prefs = await SharedPreferences.getInstance();
    while (_markedDeletedPages.length <= docIndex) {
      _markedDeletedPages.add([]);
    }
    //while (_markedDeletedPages[docIndex].contains(pageIndex)) {
    _markedDeletedPages[docIndex].remove(pageIndex);
    //}
    final jsonString = jsonEncode(_markedDeletedPages);
    prefs.setString("markedDeletedPages", jsonString);
  }

  Future<List<int>> getMarkedDeletedDocs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("markedDeletedDocs");
    List<int> decoded = _markedDeletedDocs;
    if (jsonString != null && jsonString != "[]") {
      decoded = (jsonDecode(jsonString) as List<dynamic>).cast<int>();
    }
    _markedDeletedDocs.clear();
    _markedDeletedDocs.addAll(decoded);
    return _markedDeletedDocs;
  }

  _addMarkedDeletedDoc(int docIndex) async {
    if (_markedDeletedDocs.contains(docIndex)) return;
    final prefs = await SharedPreferences.getInstance();
    _markedDeletedDocs.add(docIndex);
    List<int> tmp = _markedDeletedDocs;
    tmp.sort();
    _markedDeletedDocs.clear();
    _markedDeletedDocs.addAll(tmp.reversed.toList());
    final jsonString = jsonEncode(_markedDeletedDocs);
    prefs.setString("markedDeletedDocs", jsonString);
    globalNotifier.triggerEvent(NotifierEvent.imagesDeleted);
  }

  _removeMarkedDeletedDoc(int docIndex) async {
    final prefs = await SharedPreferences.getInstance();
    _markedDeletedDocs.remove(docIndex);
    final jsonString = jsonEncode(_markedDeletedDocs);
    prefs.setString("markedDeletedDocs", jsonString);
  }

  _deleteMarkedDeleted() async {
    // initialize lists
    await getMarkedDeletedDocs();
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("markedDeletedPages");
    if (jsonString != null && jsonString != "[]") {
      final List<List<int>> decoded = (jsonDecode(jsonString) as List<dynamic>)
          .map<List<int>>((e) => List<int>.from(e as List))
          .toList();
      _markedDeletedPages.clear();
      _markedDeletedPages.addAll(decoded);
    }
    // delete
    for (final docIndex in _markedDeletedDocs) {
      await _deleteDocument(docIndex);
    }
    List<Future> pagesFutures = [];
    for (var (docIndex, pageIndexes) in _markedDeletedPages.indexed) {
      if (pageIndexes.isEmpty) continue;
      pagesFutures.add(_deletePages(docIndex, pageIndexes));
    }
    await Future.wait(pagesFutures);
    _markedDeletedDocs.clear;
    _markedDeletedPages.clear;
    prefs.setString("markedDeletedDocs", "[]");
    prefs.setString("markedDeletedPages", "[]");
  }

  FilesHelper() : screenWidth = 1080 {
    _initializeDocumentsPath();
  }

  int calculateScreenWidth(BuildContext context) {
    if (context.mounted) {
      double logicalWidth = MediaQuery.of(context).size.width;
      double pixelRatio = MediaQuery.of(context).devicePixelRatio;
      return (logicalWidth * pixelRatio).round();
    } else {
      return 0;
    }
  }

  Future<String> _getDocumentsPath() async {
    await _initializeDocumentsPath();
    return docsPath;
  }

  Future<void> _initializeDocumentsPath() async {
    if (Directory(docsPath).existsSync()) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    final baseDir = await getApplicationDocumentsDirectory();
    docsPath = '${baseDir.path}/Documents';
    var docsDir = Directory(docsPath);
    if (!docsDir.existsSync()) {
      await docsDir.create(recursive: true);
    }
  }

  Future<(String, int)> _reserveNewDocument() async {
    int docIndex = 0;
    while (await Directory(
      await getDocumentPath(docIndex, supressWarnings: true),
    ).exists()) {
      docIndex++;
    }

    String newDocPath = await getDocumentPath(docIndex, supressWarnings: true);
    await Directory(newDocPath).create();
    return (newDocPath, docIndex);
  }

  Future<String> getDocumentPath(
    int docIndex, {
    bool supressWarnings = false,
  }) async {
    await _initializeDocumentsPath();

    String docPath =
        '$docsPath/Document ${(docIndex).toString().padLeft(4, '0')}';
    if (!Directory(docPath).existsSync() && !supressWarnings) {
      dev.log(
        "Warning, getDocumentPath: Requested Document $docIndex does not exist.",
      );
    }
    return docPath;
  }

  Future<(String, int)> _reserveNewPage(int docIndex) async {
    String docPath = await getDocumentPath(docIndex);
    int pageIndex = 0;
    while (Directory(
      '$docPath/Page ${(pageIndex).toString().padLeft(4, '0')}',
    ).existsSync()) {
      pageIndex++;
    }

    String newPagePath =
        '$docPath/Page ${(pageIndex).toString().padLeft(4, '0')}';
    Directory(newPagePath).createSync();
    return (newPagePath, pageIndex);
  }

  Future<String> getPagePath(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    String docPath = await getDocumentPath(
      docIndex,
      supressWarnings: supressWarnings,
    );
    String pagePath = '$docPath/Page ${(pageIndex).toString().padLeft(4, '0')}';
    if (!Directory(pagePath).existsSync() && !supressWarnings) {
      dev.log(
        "Warning, getPagePath: Requested directory \"$pagePath\" does not exist.",
      );
    }
    return pagePath;
  }

  Future<String> savePageVersion(
    int docIndex,
    int pageIndex,
    int versionIndex,
    Uint8List imageBytes,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(docIndex, pageIndex);
    String versionName = versionNames[versionIndex];
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.endsWith("$versionName.png")) {
        fse.delete();
      }
    }
    String versionPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$versionName.png";
    File(versionPath).writeAsBytesSync(imageBytes);
    if (!File(versionPath).existsSync()) {
      dev.log("Error, saveImage: Failed to save $versionPath");
      return "";
    }
    //dev.log("Image saved at: $toImagePath");
    return versionPath;
  }

  Future<String> savePageShape(
    int docIndex,
    int pageIndex,
    Uint8List imageBytes,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(docIndex, pageIndex);
    String fileName = "shape";
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.endsWith("$fileName.png")) {
        fse.delete();
      }
    }
    String filePath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$fileName.png";
    File(filePath).writeAsBytesSync(imageBytes);
    if (!File(filePath).existsSync()) {
      throw StateError("Error, saveImage: Failed to save $filePath");
    }
    //dev.log("Shape saved at: $filePath");
    return filePath;
  }

  Future<String> getPageShape(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(docIndex, pageIndex);
    String fileName = "shape";
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.endsWith("$fileName.png")) {
        return fse.path;
      }
    }
    if (!supressWarnings) {
      dev.log("Warning, getPageShape: No shape in page");
    }
    return "";
  }

  Future<(List<String>, int)> getDocThumbnails() async {
    await _initializeDocumentsPath();
    int docsCount = await g.filesHelper.getDocumentsCount();
    List<String> thumbnailPaths = List.generate(docsCount, (_) => "");
    for (var docIndex = 0; docIndex < docsCount; docIndex++) {
      final page0Path = await getPagePath(docIndex, 0);
      int thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        0,
        supressWarnings: true,
      );
      final thumbnailName = "thumbnail";
      final backupName = versionNames[thumbnailIndex];
      String? thumbnailPath;
      String? backupPath;
      List<FileSystemEntity> versions = [];
      try {
        versions = (Directory(page0Path).listSync()
          ..sort((a, b) => a.path.compareTo(b.path)));
      } catch (e) {
        dev.log("Error: getDocThumbnails: $e");
      }
      for (var version in versions) {
        if (version.path.contains(thumbnailName)) {
          thumbnailPath = version.path;
        } else if (version.path.contains(backupName)) {
          backupPath = version.path;
        }
      }
      if (thumbnailPath != null) {
        thumbnailPaths[docIndex] = thumbnailPath;
        if (backupPath != null) {
          imageCache.evict(FileImage(File(backupPath)), includeLive: false);
        }
      } else if (backupPath != null) {
        thumbnailPaths[docIndex] = backupPath;
      }
    }

    return (thumbnailPaths, docsCount);
  }

  Future<(List<String>, int)> getPagesThumbnails(
    int docIndex, {
    List<int> pageIndexes = const [],
    bool fullSized = false,
  }) async {
    int pagesCount;
    await _initializeDocumentsPath();
    if (pageIndexes.isEmpty) {
      pagesCount = await g.filesHelper.getPagesCount(docIndex);
      pageIndexes = List.generate(pagesCount, (index) => index);
    } else {
      pagesCount = pageIndexes.length;
    }
    List<String> thumbnailPaths = List.generate(pagesCount, (_) => "");

    for (int pageIndex in pageIndexes) {
      final pagePath = await getPagePath(docIndex, pageIndex);
      final thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        pageIndex,
        supressWarnings: true,
      );
      final thumbnailName = "thumbnail";
      final backupName = versionNames[thumbnailIndex];
      String? thumbnailPath;
      String? backupPath;
      try {
        List<FileSystemEntity> versions = Directory(pagePath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (var version in versions) {
          if (!fullSized && version.path.contains(thumbnailName)) {
            thumbnailPath = version.path;
          } else if (version.path.contains(backupName)) {
            backupPath = version.path;
          }
        }
        if (thumbnailPath != null) {
          thumbnailPaths[pageIndexes.indexOf(pageIndex)] = thumbnailPath;
          if (backupPath != null) {
            imageCache.evict(FileImage(File(backupPath)), includeLive: false);
          }
        } else if (backupPath != null) {
          thumbnailPaths[pageIndexes.indexOf(pageIndex)] = backupPath;
        }
      } catch (e) {
        dev.log("Error: getPagesThumbnails: $e");
      }
    }

    return (thumbnailPaths, pagesCount);
  }

  repairDirectoryStructure() async {
    await _initializeDocumentsPath();
    // repeat repairing until there are no more changes
    //var i = 0;
    //for (; i < 5; i++) {
    try {
      // ignore: use_build_context_synchronously
      //if (!(
      // ignore: use_build_context_synchronously
      await _deleteMarkedDeleted();
      _repairDirectoryStructure();
      //  )) break;
    } catch (e) {
      dev.log("Error, repairDirectoryStructure: $e");
    }
    //}
    //if (i == 5) {
    //  dev.log(
    //    "Warning, repairDirectoryStructure: Could not repair after $i tries.",
    //  );
    //}
  }

  Future<bool> _repairDirectoryStructure() async {
    bool anyChange = false;
    List<Future> repairFutures = [];

    List<FileSystemEntity> docs =
        Directory(docsPath).listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (var (docIndex, doc) in docs.indexed) {
      // Rename documents to match their index
      String expectedDocPath = await getDocumentPath(
        docIndex,
        supressWarnings: true,
      );
      if (doc.path != expectedDocPath) {
        dev.log("Renaming ${doc.path} -> $expectedDocPath");
        doc.renameSync(expectedDocPath);
        anyChange = true;
      }

      List<FileSystemEntity> pagesFseL =
          Directory(expectedDocPath).listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (pagesFseL.isNotEmpty) {
        for (var (pageIndex, pageFse) in pagesFseL.indexed) {
          // Reanme pages to match their index
          String expectedPagePath = await getPagePath(
            docIndex,
            pageIndex,
            supressWarnings: true,
          );
          if (pageFse.path != expectedPagePath) {
            dev.log("Renaming ${pageFse.path} -> $expectedPagePath");
            pageFse.renameSync(expectedPagePath);
            anyChange = true;
          }

          // Check if page is empty / incomplete
          List<FileSystemEntity> pageFseL = Directory(
            expectedPagePath,
          ).listSync()..sort((a, b) => a.path.compareTo(b.path));
          bool pageIncomplete = pageFseL.isEmpty;
          int countVersionsAndThumbnail = 0;
          if (!pageIncomplete) {
            for (var imageFse in pageFseL) {
              if (imageFse.path.contains("thumbnail") ||
                  versionNames.any(
                    (element) => imageFse.path.contains(element),
                  )) {
                countVersionsAndThumbnail++;
              }
            }
            // 4 versions + 1 thumbnail (ignoring shape and metadata)
            pageIncomplete = countVersionsAndThumbnail < 5;
          }

          if (pageIncomplete) {
            anyChange = true;
            bool photoExists = true;
            if (countVersionsAndThumbnail == 0) {
              dev.log("Deleting empty Doc $docIndex Page $pageIndex");
              await _deletePage(docIndex, pageIndex, isBroken: true);
            } else {
              String photoName = versionNames[0];
              for (var pageFse in Directory(
                expectedPagePath,
              ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
                if (pageFse.path.contains(photoName)) {
                  photoExists = true;
                  break;
                }
              }
              if (photoExists) {
                dev.log("Repairing Doc $docIndex Page $pageIndex");
                Future future = imageProcessingManager.repairPage(
                  docIndex,
                  pageIndex,
                );
                repairFutures.add(future);
                future.whenComplete(() {
                  repairFutures.remove(future);
                });
              } else {
                dev.log("Deleting half-empty Doc $docIndex Page $pageIndex");
                await _deletePage(docIndex, pageIndex, isBroken: true);
              }
            }
          }
        }
      } else {
        anyChange = true;
        // ignore: use_build_context_synchronously
        _deleteDocument(docIndex, isBroken: true);
      }
    }
    await Future.wait(repairFutures);
    return anyChange;
  }

  Future<void> deleteImages(
    BuildContext? context,
    int docIndex, {
    List<int> pageIndexes = const [],
  }) async {
    if (pageIndexes.isEmpty) {
      await _deleteDocument(docIndex);
    } else if (pageIndexes.length == 1) {
      await _deletePage(docIndex, pageIndexes.first);
    } else {
      await _deletePages(docIndex, pageIndexes);
    }
  }

  Future<void> _deleteDocument(
    int docIndex, {
    bool supressInfo = false,
    bool isBroken = false,
  }) async {
    String docPath = await getDocumentPath(docIndex, supressWarnings: true);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Warning, deleteDocument: Document $docIndex nonexistent, moving following Documents up",
      );
    } else {
      if (!supressInfo) {
        dev.log("deleteDocument: Deleting document directory: $docPath");
      }
      _addMarkedDeletedDoc(docIndex);
      imageProcessingManager.killIsolatesOfDocument(docIndex);

      bool deleted = false;
      Future future = imageProcessingManager
          .awaitIsolatesOfHigherIndexedDocuments(docIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!deleted) {
          Fluttertoast.showToast(msg: "Deleting Document ${docIndex + 1}...");
        }
      });
      await future;
      deleted = true;

      _removeMarkedDeletedDoc(docIndex);

      imageProcessingManager.killIsolatesOfDocument(docIndex);
      Directory(docPath).deleteSync(recursive: true);
      Fluttertoast.showToast(msg: "Document ${docIndex + 1} deleted");
    }

    // rename all with higher docIndex to close the gap
    Directory fromDirectory = Directory(
      await getDocumentPath(docIndex + 1, supressWarnings: true),
    );
    String toPath = docPath;
    for (int i = docIndex; i < await getDocumentsCount();) {
      if (fromDirectory.existsSync()) {
        dev.log("Renaming Document ${docIndex + 1} -> Document $docIndex");
        await fromDirectory.rename(toPath);
        i++;
      }

      docIndex++;
      fromDirectory = Directory(
        await getDocumentPath(docIndex + 1, supressWarnings: true),
      );
      toPath = await getDocumentPath(docIndex, supressWarnings: true);
    }
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
  }

  Future<void> _deletePage(
    int docIndex,
    int pageIndex, {
    bool isBroken = false,
  }) async {
    final pagePath = await getPagePath(docIndex, pageIndex);
    final pageDir = Directory(pagePath);
    if (!await pageDir.exists()) {
      dev.log(
        "Warning, deletePage: Document $docIndex, Page $pageIndex nonexistent, moving following Pages up",
      );
    } else {
      _addMarkedDeletedPage(docIndex, pageIndex);
      imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex);

      bool deleted = false;
      Future future = imageProcessingManager.awaitIsolatesOfHigherIndexPage(
        docIndex,
        pageIndex,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!deleted) {
          Fluttertoast.showToast(
            msg:
                "Deleting Page ${pageIndex + 1} of Document ${docIndex + 1}...",
          );
        }
      });
      await future;
      deleted = true;

      _removeMarkedDeletedPage(docIndex, pageIndex);
      dev.log("Deleting page directory: $pagePath");
      List<FileSystemEntity> files = pageDir.listSync(recursive: true);
      for (var file in files) {
        imageCache.evict(FileImage(File(file.path)), includeLive: true);
      }
      imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex);
      pageDir.deleteSync(recursive: true);
      Fluttertoast.showToast(
        msg: "Page ${pageIndex + 1} of Document ${docIndex + 1} deleted",
      );
    }

    // rename all with higher pageIndex to close the gap
    Directory fromDirectory = Directory(
      await getPagePath(docIndex, pageIndex + 1, supressWarnings: true),
    );
    String toPath = pagePath;
    for (int i = pageIndex; i < await getPagesCount(docIndex);) {
      if (fromDirectory.existsSync()) {
        dev.log(
          "Renaming Page ${pageIndex + 1} -> Page $pageIndex (in Document $docIndex)",
        );
        await fromDirectory.rename(toPath);
        i++;
      }

      pageIndex++;
      fromDirectory = Directory(
        await getPagePath(docIndex, pageIndex + 1, supressWarnings: true),
      );
      toPath = await getPagePath(docIndex, pageIndex, supressWarnings: true);
    }
    // Check if document is now empty and delete it
    if ((await getPagesCount(docIndex)) == 0) {
      dev.log("Deleting empty Document $docIndex");
      await _deleteDocument(docIndex, supressInfo: true, isBroken: true);
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
    } else {
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
      globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
    }
  }

  Future<void> _deletePages(int docIndex, List<int> pageIndexes) async {
    pageIndexes.sort();
    List<int> displayPageIndexes = [];
    for (var pageIndex in pageIndexes) {
      displayPageIndexes.add(pageIndex + 1);
    }
    pageIndexes = pageIndexes.reversed.toList();

    for (var pageIndex in pageIndexes) {
      _addMarkedDeletedPage(docIndex, pageIndex);
      imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex);
    }

    bool deleted = false;
    Future future = imageProcessingManager.awaitIsolatesOfHigherIndexPages(
      docIndex,
      pageIndexes,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!deleted) {
        Fluttertoast.showToast(
          msg:
              "Deleting Pages $displayPageIndexes of Document ${docIndex + 1}...",
        );
      }
    });
    await future;
    deleted = true;

    for (var pageIndex in pageIndexes) {
      _removeMarkedDeletedPage(docIndex, pageIndex);
    }
    // delete
    for (var pageIndex in pageIndexes) {
      final pagePath = await getPagePath(docIndex, pageIndex);
      final pageDir = Directory(pagePath);
      if (!await pageDir.exists()) {
        dev.log(
          "Warning, deletePage: Document $docIndex, Page $pageIndex nonexistent, moving following Pages up",
        );
      } else {
        dev.log("Deleting page directory: $pagePath");
        List<FileSystemEntity> files = pageDir.listSync(recursive: true);
        for (var file in files) {
          imageCache.evict(FileImage(File(file.path)), includeLive: true);
        }

        imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex);
        pageDir.deleteSync(recursive: true);
      }
    }
    Fluttertoast.showToast(
      msg: "Pages $displayPageIndexes of Document ${docIndex + 1} deleted",
    );
    // rename all with higher pageIndex to close the gap
    // ignore: use_build_context_synchronously
    await _repairDirectoryStructure();
    globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
  }

  Future<void> deleteProcessedVersionsOfPage(
    int docIndex,
    int pageIndex,
  ) async {
    String pagePath = await getPagePath(docIndex, pageIndex);
    if (!await Directory(pagePath).exists()) {
      dev.log(
        "Error, deleteProcessedVersionsOfPage: Document $docIndex, Page $pageIndex nonexistent",
      );
      return;
    }
    List<String> processedNames = ["thumbnail"];
    processedNames.addAll(versionNames.getRange(1, 4));
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      for (var name in processedNames) {
        if (fse.path.endsWith("$name.png")) {
          imageCache.evict(FileImage(File(fse.path)), includeLive: true);
          fse.delete();
          //dev.log("deleteProcessedVersionsOfPage: Deleting ${fse.path}");
        }
      }
    }
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
    globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
  }

  Future<(int, int)> createNewDocument(int pageCount) async {
    if (pageCount <= 0) return (0, 0);
    final newDoc = await _reserveNewDocument();
    int docIndex = newDoc.$2;
    int? firstPageIndex;
    for (var i = 0; i < pageCount; i++) {
      final newPage = await _reserveNewPage(docIndex);
      firstPageIndex ??= newPage.$2;
    }

    return (docIndex, firstPageIndex!);
  }

  Future<int> reserveNewPagesInDocment(int docIndex, int pageCount) async {
    if (pageCount <= 0) return 0;

    Completer afterFirst = Completer();
    Future.microtask(() async {
      await afterFirst.future;
      for (var i = 1; i < pageCount; i++) {
        _reserveNewPage(docIndex);
      }
    });
    int firstPageIndex = (await _reserveNewPage(docIndex)).$2;
    afterFirst.complete();
    return firstPageIndex;
  }

  Future<(List<String>, String, String)> getImagePathsForPage(
    int docIndex,
    int pageIndex,
  ) async {
    String pagePath = await getPagePath(docIndex, pageIndex);
    List<String> versionPaths = ["", "", "", ""];
    String shapePath = "";
    String thumbnailPath = "";
    try {
      List<FileSystemEntity> versionsFSE = (Directory(pagePath).listSync()
        ..sort((a, b) => a.path.compareTo(b.path)));
      for (var fse in versionsFSE) {
        for (var (versionIndex, versionName) in versionNames.indexed) {
          if (fse.path.contains(versionName)) {
            versionPaths[versionIndex] = fse.path;
            break;
          }
        }
        if (fse.path.contains("shape")) {
          shapePath = fse.path;
        }
        if (fse.path.contains("thumbnail")) {
          thumbnailPath = fse.path;
        }
      }
    } catch (e) {
      dev.log("Error, getImagePathsForPage: $e");
    }

    return (versionPaths, shapePath, thumbnailPath);
  }

  Future<String> getVersionPath(
    int docIndex,
    int pageIndex,
    int versionIndex, {
    bool supressWarnings = false,
  }) async {
    String pagePath = await getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: supressWarnings,
    );

    List<FileSystemEntity> versionsFSE = (Directory(pagePath).listSync()
      ..sort((a, b) => a.path.compareTo(b.path)));
    for (var fse in versionsFSE) {
      if (fse.path.contains(versionNames[versionIndex])) {
        return fse.path;
      }
    }
    return "";
  }

  changeDocumentIndex(int currentIndex, int newIndex) async {
    //int pagesCount = await getDocumentsCount();
    String currentPath = await getDocumentPath(currentIndex);
    var tmpDoc = await _reserveNewDocument();
    String tmpDocPath = tmpDoc.$1;
    //String tmpDocIndex = tmpDoc.$1;
    await Directory(currentPath).rename(tmpDocPath);
    // up or down?
    if (currentIndex < newIndex) {
      // move down
      for (
        int rollingIndex = currentIndex;
        rollingIndex < newIndex;
        rollingIndex++
      ) {
        String fromPath = await getDocumentPath(rollingIndex + 1);
        String toPath = await getDocumentPath(
          rollingIndex,
          supressWarnings: true,
        );
        await Directory(fromPath).rename(toPath);
      }
    } else {
      // move up
      for (
        int rollingIndex = currentIndex;
        rollingIndex > newIndex;
        rollingIndex--
      ) {
        String fromPath = await getDocumentPath(rollingIndex - 1);
        String toPath = await getDocumentPath(
          rollingIndex,
          supressWarnings: true,
        );
        await Directory(fromPath).rename(toPath);
      }
    }
    String newPath = await getDocumentPath(newIndex);
    await Directory(tmpDocPath).rename(newPath);
  }

  changePageIndex(int docIndex, int currentIndex, int newIndex) async {
    // pages Count
    //int pagesCount = await getPagesCount(docIndex);
    String currentPath = await getPagePath(docIndex, currentIndex);
    var tmpPage = await _reserveNewPage(docIndex);
    String tmpPath = tmpPage.$1;
    await Directory(currentPath).rename(tmpPath);
    // up or down?
    if (currentIndex < newIndex) {
      // move down
      for (
        int rollingIndex = currentIndex;
        rollingIndex < newIndex;
        rollingIndex++
      ) {
        String fromPath = await getPagePath(docIndex, rollingIndex + 1);
        String toPath = await getPagePath(
          docIndex,
          rollingIndex,
          supressWarnings: true,
        );
        await Directory(fromPath).rename(toPath);
      }
    } else {
      // move up
      for (
        int rollingIndex = currentIndex;
        rollingIndex > newIndex;
        rollingIndex--
      ) {
        String fromPath = await getPagePath(docIndex, rollingIndex - 1);
        String toPath = await getPagePath(
          docIndex,
          rollingIndex,
          supressWarnings: true,
        );
        await Directory(fromPath).rename(toPath);
      }
    }
    String newPath = await getPagePath(docIndex, newIndex);
    await Directory(tmpPath).rename(newPath);
  }

  Future<void> reversePagesOrder(int docIndex) async {
    int pagesCount = await getPagesCount(docIndex);
    String pathTmp = await getPagePath(
      docIndex,
      pagesCount,
      supressWarnings: true,
    );
    for (int pageIndex = 0; pageIndex < pagesCount ~/ 2; pageIndex++) {
      String path1 = await getPagePath(docIndex, pageIndex);
      String path2 = await getPagePath(docIndex, pagesCount - 1 - pageIndex);

      await Directory(path1).rename(pathTmp);
      await Directory(path2).rename(path1);
      await Directory(pathTmp).rename(path2);
    }
  }

  Future<int> getPageImagesCount(int docIndex, int pageIndex) async {
    final pageDir = Directory(await getPagePath(docIndex, pageIndex));
    int versionsCount = 0;
    if (pageDir.existsSync()) {
      var pageFiles = pageDir.listSync();
      for (var file in pageFiles) {
        if (file.path.endsWith(".png")) versionsCount++;
      }
    } else {
      dev.log(
        "Warning, getPageVersionsCount: '${pageDir.path}' does not exist",
      );
    }
    return versionsCount;
  }

  Future<int> getPagesCount(int docIndex) async {
    final docDir = Directory(await getDocumentPath(docIndex));
    int? pagesCount;
    if (docDir.existsSync()) {
      pagesCount = docDir.listSync().whereType<Directory>().toList().length;
    } else {
      dev.log("Warning, getPagesCount: '${docDir.path}' does not exist");
      pagesCount = 0;
    }
    return pagesCount;
  }

  Future<int> getDocumentsCount() async {
    List<Directory> dirList =
        Directory(
            await _getDocumentsPath(),
          ).listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return dirList.length;
  }

  Future<void> saveDocumentImagesToGallery(int docIndex) async {
    List<String> imagePaths = (await getPagesThumbnails(
      docIndex,
      fullSized: true,
    )).$1;
    final albumName = "Scanned Documents";

    int i = 0;
    for (String imagePath in imagePaths) {
      await Gal.putImage(imagePath, album: albumName);
      i++;
    }
    Fluttertoast.showToast(msg: 'Saved $i images in album "$albumName"');
  }

  Future<void> saveImagesToGallery(
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    List<String> imagePaths;
    if (pageIndexes.length == 1 && versionIndex != null) {
      imagePaths = [
        await getVersionPath(docIndex, pageIndexes.first, versionIndex),
      ];
    } else {
      imagePaths = (await getPagesThumbnails(
        docIndex,
        pageIndexes: pageIndexes,
        fullSized: true,
      )).$1;
    }
    if (imagePaths.isEmpty) {
      dev.log("Error, saveImagesToGallery: No images in Document $docIndex");
    }

    final albumName = "Scanned Documents";

    for (String imagePath in imagePaths) {
      await Gal.putImage(imagePath, album: albumName);
      Fluttertoast.showToast(msg: 'Saved in album "$albumName"');
    }
  }

  bool pickingImage = false;
  Future<List<String>> pickImage(
    BuildContext context,
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    if (pickingImage) return [];
    pickingImage = true;

    ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    SnackBar snackBar = SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Fetching Images...'),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
      duration: const Duration(days: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 500));
      if (context.mounted && pickingImage) {
        messenger.showSnackBar(snackBar);
      }
    });

    List<String> imagePaths = [];
    final ImagePicker picker = ImagePicker();
    final double maxWidth = 4048;
    final double maxHeight = 4048;

    if (isMultiImage) {
      final List<XFile> pickedFileList = await picker.pickMultiImage(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        requestFullMetadata: false,
      );
      for (var xfile in pickedFileList) {
        imagePaths.add(xfile.path);
      }
    } else {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        requestFullMetadata: false,
      );
      if (pickedFile != null) {
        imagePaths = [pickedFile.path];
      }
    }
    messenger.hideCurrentSnackBar();
    pickingImage = false;

    return imagePaths;
  }

  Future<pdfw.Document?> _convertImagesToPdf(
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    List<String> imagePaths;
    if (pageIndexes.length == 1 && versionIndex != null) {
      imagePaths = [
        await getVersionPath(docIndex, pageIndexes.first, versionIndex),
      ];
    } else {
      imagePaths = (await getPagesThumbnails(
        docIndex,
        pageIndexes: pageIndexes,
        fullSized: true,
      )).$1;
    }
    if (imagePaths.isEmpty) {
      dev.log("Error, _convertImagesToPdf: No images in Document $docIndex");
    }

    // Metadata
    List<double> ratioValues = [];
    if (pageIndexes.isEmpty) {
      pageIndexes = List.generate(imagePaths.length, (index) => index);
    }

    for (var pageIndex in pageIndexes) {
      ratioValues.add(
        await MetadataHelper.readPageRatioValue(docIndex, pageIndex) ??
            math.sqrt2,
      );
    }

    try {
      // Select Aspect ratio
      double width = 21.0 * pdf.PdfPageFormat.cm;
      // 1. Get common width (shared across pages)
      for (double ratioValue in ratioValues) {
        if (ratioValue == math.sqrt2) // DIN A4
        {
          width = 21.0 * pdf.PdfPageFormat.cm;
          break;
        } else if (ratioValue == 11 / 8.5 ||
            ratioValue == 14 / 8.5) // Letter / Legal
        {
          width = 8.5 * pdf.PdfPageFormat.inch;
          break;
        }
      }
      // 2. Set correct aspect ratio
      List<pdf.PdfPageFormat> pageFormats = [];
      for (var (i, ratioValue) in ratioValues.indexed) {
        late double height;
        if (versionIndex == 0) {
          final imgInfo = AppGlobals.getPngInfo(
            File(imagePaths[i]).readAsBytesSync(),
          );
          double photoRatio =
              imgInfo!.height.toDouble() / imgInfo.width.toDouble();
          height = width * photoRatio;
        } else {
          height = width * ratioValue;
        }
        pageFormats.add(pdf.PdfPageFormat(width, height));
      }

      // Create PDF
      final pdfDoc = pdfw.Document();
      for (var (i, imagePath) in imagePaths.indexed) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          final imageBytes = imageFile.readAsBytesSync();
          final image = pdfw.MemoryImage(imageBytes);

          pdfDoc.addPage(
            pdfw.Page(
              pageFormat: pageFormats[i],
              build: (pdfw.Context context) {
                return pdfw.Center(
                  child: pdfw.Image(image, fit: pdfw.BoxFit.contain),
                );
              },
            ),
          );
        }
      }

      return pdfDoc;
    } catch (e) {
      dev.log("Error, _convertImageToPdf: $e");
    }
    return null;
  }

  Future<void> pickFolderForSavingPdf(
    int docIndex,
    BuildContext context, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    if (isTmpExternal) return;
    ReceivePort port = ReceivePort();
    RootIsolateToken token = RootIsolateToken.instance!;

    ScaffoldMessengerState? messenger;
    SnackBar? snackBar;
    if (context.mounted) {
      messenger = ScaffoldMessenger.of(context);
      snackBar = SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Processing PDF...'),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ],
        ),
        duration: const Duration(days: 1),
      );
    }

    try {
      // Ask user to pick a folder
      isTmpExternal = true;
      String? selectedDirectory = await getDirectoryPath(
        confirmButtonText: "Select a Folder to Save PDF",
      );
      Future.delayed(Duration(seconds: 1), () {
        isTmpExternal = false;
      });
      if (selectedDirectory == null) {
        throw StateError('User-Action, pickFolderForDocumentPdf: cancelled');
      }

      // SnackBar
      messenger?.showSnackBar(snackBar!);
      List<int> displayPageIndexes = [];
      for (var pageIndex in pageIndexes) {
        displayPageIndexes.add(pageIndex + 1);
      }
      // Save PDF
      final String? versionName = versionIndex != null
          ? versionNames[versionIndex]
          : null;
      final String docName =
          "doc${docIndex + 1}${pageIndexes.length == 1
              ? ("_page${pageIndexes.first + 1}${versionName != null ? "_$versionName" : ""}")
              : pageIndexes.isNotEmpty
              ? "_pages${displayPageIndexes.toString()}"
              : ""}.pdf";
      final String pdfPath = "$selectedDirectory/$docName";

      final File file = File(pdfPath);
      if (file.existsSync()) {
        file.renameSync(
          "${pdfPath}_old_${DateTime.now().millisecondsSinceEpoch}",
        );
        Fluttertoast.showToast(
          msg:
              "Existing $docName renamed to ${docName}_old_${DateTime.now().millisecondsSinceEpoch}",
          toastLength: Toast.LENGTH_LONG,
        );
      }

      pdfw.Document? pdf;
      pdf = await _convertImagesToPdf(
        docIndex,
        pageIndexes: pageIndexes,
        versionIndex: versionIndex,
      );

      // Isolate
      TaskKiller killer = await IsolatesManager().runTask(
        _writePfdToPathIsolate,
        (port.sendPort, token, pdfPath, pdf),
        prio: IsolatePriority.quick,
      );

      final completer = Completer();
      port.listen((message) {
        if (message is bool) {
          if (message) {
            completer.complete(message);
            messenger?.hideCurrentSnackBar();
            // Saved Toast
            const String basePath = "/storage/emulated/0";
            final readablePath = pdfPath.startsWith(basePath)
                ? pdfPath.substring(basePath.length)
                : pdfPath;
            dev.log("PDF saved at: $readablePath");
            Fluttertoast.showToast(
              msg: "PDF saved at: $readablePath",
              toastLength: Toast.LENGTH_LONG,
            );
          } else {
            messenger?.hideCurrentSnackBar();
            messenger?.showSnackBar(
              SnackBar(content: Text("Error: No PDF available to save.")),
            );
          }
        }
        port.close();
        killer.kill();
      });
      return await completer.future;
    } catch (e) {
      dev.log("Error, pickFolderForDocumentPdf: $e");
    }
  }

  static Future<void> _writePfdToPathIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      String pdfPath,
      pdfw.Document? pdf,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    RootIsolateToken token = data.$2;
    String pdfPath = data.$3;
    pdfw.Document? pdf = data.$4;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    if (pdf != null) {
      try {
        final pdfFile = File(pdfPath);
        await pdfFile.writeAsBytes(await pdf.save());
        sendPort.send(true);
      } catch (e) {
        dev.log("Error, _writePfdToPathIsolate: $e");
      }
    } else {
      sendPort.send(false);
    }
  }

  Future<void> shareDocumentImages(BuildContext context, int docIndex) async {
    ScaffoldMessengerState? messenger;
    if (context.mounted) {
      messenger = ScaffoldMessenger.of(context);
    }
    List<String> imagePaths = (await getPagesThumbnails(
      docIndex,
      fullSized: true,
    )).$1;
    if (imagePaths.isNotEmpty) {
      shareImages(docIndex);
    } else {
      messenger?.showSnackBar(
        SnackBar(content: Text("No images available to SharePlus.")),
      );
    }
  }

  Future<void> shareImages(
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    List<String> imagePaths;
    if (pageIndexes.length == 1 && versionIndex != null) {
      imagePaths = [
        await getVersionPath(docIndex, pageIndexes.first, versionIndex),
      ];
    } else {
      imagePaths = (await getPagesThumbnails(
        docIndex,
        pageIndexes: pageIndexes,
        fullSized: true,
      )).$1;
    }
    if (imagePaths.isEmpty) {
      dev.log("Error, shareImages: No images in Document $docIndex");
    }

    List<XFile> xFiles = [];
    for (var imagePath in imagePaths) {
      xFiles.add(XFile(imagePath));
    }

    await SharePlus.instance.share(ShareParams(files: xFiles));
  }

  Future<void> shareImagesPdf(
    BuildContext context,
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    ReceivePort port = ReceivePort();
    RootIsolateToken token = RootIsolateToken.instance!;
    ScaffoldMessengerState? messenger;

    // Snackbar
    if (context.mounted) {
      messenger = ScaffoldMessenger.of(context);
    }
    SnackBar snackBar = SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Processing PDF...'),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
      duration: const Duration(days: 1),
    );
    messenger?.showSnackBar(snackBar);

    // Save PDF
    final docsDir = await _getDocumentsPath();
    final String? versionName = versionIndex != null
        ? versionNames[versionIndex]
        : null;
    String pdfPath =
        "$docsDir/doc${docIndex + 1}${pageIndexes.length == 1 ? "_page${pageIndexes.isNotEmpty ? pageIndexes.first + 1 : 1}" : ""}${versionName != null ? "_$versionName" : ""}.pdf";
    pdfw.Document? pdf = await _convertImagesToPdf(
      docIndex,
      pageIndexes: pageIndexes,
      versionIndex: versionIndex,
    );

    // Isolate
    TaskKiller killer = await IsolatesManager().runTask(
      _writePfdToPathIsolate,
      (port.sendPort, token, pdfPath, pdf),
      prio: IsolatePriority.immediate,
    );

    final completer = Completer();
    port.listen((message) async {
      if (message is bool) {
        if (message) {
          messenger?.hideCurrentSnackBar();
          completer.complete(message);
          await SharePlus.instance.share(ShareParams(files: [XFile(pdfPath)]));
          File(pdfPath).delete();
        } else {
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            SnackBar(content: Text("Error: No PDF available to SharePlus.")),
          );
        }
      }
      port.close();
      killer.kill();
    });
    return await completer.future;
  }

  static Future<String> rotateImageInTmpDir(
    String imagePath,
    int rotationIn,
  ) async {
    final port = ReceivePort();
    final tmpDir = await getTemporaryDirectory();
    final rotatedFilePath = "${tmpDir.path}/rotated_$rotationIn.png";

    if (!File(rotatedFilePath).existsSync()) {
      IsolatesManager().runTask(_rotateImageInTmpDirIsolate, (
        port.sendPort,
        imagePath,
        rotatedFilePath,
        rotationIn,
        g,
      ), prio: IsolatePriority.immediate);
      await port.first;
      port.close();
    }

    return rotatedFilePath;
  }

  static Future<void> _rotateImageInTmpDirIsolate(
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
    String imagePath = data.$2;
    String rotatedFilePath = data.$3;
    int angle = data.$4;
    AppGlobals gIn = data.$5;

    OpenCVHelper cvHelper = OpenCVHelper(gIn);
    Uint8List rotatedBytes = cvHelper.rotateImage(imagePath, angle);
    File(rotatedFilePath).writeAsBytesSync(rotatedBytes);
    sendPort.send(true);
  }

  static Future<void> deleteCachedRoatedImages() async {
    List<String> paths = [];
    final tmpDir = await getTemporaryDirectory();
    for (var angle = 90; angle <= 270; angle += 90) {
      paths.add("${tmpDir.path}/rotated_$angle.png");
    }
    _deleteImages(paths);
  }

  static Future<void> _deleteImages(List<String> paths) async {
    List<Future<void>> futures = [];
    for (var path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        imageCache.evict(FileImage(File(path)), includeLive: true);
        futures.add(file.delete(recursive: true));
      }
    }
    await Future.wait(futures);
  }

  Future<List<(int?, int?)>> pickPdfToDoc({int? addToDocWithIndex}) async {
    final List<(int?, int?)> indexPairsList = [];
    if (isTmpExternal) return indexPairsList;
    // User picks PDF
    final pdfType = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    isTmpExternal = true;
    final xFiles = await openFiles(acceptedTypeGroups: [pdfType]);
    Future.delayed(Duration(seconds: 1), () {
      isTmpExternal = false;
    });
    if (xFiles.isEmpty) {
      dev.log("User-Error, pickPdfToDocument: cancelled");
      return indexPairsList;
    }
    // Process multiple PDFs
    for (var xFile in xFiles) {
      final docData = await pdfToDoc(
        xFile.path,
        addToDocWithIndex: addToDocWithIndex,
      );
      addToDocWithIndex = (addToDocWithIndex != null)
          ? addToDocWithIndex++
          : null;
      indexPairsList.add((docData.$1, docData.$2));
    }
    return indexPairsList;
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
    // Process delayed
    Future.microtask(() async {
      await Future.delayed(Duration(milliseconds: 100));
      _savePdfAsPage(firstPageIndex, pageCount, doc, docIndex);
      // Creation Date
      final now = DateTime.now();
      final newDate = "${now.year}-${now.month}-${now.day}";
      g.metadataHelper.writeDocDate(docIndex, newDate, supressWarnings: true);
    });
    return (docIndex, firstPageIndex);
  }

  Future<void> _savePdfAsPage(
    int firstPageIndex,
    int pageCount,
    pdfr.PdfDocument doc,
    int docIndex,
  ) async {
    int pagesProcessed = 0;
    for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
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
      final renderedPage = await page.render(
        width: (page.width * limitingScale * dpiScale).toInt(),
        height: (page.height * limitingScale * dpiScale).toInt(),
      );
      // -> Uint8List
      final ui.Image uiImage = await renderedPage.createImageDetached();
      final ByteData? byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List pngBytes = byteData!.buffer.asUint8List();
      // Processing
      imageProcessingManager.processPdfPage(
        docIndex,
        pageIndex + firstPageIndex,
        pngBytes,
      );
      // Cleanup
      pagesProcessed++;
      if (pagesProcessed == pageCount) {
        doc.dispose();
      }
    }
  }
}
