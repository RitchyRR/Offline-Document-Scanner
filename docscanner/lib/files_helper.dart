import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:developer' as dev;

import 'package:easy_localization/easy_localization.dart' show tr;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' show DecodeInfo;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
// images:
import 'package:flutter_image_compress/flutter_image_compress.dart'
    show FlutterImageCompress, CompressFormat;
// pdf:
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pdfw;
// isolates:
import 'dart:isolate' show ReceivePort, SendPort, Isolate;
import 'isolates_manager.dart';
// my packages:
import 'image_prosessing_manager.dart';
import 'main.dart'
    show globalNotifier, imageProcessingManager, isTmpExternal, versionNames;
import 'metadata_helper.dart';
import 'opencv_helper.dart';
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
    if (jsonString != null && jsonString != "" && jsonString != "[]") {
      decoded = (jsonDecode(jsonString) as List<dynamic>)
          .map<List<int>>((e) => List<int>.from(e as List))
          .toList();
    }
    _markedDeletedPages.clear();
    _markedDeletedPages.addAll(decoded);
    if (_markedDeletedPages.length <= docIndex) return [];
    return _markedDeletedPages[docIndex];
  }

  void _addMarkedDeletedPage(int docIndex, int pageIndex) async {
    while (_markedDeletedPages.length <= docIndex) {
      _markedDeletedPages.add([]);
    }
    if (_markedDeletedPages[docIndex].contains(pageIndex)) return;
    _markedDeletedPages[docIndex].add(pageIndex);
    _markedDeletedPages[docIndex].sort();
    _markedDeletedPages[docIndex] = _markedDeletedPages[docIndex].reversed
        .toList();
    globalNotifier.triggerEvent(NotifierEvent.imagesDeleted);
    // prefs
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_markedDeletedPages);
    await prefs.setString("markedDeletedPages", jsonString);
  }

  Future<void> _removeMarkedDeletedPage(int docIndex, int pageIndex) async {
    while (_markedDeletedPages.length <= docIndex) {
      _markedDeletedPages.add([]);
    }
    //while (_markedDeletedPages[docIndex].contains(pageIndex)) {}
    _markedDeletedPages[docIndex].remove(pageIndex);
    // prefs
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_markedDeletedPages);
    prefs.setString("markedDeletedPages", jsonString);
  }

  Future<List<int>> getMarkedDeletedDocs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("markedDeletedDocs");
    List<int> decoded = _markedDeletedDocs;
    if (jsonString != null && jsonString != "" && jsonString != "[]") {
      decoded = (jsonDecode(jsonString) as List<dynamic>).cast<int>();
    }
    _markedDeletedDocs.clear();
    _markedDeletedDocs.addAll(decoded);
    return _markedDeletedDocs;
  }

  void _addMarkedDeletedDoc(int docIndex) async {
    if (_markedDeletedDocs.contains(docIndex)) return;
    _markedDeletedDocs.add(docIndex);
    List<int> tmp = _markedDeletedDocs;
    tmp.sort();
    _markedDeletedDocs.clear();
    _markedDeletedDocs.addAll(tmp.reversed.toList());
    globalNotifier.triggerEvent(NotifierEvent.imagesDeleted);
    // prefs
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_markedDeletedDocs);
    await prefs.setString("markedDeletedDocs", jsonString);
  }

  Future<void> _removeMarkedDeletedDoc(int docIndex) async {
    _markedDeletedDocs.remove(docIndex);
    // prefs
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_markedDeletedDocs);
    prefs.setString("markedDeletedDocs", jsonString);
  }

  Future<void> _deleteMarkedDeleted() async {
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
    docsPath = "${baseDir.path}/Documents";
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
        "$docsPath/Document ${(docIndex).toString().padLeft(4, "0")}";
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
      "$docPath/Page ${(pageIndex).toString().padLeft(4, "0")}",
    ).existsSync()) {
      pageIndex++;
    }

    String newPagePath =
        "$docPath/Page ${(pageIndex).toString().padLeft(4, "0")}";
    await Directory(newPagePath).create(recursive: true);
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
    String pagePath = "$docPath/Page ${(pageIndex).toString().padLeft(4, "0")}";
    if (!Directory(pagePath).existsSync() && !supressWarnings) {
      dev.log(
        "Warning, getPagePath: Requested directory \"$pagePath\" does not exist.",
      );
    }
    return pagePath;
  }

  (Uint8List, String) readImageRaw(String imagePath) {
    final file = File(imagePath);
    final Uint8List futureBytes = file.readAsBytesSync();
    String extension = imagePath.split(".").last;
    return (futureBytes, extension);
  }

  Future<String> writeImageRaw(
    int docIndex,
    int pageIndex,
    int versionIndex,
    Uint8List imageBytes,
    String extension,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: true,
    );
    String versionName = versionNamesInternal[versionIndex];
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.contains("$versionName.")) {
        fse.delete();
      }
    }
    String versionPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$versionName.$extension";
    // Write
    await File(versionPath).writeAsBytes(imageBytes);
    if (!File(versionPath).existsSync()) {
      throw StateError("Error, writeImageRaw: Failed to save to $versionPath");
    }
    return versionPath;
  }

  Future<String> savePageVersion(
    int docIndex,
    int pageIndex,
    int versionIndex,
    Uint8List imageBytes,
    String imageExtension,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: true,
    );
    String versionName = versionNamesInternal[versionIndex];
    // Delete prior Version
    if (Directory(pagePath).existsSync()) {
      for (var fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("$versionName.")) {
          fse.delete();
        }
      }
    } else {
      throw StateError(
        "Error, savePageVersion: pagePath $pagePath does not exist",
      );
    }
    String versionPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$versionName.png";
    // Compress
    final imgInfo = await AppGlobals.getImageBytesInfo(
      imageBytes,
      imageExtension,
    );
    final Uint8List compressedPngBytes =
        await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: imgInfo!.width,
          minHeight: imgInfo.height,
          format: CompressFormat.png,
          quality: 100,
        );
    // Save
    File(versionPath).writeAsBytesSync(compressedPngBytes);
    if (!File(versionPath).existsSync()) {
      throw StateError("Error, savePageVersion: Failed to save $versionPath");
    }
    return versionPath;
  }

  Future<String> savePageShape(
    int docIndex,
    int pageIndex,
    Uint8List pngBytes,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(docIndex, pageIndex);
    String fileName = "shape";
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.contains("$fileName.")) {
        fse.delete();
      }
    }
    String filePath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$fileName.png";
    File(filePath).writeAsBytesSync(pngBytes);
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
      if (fse.path.contains("$fileName.")) {
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
      int? thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        0,
        supressWarnings: true,
      );
      final thumbnailName = "thumbnail";
      final backupName = thumbnailIndex != null
          ? versionNamesInternal[thumbnailIndex]
          : null;
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
        } else if (backupName != null && version.path.contains(backupName)) {
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
    bool supressWarnings = false,
  }) async {
    int pagesCount;
    await _initializeDocumentsPath();
    if (pageIndexes.isEmpty) {
      pagesCount = await g.filesHelper.getPagesCount(
        docIndex,
        supressWarnings: supressWarnings,
      );
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
      final backupName = thumbnailIndex != null
          ? versionNamesInternal[thumbnailIndex]
          : null;
      String? thumbnailPath;
      String? backupPath;
      try {
        List<FileSystemEntity> versions = Directory(pagePath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (var version in versions) {
          if (!fullSized && version.path.contains(thumbnailName)) {
            thumbnailPath = version.path;
          } else if (backupName != null && version.path.contains(backupName)) {
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
        dev.log("Warning: getPagesThumbnails: $e");
      }
    }

    return (thumbnailPaths, pagesCount);
  }

  repairDirectoryStructure() async {
    await _initializeDocumentsPath();
    // repeat repairing until there are no more changes
    var i = 0;
    bool deletedMarked = false;
    bool changeHappened = true;
    for (; i < 5; i++) {
      try {
        if (!deletedMarked) {
          await _deleteMarkedDeleted();
          deletedMarked = true;
        }
        if (changeHappened == true) {
          changeHappened = await _repairDirectoryStructure();
        } else {
          break;
        }
      } catch (e) {
        throw StateError("Error, repairDirectoryStructure: $e");
      }
    }
    if (i == 5) {
      dev.log(
        "Warning, repairDirectoryStructure: Could not repair after $i tries.",
      );
    }
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
          List<FileSystemEntity> pageFseL = [];
          try {
            pageFseL = Directory(expectedPagePath).listSync()
              ..sort((a, b) => a.path.compareTo(b.path));
          } catch (e) {
            dev.log("Warning, _repairDirectoryStructure: $e");
          }
          bool pageIncomplete = pageFseL.isEmpty;
          int countVersionsAndThumbnail = 0;
          if (!pageIncomplete) {
            for (var imageFse in pageFseL) {
              if (imageFse.path.contains("thumbnail") ||
                  versionNamesInternal.any(
                    (element) => imageFse.path.contains(element),
                  )) {
                countVersionsAndThumbnail++;
              }
            }
            // versions + 1 for thumbnail (ignoring shape and metadata)
            pageIncomplete =
                countVersionsAndThumbnail < versionNamesInternal.length + 1;
          }

          if (pageIncomplete) {
            anyChange = true;
            bool photoExists = true;
            if (countVersionsAndThumbnail == 0) {
              dev.log("Deleting empty Doc $docIndex Page $pageIndex");
              await _deletePage(docIndex, pageIndex, isBroken: true);
            } else {
              String photoName = versionNamesInternal[0];
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
      dev.log("deleteDocument: Starting deleting document directory: $docPath");
      _addMarkedDeletedDoc(docIndex);
      if (!supressInfo) {
        Fluttertoast.showToast(
          msg: tr(
            "toast.docDeleted",
            namedArgs: {"docIndex": "${docIndex + 1}"},
          ),
        );
      }

      Future killFuture = imageProcessingManager.killIsolatesOfDocument(
        docIndex,
      );
      Future future = imageProcessingManager
          .awaitIsolatesOfHigherIndexedDocuments(docIndex);
      await killFuture;
      await future;
      await imageProcessingManager.pdfProcessingFutures[docIndex];

      Directory(docPath).deleteSync(recursive: true);
      dev.log("deleteDocument: Deleted document directory: $docPath");
      await _removeMarkedDeletedDoc(docIndex);
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
      dev.log("_deletePage: Starting deleting page directory: $pagePath");
      _addMarkedDeletedPage(docIndex, pageIndex);
      Fluttertoast.showToast(
        msg: tr(
          "toast.pageDeleted",
          namedArgs: {
            "docIndex": "${docIndex + 1}",
            "pageIndex": "${pageIndex + 1}",
          },
        ),
      );

      Future killFuture = imageProcessingManager.killIsolatesOfPage(
        docIndex,
        pageIndex,
      );
      Future future = imageProcessingManager.awaitIsolatesOfHigherIndexPage(
        docIndex,
        pageIndex,
      );
      await killFuture;
      await future;
      await imageProcessingManager.pdfProcessingFutures[docIndex];

      if (pageDir.existsSync()) {
        List<FileSystemEntity> files = pageDir.listSync(recursive: true);
        for (var file in files) {
          imageCache.evict(FileImage(File(file.path)), includeLive: true);
        }
        pageDir.deleteSync(recursive: true);
      }
      dev.log("Deleted page directory: $pagePath");
      _removeMarkedDeletedPage(docIndex, pageIndex);
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

    List<Future<void>> killFutures = [];
    for (var pageIndex in pageIndexes) {
      _addMarkedDeletedPage(docIndex, pageIndex);
      killFutures.add(
        imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex),
      );
    }
    Fluttertoast.showToast(
      msg: tr(
        "toast.pagesDeleted",
        namedArgs: {
          "docIndex": "${docIndex + 1}",
          "pageIndexes": "$displayPageIndexes",
        },
      ),
    );
    dev.log("_deletePages: Starting deleting Pages: $pageIndexes");

    Future future = imageProcessingManager.awaitIsolatesOfHigherIndexPages(
      docIndex,
      pageIndexes,
    );
    await Future.wait(killFutures);
    await future;
    await imageProcessingManager.pdfProcessingFutures[docIndex];

    // delete
    for (var pageIndex in pageIndexes) {
      final pagePath = await getPagePath(docIndex, pageIndex);
      final pageDir = Directory(pagePath);
      if (!await pageDir.exists()) {
        dev.log(
          "Warning, deletePage: Document $docIndex, Page $pageIndex nonexistent, moving following Pages up",
        );
      } else {
        List<FileSystemEntity> files = pageDir.listSync(recursive: true);
        for (var file in files) {
          imageCache.evict(FileImage(File(file.path)), includeLive: true);
        }

        pageDir.deleteSync(recursive: true);
        dev.log("_deletePages: Deleted page directory: $pagePath");
        _removeMarkedDeletedPage(docIndex, pageIndex);
      }
    }
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
      throw StateError(
        "Error, deleteProcessedVersionsOfPage: Document $docIndex, Page $pageIndex nonexistent",
      );
    }
    List<String> processedNames = ["thumbnail"];
    processedNames.addAll(
      versionNamesInternal.getRange(1, versionNamesInternal.length),
    );
    try {
      for (var fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        for (var name in processedNames) {
          if (fse.path.contains("$name.")) {
            imageCache.evict(FileImage(File(fse.path)), includeLive: true);
            fse.delete();
            //dev.log("deleteProcessedVersionsOfPage: Deleting ${fse.path}");
          }
        }
      }
    } catch (e) {
      dev.log("Warning, deleteProcessedVersionsOfPage: Could not delete: $e");
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
    List<String> versionPaths = List.generate(
      versionNamesInternal.length,
      (_) => "",
    );
    String shapePath = "";
    String thumbnailPath = "";
    try {
      List<FileSystemEntity> versionsFSE = (Directory(pagePath).listSync()
        ..sort((a, b) => a.path.compareTo(b.path)));
      for (var fse in versionsFSE) {
        for (var (versionIndex, versionName) in versionNamesInternal.indexed) {
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
      throw StateError("Error, getImagePathsForPage: $e");
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

    try {
      List<FileSystemEntity> versionsFSE = (Directory(pagePath).listSync()
        ..sort((a, b) => a.path.compareTo(b.path)));
      for (var fse in versionsFSE) {
        if (fse.path.contains(versionNamesInternal[versionIndex])) {
          return fse.path;
        }
      }
    } catch (e) {
      if (!supressWarnings) {
        dev.log("Warning, getVersionPath failed: $e");
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
      var pageFiles = pageDir.listSync().whereType<File>();
      for (var file in pageFiles) {
        if (!file.path.endsWith(".json")) versionsCount++;
      }
    } else {
      dev.log("Warning, getPageVersionsCount: ${pageDir.path} does not exist");
    }
    return versionsCount;
  }

  Future<int> getPagesCount(
    int docIndex, {
    bool supressWarnings = false,
  }) async {
    final docDir = Directory(
      await getDocumentPath(docIndex, supressWarnings: true),
    );
    int? pagesCount;
    if (docDir.existsSync()) {
      pagesCount = docDir.listSync().whereType<Directory>().toList().length;
    } else {
      if (!supressWarnings) {
        dev.log("Warning, getPagesCount: ${docDir.path} does not exist");
      }
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
      throw StateError(
        "Error, saveImagesToGallery: No images in Document $docIndex",
      );
    }

    final albumName = "Scanned Documents";
    for (var (pageIndex, imagePath) in imagePaths.indexed) {
      final extension = imagePath.split(".").last;
      final newName = await _generateFileName(
        docIndex,
        [pageIndex],
        versionIndex,
        ".$extension",
      );
      final renamedPath = imagePath.replaceFirst(RegExp(r"[^/]+$"), newName);
      final renamedFile = await File(imagePath).copy(renamedPath);
      await Gal.putImage(renamedPath, album: albumName);
      await Fluttertoast.showToast(
        msg: tr("toast.imageSaved", namedArgs: {"albumName": albumName}),
      );
      await renamedFile.delete();
    }
  }

  bool pickingImage = false;
  Future<(List<String>, ScaffoldMessengerState?)> pickImage(
    BuildContext context,
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    if (pickingImage) return (<String>[], null);
    pickingImage = true;

    ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    SnackBar snackBar = SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr("loading.importingImages")),
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
        limit: 20,
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

    pickingImage = false;
    return (imagePaths, messenger);
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
      throw StateError(
        "Error, _convertImagesToPdf: No images in Document $docIndex",
      );
    }

    // Metadata
    List<double?> ratioValues = [];
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
      for (double? ratioValue in ratioValues) {
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
      // Image Info
      List<DecodeInfo> imageInfos = [];
      for (var path in imagePaths) {
        imageInfos.add((await AppGlobals.getImageInfo(path))!);
      }
      // 2. Set correct aspect ratio
      List<pdf.PdfPageFormat> pageFormats = [];
      for (var (i, ratioValue) in ratioValues.indexed) {
        late double height;
        if (versionIndex == 0) {
          double photoRatio =
              imageInfos[i].height.toDouble() / imageInfos[i].width.toDouble();
          height = width * photoRatio;
        } else {
          height = width * (ratioValue ?? math.sqrt2);
        }
        pageFormats.add(pdf.PdfPageFormat(width, height));
      }

      // Create PDF
      final pdfDoc = pdfw.Document();
      for (var (i, imagePath) in imagePaths.indexed) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          final Uint8List? pngBytes =
              await FlutterImageCompress.compressWithFile(
                imagePath,
                minWidth: imageInfos[i].width,
                minHeight: imageInfos[i].height,
                format: CompressFormat.png,
                quality: 100,
              );

          pdfDoc.addPage(
            pdfw.Page(
              pageFormat: pageFormats[i],
              build: (pdfw.Context context) {
                return pdfw.Center(
                  child: pdfw.Image(
                    pdfw.MemoryImage(pngBytes!),
                    fit: pdfw.BoxFit.contain,
                  ),
                );
              },
            ),
          );
        }
      }

      return pdfDoc;
    } catch (e) {
      throw StateError("Error, _convertImagesToPdf: $e");
    }
  }

  Future<void> pickFolderForSavingPdf(
    int docIndex,
    BuildContext context, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    if (isTmpExternal) return;

    ScaffoldMessengerState? messenger;
    SnackBar? snackBar;
    if (context.mounted) {
      messenger = ScaffoldMessenger.of(context);
      snackBar = SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr("loading.processingPdf")),
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
      // PDF Name
      String docFileName = await _generateFileName(
        docIndex,
        pageIndexes,
        versionIndex,
        ".pdf",
      );

      Future.delayed(Duration(seconds: 1), () {
        isTmpExternal = false;
      });
      // SnackBar
      messenger?.showSnackBar(snackBar!);

      // Save PDF
      pdfw.Document? pdf;
      pdf = await _convertImagesToPdf(
        docIndex,
        pageIndexes: pageIndexes,
        versionIndex: versionIndex,
      );
      // Ask user to pick a folder
      isTmpExternal = true;
      String? pdfPath;
      if (pdf != null) {
        try {
          pdfPath = await FilePicker.platform.saveFile(
            fileName: docFileName,
            dialogTitle: "Select a Folder to save the PDF to", //todo tr
            allowedExtensions: ["pdf"],
            bytes: await pdf.save(),
          );
        } catch (e) {
          dev.log("Error, pickFolderForDocumentPdf: $e");
          isTmpExternal = false;
          throw StateError("Error, pickFolderForDocumentPdf: $e");
        }
        if (pdfPath == null) {
          dev.log("User-Action, pickFolderForDocumentPdf: cancelled");
          isTmpExternal = false;
          return;
        }
      } else {
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(content: Text(tr("snackbar.e_savePdf"))),
        );
        isTmpExternal = false;
        return;
      }

      messenger?.hideCurrentSnackBar();
      // Saved Toast
      const String basePath = "/storage/emulated/0";
      final readablePath = pdfPath.startsWith(basePath)
          ? pdfPath.substring(basePath.length)
          : pdfPath;
      dev.log("PDF saved at: $readablePath");
      Fluttertoast.showToast(
        msg: tr("toast.pdfSaved", namedArgs: {"path": readablePath}),
        toastLength: Toast.LENGTH_LONG,
      );
    } catch (e) {
      throw StateError("Error, pickFolderForDocumentPdf: $e");
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
        SnackBar(content: Text(tr("snackbar.e_shareImages"))),
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
      throw StateError("Error, shareImages: No images in Document $docIndex");
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
    final port = ReceivePort();
    final token = RootIsolateToken.instance!;
    ScaffoldMessengerState? messenger;

    // Snackbar
    if (context.mounted) {
      messenger = ScaffoldMessenger.of(context);
    }
    SnackBar snackBar = SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr("loading.processingPdf")),
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
    // PDF Name
    String docFileName = await _generateFileName(
      docIndex,
      pageIndexes,
      versionIndex,
      ".pdf",
    );
    final String pdfPath = "$docsDir/$docFileName";
    pdfw.Document? pdf = await _convertImagesToPdf(
      docIndex,
      pageIndexes: pageIndexes,
      versionIndex: versionIndex,
    );

    // Isolate
    await IsolatesManager().runTask(
      _writePfdToInternalPathIsolate,
      (port.sendPort, token, pdfPath, pdf),
      portIn: port,
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
            SnackBar(content: Text(tr("snackbar.e_sharePdf"))),
          );
        }
      }
    });
    return await completer.future;
  }

  static Future<void> _writePfdToInternalPathIsolate(
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
        sendPort.send(false);
        throw StateError("Error, _writePfdToInternalPathIsolate: $e");
      }
    } else {
      sendPort.send(false);
    }
    Isolate.exit();
  }

  Future<String> _generateFileName(
    int docIndex,
    List<int> pageIndexes,
    int? versionIndex,
    String extension,
  ) async {
    List<int> displayPageIndexes = [];
    for (var pageIndex in pageIndexes) {
      displayPageIndexes.add(pageIndex + 1);
    }
    bool isWholeDoc = false;
    if (pageIndexes.isEmpty ||
        pageIndexes.length == await g.filesHelper.getPagesCount(docIndex)) {
      isWholeDoc = true;
    }
    String docName =
        await g.metadataHelper.readDocName(docIndex) ??
        tr("documents.docIndex", namedArgs: {"docIndex": "${docIndex + 1}"});
    final String? versionName = versionIndex != null
        ? versionNames[versionIndex]
        : null;
    final String docFileName =
        "$docName${pageIndexes.length == 1
            ? ", ${tr("pages.pageIndex", namedArgs: {"pageIndex": "${pageIndexes.first + 1}"})}${versionName != null ? ", $versionName" : ""}"
            : !isWholeDoc
            ? ", $displayPageIndexes"
            : ""}$extension";
    return docFileName;
  }

  static Future<String> rotateImageInTmpDir(
    String imagePath,
    int rotationIn,
  ) async {
    final port = ReceivePort();
    final tmpDir = await getTemporaryDirectory();
    final rotatedFilePath = "${tmpDir.path}/rotated_$rotationIn.png";

    if (!File(rotatedFilePath).existsSync()) {
      //RootIsolateToken token = RootIsolateToken.instance!;
      IsolatesManager().runTask(
        _rotateImageInTmpDirIsolate,
        (
          port.sendPort,
          //token,
          imagePath,
          rotatedFilePath,
          rotationIn,
          g,
        ),
        portIn: port,
        prio: IsolatePriority.immediate,
      );
      await port.first;
    }

    return rotatedFilePath;
  }

  static Future<void> _rotateImageInTmpDirIsolate(
    (
      SendPort sendPort,
      //RootIsolateToken token,
      String imagePath,
      String rotatedFilePath,
      int angle,
      AppGlobals gIn,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    //RootIsolateToken token = data.$2;
    String imagePath = data.$2;
    String rotatedFilePath = data.$3;
    int angle = data.$4;
    AppGlobals gIn = data.$5;
    //BackgroundIsolateBinaryMessenger.ensureInitialized(token);

    OpenCVHelper cvHelper = OpenCVHelper(gIn);
    Uint8List imageBytes = await File(imagePath).readAsBytes();
    Uint8List rotatedBytes = await cvHelper.rotateImage(imageBytes, angle);
    File(rotatedFilePath).writeAsBytesSync(rotatedBytes);
    Isolate.exit(sendPort, true);
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
    isTmpExternal = true;
    FilePickerResult? filePickerResult = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      allowedExtensions: ["pdf"],
    );
    if (filePickerResult == null) {
      dev.log("User-Error, pickPdfToDocument: cancelled");
      isTmpExternal = false;
      return indexPairsList;
    }
    List<File> pickedFiles = filePickerResult.paths
        .map((path) => File(path!))
        .toList();
    //final pdfType = XTypeGroup(label: "PDF", extensions: ["pdf"]);
    //final xFiles = await openFiles(acceptedTypeGroups: [pdfType]);
    if (pickedFiles.isEmpty) {
      dev.log("User-Error, pickPdfToDocument: cancelled");
      isTmpExternal = false;
      return indexPairsList;
    }
    // Process multiple PDFs
    for (var file in pickedFiles) {
      final docData = await imageProcessingManager.pdfToDoc(
        file.path,
        addToDocWithIndex: addToDocWithIndex,
      );
      addToDocWithIndex = (addToDocWithIndex != null)
          ? addToDocWithIndex++
          : null;
      indexPairsList.add((docData.$1, docData.$2));
    }
    Future.microtask(() async {
      for (var element in indexPairsList) {
        await imageProcessingManager.pdfProcessingFutures[element.$1];
      }
      isTmpExternal = false;
    });
    return indexPairsList;
  }

  Future<void> exportErrorLog() async {
    // Get internal log file
    final docDir = await getApplicationDocumentsDirectory();
    final logFile = File("${docDir.path}/error_log.txt");

    if (!await logFile.exists()) {
      Fluttertoast.showToast(msg: "No log file found.");
      return;
    }

    // Let user pick folder
    final now = DateTime.now().millisecondsSinceEpoch;
    final fileName = "error_log_$now.txt";

    isTmpExternal = true;
    final String? filePath = await FilePicker.platform.saveFile(
      fileName: fileName,
      dialogTitle: "Select Error-Log Folder",
      bytes: logFile.readAsBytesSync(),
    );
    if (filePath == null) {
      Fluttertoast.showToast(msg: "Saving Error Log cancelled");
      isTmpExternal = false;
      return;
    }
    Future.delayed(Duration(seconds: 1), () {
      isTmpExternal = false;
    });

    // Save externally
    Fluttertoast.showToast(msg: "Log at: $filePath");
  }
}
