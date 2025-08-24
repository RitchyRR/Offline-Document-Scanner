import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:developer' as dev;
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:path/path.dart' as p;
import 'package:docscanner/ffi/opencv_bindings.dart' as cvb;
import 'package:easy_localization/easy_localization.dart' show tr, NumberFormat;
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
import '../main.dart'
    show globalNotifier, imageProcessingManager, isTmpExternal, versionNames;
import 'metadata_helper.dart';
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

  Future<void> _addMarkedDeletedPage(int docIndex, int pageIndex) async {
    while (_markedDeletedPages.length <= docIndex) {
      _markedDeletedPages.add([]);
    }
    if (_markedDeletedPages[docIndex].contains(pageIndex)) return;
    _markedDeletedPages[docIndex].add(pageIndex);
    _markedDeletedPages[docIndex].sort();
    _markedDeletedPages[docIndex] = _markedDeletedPages[docIndex].reversed
        .toList();
    // prefs
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_markedDeletedPages);
    await prefs.setString("markedDeletedPages", jsonString);
    // signal
    globalNotifier.triggerEvent(NotifierEvent.imagesDeleted);
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

  Future<void> _addMarkedDeletedDoc(int docIndex) async {
    if (_markedDeletedDocs.contains(docIndex)) return;
    _markedDeletedDocs.add(docIndex);
    List<int> tmp = _markedDeletedDocs.toList();
    tmp.sort();
    _markedDeletedDocs.clear();
    _markedDeletedDocs.addAll(tmp.reversed.toList());
    // prefs
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_markedDeletedDocs);
    await prefs.setString("markedDeletedDocs", jsonString);
    // signal
    globalNotifier.triggerEvent(NotifierEvent.imagesDeleted);
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

  Future<String> writeImageRaw(
    int docIndex,
    int pageIndex,
    int versionIndex,
    String sourcePath, {
    AppGlobals? gIn,
  }) async {
    gIn ??= g;

    await _initializeDocumentsPath();
    String versionPath = await gIn.filesHelper.createVersionPath(
      docIndex,
      pageIndex,
      versionIndex,
    );
    // Delete existing Image
    String pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    String versionName = versionNamesInternal[versionIndex];
    for (var fse in Directory(
      pagePath,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.contains("$versionName.")) {
        fse.delete();
      }
    }

    // Save version (Scale down if too large)
    final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
    bool scaledAndSaved = imageProcessor.scaleImageToMaxSize(
      sourcePath,
      versionPath,
    );
    final tmpPath =
        '$pagePath/tmp_${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}';
    if (!scaledAndSaved) await File(sourcePath).copy(tmpPath);
    await File(tmpPath).rename(versionPath);
    imageProcessor.dispose();

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
    // Delete existing Image
    if (Directory(pagePath).existsSync()) {
      for (var fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("$versionName.")) {
          fse.deleteSync();
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
    //final imgInfo = await AppGlobals.getImageBytesInfo(
    //  imageBytes,
    //  imageExtension,
    //);
    final Uint8List compressedPngBytes =
        await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: AppGlobals.maxPhotoSize,
          minHeight: AppGlobals.maxPhotoSize,
          format: CompressFormat.png,
          quality: 1,
        );
    // Save
    File(versionPath).writeAsBytesSync(compressedPngBytes);
    if (!File(versionPath).existsSync()) {
      throw StateError("Error, savePageVersion: Failed to save $versionPath");
    }
    return versionPath;
  }

  Future<bool> deleteExistingVersion(
    int docIndex,
    int pageIndex,
    int versionIndex,
  ) async {
    bool deleted = false;
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: true,
    );
    String versionName = versionNamesInternal[versionIndex];
    // Delete existing Image
    if (Directory(pagePath).existsSync()) {
      for (var fse in Directory(
        pagePath,
      ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
        if (fse.path.contains("$versionName.")) {
          fse.deleteSync();
          deleted = true;
        }
      }
    } else {
      throw StateError(
        "Error, savePageVersion: pagePath $pagePath does not exist",
      );
    }
    return deleted;
  }

  Future<String> createVersionPath(
    int docIndex,
    int pageIndex,
    int versionIndex,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(
      docIndex,
      pageIndex,
      supressWarnings: true,
    );
    String versionName = versionNamesInternal[versionIndex];
    String versionPath =
        "$pagePath/${DateTime.now().millisecondsSinceEpoch}_$versionName.png";

    return versionPath;
  }

  Future<(List<String>, int)> getDocThumbnails() async {
    await _initializeDocumentsPath();
    final List<int> deletedDocs = _markedDeletedDocs.toList();
    int docsCount = await g.filesHelper.getDocumentsCount();
    List<String> thumbnailPaths = List.generate(docsCount, (_) => "");
    for (var docIndex = 0; docIndex < docsCount; docIndex++) {
      if (deletedDocs.contains(docIndex)) continue;
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
    // Init
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
    // Find Thumbnails for Pages
    for (int pageIndex in pageIndexes) {
      final pagePath = await getPagePath(docIndex, pageIndex);
      final thumbnailIndex = await MetadataHelper.readPageThumbnailIndex(
        docIndex,
        pageIndex,
        supressWarnings: true,
      );
      final versionName = thumbnailIndex != null
          ? versionNamesInternal[thumbnailIndex]
          : null;
      if (versionName == null) continue;
      final thumbnailName = "thumbnail";
      // Find Thumbnail or versionName Image
      String? thumbnailPath;
      String? backupPath;
      try {
        List<FileSystemEntity> versions = Directory(pagePath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (var version in versions) {
          if (!fullSized && version.path.contains(thumbnailName)) {
            thumbnailPath = version.path;
          } else if (version.path.contains(versionName) &&
              !version.path.contains(thumbnailName)) {
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

  repairAll() async {
    StackTrace? stackTrace = StackTrace.current;
    await _initializeDocumentsPath();
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
          changeHappened = await _repairAll();
          // Give Stacktrace if repair happened
          if (changeHappened && stackTrace != null) {
            dev.log("repairAll, $stackTrace");
            stackTrace = null;
          }
        } else {
          break;
        }
      } catch (e) {
        throw StateError("Error, repairAll: $e");
      }
    }
    if (i == 5) {
      dev.log("Warning, repairAll: Could not repair after $i tries.");
    }
    imageProcessingManager.compressAll();
  }

  Future<bool> _repairAll() async {
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
        if (Directory(expectedDocPath).existsSync()) {
          await Directory(expectedDocPath).delete(recursive: true);
        }
        doc.renameSync(expectedDocPath);
        anyChange = true;
      }

      List<FileSystemEntity> pagesFseL =
          Directory(expectedDocPath).listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (pagesFseL.isNotEmpty) {
        for (var (pageIndex, pageFse) in pagesFseL.indexed) {
          bool isImportedPdf = await MetadataHelper.readPageImportedPdf(
            docIndex,
            pageIndex,
            supressWarnings: true,
          );

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
            dev.log("Warning, _repairAll: $e");
          }
          bool pageIncomplete = pageFseL.isEmpty;
          int countVersionsAndThumbnail = 0;
          if (!pageIncomplete) {
            List<String>? oldVersionFileNames =
                await MetadataHelper.readOldPageFileNames(
                  docIndex,
                  pageIndex,
                  supressWarnings: true,
                );
            oldVersionFileNames = oldVersionFileNames
                ?.where((element) => element != "")
                .toList();
            oldVersionFileNames =
                oldVersionFileNames == null || oldVersionFileNames.isEmpty
                ? null
                : oldVersionFileNames;
            for (var imageFse in pageFseL) {
              if (imageFse.path.contains("thumbnail") ||
                  versionNamesInternal.any(
                    (element) => imageFse.path.contains(element),
                  )) {
                countVersionsAndThumbnail++;
              } else if (!imageFse.path.endsWith("metadata.json")) {
                dev.log(
                  "Info, _repairAll: Deleting unrecognized file: $imageFse.path",
                );
                File(imageFse.path).deleteSync();
              }
              if (oldVersionFileNames != null) {
                for (var oldName in oldVersionFileNames) {
                  if (imageFse.path.contains(oldName)) {
                    countVersionsAndThumbnail--;
                    break;
                  }
                }
              }
            }

            pageIncomplete = isImportedPdf
                ? countVersionsAndThumbnail !=
                      2 // photo + thumbnail
                : countVersionsAndThumbnail <
                      versionNamesInternal.length + 1; // versions +  thumbnail
          }

          if (pageIncomplete) {
            anyChange = true;
            bool photoExists = true;
            if (countVersionsAndThumbnail <= 0 || isImportedPdf) {
              dev.log("Deleting empty page, Doc $docIndex Page $pageIndex");
              await _deletePage(docIndex, pageIndex, supressInfo: true);
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
                await _deletePage(docIndex, pageIndex, supressInfo: true);
              }
            }
          }
        }
      } else {
        anyChange = true;
        // ignore: use_build_context_synchronously
        _deleteDocument(docIndex, supressInfo: true);
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
    } else {
      await _deletePages(docIndex, pageIndexes);
    }
  }

  Future<void> _deleteDocument(int docIndex, {bool supressInfo = false}) async {
    String docPath = await getDocumentPath(docIndex, supressWarnings: true);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Warning, deleteDocument: Document $docIndex nonexistent, moving following Documents up",
      );
    } else {
      dev.log("deleteDocument: Starting deleting document directory: $docPath");
      Future markDeletedFuture = _addMarkedDeletedDoc(docIndex);
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
      Future higherIndexedDocsFuture = imageProcessingManager
          .awaitIsolatesOfHigherIndexedDocuments(docIndex);
      await markDeletedFuture;
      await killFuture;
      await imageProcessingManager.pdfProcessingFutures[docIndex];
      await higherIndexedDocsFuture;
    }

    final docsCount = await getDocumentsCount();
    // delete
    if (Directory(docPath).existsSync()) {
      await Directory(docPath).delete(recursive: true);
      dev.log("deleteDocument: Deleted document directory: $docPath");
    }
    // rename all with higher docIndex to close the gap
    for (int i = docIndex; i + 1 < docsCount; i++) {
      Directory fromDirectory = Directory(
        await getDocumentPath(i + 1, supressWarnings: true),
      );
      String toPath = await getDocumentPath(i, supressWarnings: true);
      if (fromDirectory.existsSync()) {
        dev.log("Renaming Document ${i + 1} -> Document $i");
        await fromDirectory.rename(toPath);
        i++;
      }
    }
    await _removeMarkedDeletedDoc(docIndex);
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
  }

  Future<void> _deletePage(
    int docIndex,
    int pageIndex, {
    bool supressInfo = false,
  }) async {
    _deletePages(docIndex, [pageIndex], supressInfo: supressInfo);
  }

  Future<void> _deletePages(
    int docIndex,
    List<int> deletePageIndexes, {
    bool supressInfo = false,
  }) async {
    final oldPagesCount = await getPagesCount(docIndex);
    if (deletePageIndexes.isEmpty) return;
    deletePageIndexes.sort();
    List<int> displayPageIndexes = [];
    for (var pageIndex in deletePageIndexes) {
      displayPageIndexes.add(pageIndex + 1);
    }
    deletePageIndexes = deletePageIndexes.reversed.toList();

    // Show deleted in Frontend
    // Kill Isolates of Pages
    List<Future<void>> markDeletedFutures = [];
    List<Future<void>> killFutures = [];
    for (var pageIndex in deletePageIndexes) {
      markDeletedFutures.add(_addMarkedDeletedPage(docIndex, pageIndex));
      killFutures.add(
        imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex),
      );
    }
    if (!supressInfo) {
      Fluttertoast.showToast(
        msg: tr(
          "toast.pagesDeleted",
          namedArgs: {
            "docIndex": "${docIndex + 1}",
            "pageIndexes": "$displayPageIndexes",
          },
        ),
      );
    }
    dev.log("_deletePages: Starting deleting Pages: $deletePageIndexes");

    // Await Isolates
    Future higherIndexedPagesFuture = imageProcessingManager
        .awaitIsolatesOfHigherIndexPages(docIndex, deletePageIndexes);
    await Future.wait(markDeletedFutures);
    await Future.wait(killFutures);
    await imageProcessingManager.pdfProcessingFutures[docIndex];
    await higherIndexedPagesFuture;

    // Delete
    List<String> deletedPagePaths = [];
    for (var (i, deletePageIndex) in deletePageIndexes.indexed) {
      deletedPagePaths.add(await getPagePath(docIndex, deletePageIndex));
      final deletePageDir = Directory(deletedPagePaths[i]);
      if (!deletePageDir.existsSync()) {
        dev.log(
          "Warning, deletePage: Document $docIndex, Page $deletePageIndex nonexistent, moving following Pages up",
        );
      } else {
        for (var file in deletePageDir.listSync(recursive: true)) {
          imageCache.evict(FileImage(File(file.path)), includeLive: true);
        }
        // Delete
        deletePageDir.deleteSync(recursive: true);
        dev.log("_deletePages: Deleted page directory: ${deletedPagePaths[i]}");
      }
    }

    // Rename all with higher pageIndex to close the gap
    List<Future> removeMarkedDeletetedFutures = [];
    final newPagesCount = await getPagesCount(docIndex);
    List<String> moveTo = [];
    for (
      var pageIndex = deletePageIndexes.last;
      pageIndex < oldPagesCount;
      pageIndex++
    ) {
      Directory pageDir = Directory(
        await getPagePath(docIndex, pageIndex, supressWarnings: true),
      );
      if (pageDir.existsSync()) {
        dev.log(
          "Renaming Page $pageIndex -> ${moveTo.first} (in Document $docIndex)",
        );
        if (Directory(moveTo.first).existsSync()) {
          await Directory(moveTo.first).delete(recursive: true);
        }
        await pageDir.rename(moveTo.removeAt(0));
        moveTo.add(pageDir.path);
        removeMarkedDeletetedFutures.add(
          _removeMarkedDeletedPage(docIndex, pageIndex),
        );
      } else {
        moveTo.add(pageDir.path);
      }
    }
    await Future.wait(removeMarkedDeletetedFutures);

    // Check if document is now empty and delete it
    if (newPagesCount == 0) {
      dev.log("Deleting empty Document $docIndex");
      await _deleteDocument(docIndex, supressInfo: true);
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
    } else {
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
      globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnails);
    }
  }

  Future<(int, int)> createNewDocument(
    int pageCount, {
    bool importedPdf = false,
  }) async {
    if (pageCount <= 0) return (0, 0);
    final newDoc = await _reserveNewDocument();
    int docIndex = newDoc.$2;
    int? firstPageIndex;
    for (var i = 0; i < pageCount; i++) {
      final newPage = await _reserveNewPage(docIndex);
      if (importedPdf) {
        MetadataHelper.writePageImportedPdf(docIndex, newPage.$2, true);
      }
      firstPageIndex ??= newPage.$2;
    }

    return (docIndex, firstPageIndex!);
  }

  Future<int> reserveNewPagesInDocment(
    int docIndex,
    int pageCount, {
    bool importedPdf = false,
  }) async {
    if (pageCount <= 0) return 0;

    Completer afterFirst = Completer();
    Future.microtask(() async {
      await afterFirst.future;
      for (var i = 1; i < pageCount; i++) {
        int pageIndex;
        (_, pageIndex) = await _reserveNewPage(docIndex);
        if (importedPdf) {
          MetadataHelper.writePageImportedPdf(docIndex, pageIndex, true);
        }
      }
    });
    int firstPageIndex = (await _reserveNewPage(docIndex)).$2;
    afterFirst.complete();
    return firstPageIndex;
  }

  Future<(List<String>, String)> getImagePathsForPage(
    int docIndex,
    int pageIndex,
  ) async {
    String pagePath = await getPagePath(docIndex, pageIndex);
    List<String> versionPaths = List.generate(
      versionNamesInternal.length,
      (_) => "",
    );
    String thumbnailPath = "";
    try {
      List<FileSystemEntity> versionsFSE = (Directory(pagePath).listSync()
        ..sort((a, b) => a.path.compareTo(b.path)));
      for (var fse in versionsFSE) {
        for (var (versionIndex, versionName) in versionNamesInternal.indexed) {
          if (fse.path.contains(versionName) &&
              !fse.path.contains("thumbnail")) {
            versionPaths[versionIndex] = fse.path;
            break;
          }
        }
        if (fse.path.contains("thumbnail")) {
          thumbnailPath = fse.path;
        }
      }
    } catch (e) {
      throw StateError("Error, getImagePathsForPage: $e");
    }

    return (versionPaths, thumbnailPath);
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
        if (fse.path.contains(versionNamesInternal[versionIndex]) &&
            !fse.path.contains("thumbnail")) {
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

  moveDocumentIndex(int currentIndex, int newIndex) async {
    String currentPath = await getDocumentPath(currentIndex);
    String tmpDocPath;
    (tmpDocPath, _) = await _reserveNewDocument();
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
    String newPath = await getDocumentPath(newIndex, supressWarnings: true);
    await Directory(tmpDocPath).rename(newPath);
  }

  movePageIndex(int docIndex, int currentIndex, int newIndex) async {
    String currentPath = await getPagePath(docIndex, currentIndex);
    String tmpPagePath;
    (tmpPagePath, _) = await _reserveNewPage(docIndex);
    await Directory(currentPath).rename(tmpPagePath);
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
    String newPath = await getPagePath(
      docIndex,
      newIndex,
      supressWarnings: true,
    );
    await Directory(tmpPagePath).rename(newPath);
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
    int? maxDpi,
    bool useSameWidth = false,
  }) async {
    // DPI Scaling
    List<String> imagePaths;
    (imagePaths, _) = await imageProcessingManager.scaleImagesToMaxDpi(
      docIndex,
      pageIndexes,
      versionIndex,
      maxDpi,
    );

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

    // DPI Scaling Delete
    if (maxDpi != null) {
      deleteCachedScaledImages();
    }
  }

  bool pickingImage = false;
  Future<(List<String>, ScaffoldMessengerState?)> pickImage(
    BuildContext context,
    ImageSource source,
  ) async {
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
    final double maxWidth = AppGlobals.maxPhotoSize.toDouble();
    final double maxHeight = AppGlobals.maxPhotoSize.toDouble();

    final List<XFile> pickedFileList = await picker.pickMultiImage(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      requestFullMetadata: false,
      limit: 20,
    );
    for (var xfile in pickedFileList) {
      imagePaths.add(xfile.path);
    }

    pickingImage = false;
    return (imagePaths, messenger);
  }

  Future<(List<int>, List<double>)> getPdfPageDpis(
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    List<String> imagePaths = await getImagePaths(
      pageIndexes,
      versionIndex,
      docIndex,
    );

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

    /// Aspect ratio

    // 0. Default (localized)
    const double widthA4 = 21.0 * pdf.PdfPageFormat.cm;
    const double heightA4 = 29.7 * pdf.PdfPageFormat.cm;
    const double widthLetterLegal = 8.5 * pdf.PdfPageFormat.inch;
    const double heightLetter = 11 * pdf.PdfPageFormat.inch;

    String? country;
    try {
      final Locale deviceLocale = ui.PlatformDispatcher.instance.locale;
      country = deviceLocale.countryCode;
    } catch (e) {
      dev.log("Error, getPdfPageDpis: deviceLocale not available");
    }
    final bool imperial;
    const imperialCountries = {"US", "LR", "MM"}; // USA, Liberia, Myanmar
    if (country != null && imperialCountries.contains(country)) {
      imperial = true;
    } else {
      imperial = false;
    }

    // 1. Get common widths (shared across pages)
    final List<double> physicalWidths = [];
    const double tolerance = 0.001;
    for (double? ratioValue in ratioValues) {
      // DIN A4
      if (ratioValue == math.sqrt2) {
        physicalWidths.add(widthA4);
      } else if (ratioValue != null &&
          ratioValue <= math.sqrt1_2 + tolerance &&
          ratioValue >= math.sqrt1_2 - tolerance) {
        physicalWidths.add(heightA4);
      }
      // Letter / Legal
      else if (ratioValue == 11 / 8.5 || ratioValue == 14 / 8.5) {
        physicalWidths.add(widthLetterLegal);
      } else if (ratioValue == 8.5 / 11) {
        physicalWidths.add(11 * pdf.PdfPageFormat.inch);
      } else if (ratioValue == 8.5 / 14) {
        physicalWidths.add(14 * pdf.PdfPageFormat.inch);
      }
      // Fallback: localized default
      else if (ratioValue != null && ratioValue < 1.0) {
        physicalWidths.add(imperial ? heightLetter : heightA4);
      } else {
        physicalWidths.add(imperial ? widthLetterLegal : widthA4);
      }
    }

    // 2. Select Width
    final List<double> widthsInInches;
    widthsInInches = List.generate(
      physicalWidths.length,
      (index) => physicalWidths[index] / pdf.PdfPageFormat.inch,
    );

    // Image Info
    List<DecodeInfo> imageInfos = [];
    for (var path in imagePaths) {
      if (path.isNotEmpty) {
        imageInfos.add((await AppGlobals.getImageInfo(path))!);
      }
    }

    List<int> dpis = [];
    for (var i = 0; i < imageInfos.length; i++) {
      dpis.add((imageInfos[i].width / widthsInInches[i]).toInt());
    }
    return (dpis, widthsInInches);
  }

  Future<pdfw.Document?> _convertImagesToPdf(
    final int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
    int? maxDpi,
    bool useSameWidth = false,
  }) async {
    // DPI Scaling
    List<String> imagePaths;
    List<double> widthsInInches;
    (imagePaths, widthsInInches) = await imageProcessingManager
        .scaleImagesToMaxDpi(docIndex, pageIndexes, versionIndex, maxDpi);

    // Page Formats (Aspect Ratio, physical Size etc.)
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

    // Aspect Ratio
    if (useSameWidth) {
      const double widthA4 =
          21.0 * pdf.PdfPageFormat.cm / pdf.PdfPageFormat.inch;
      const double heightA4 =
          29.7 * pdf.PdfPageFormat.cm / pdf.PdfPageFormat.inch;
      const double widthLetterLegal = 8.5;
      const double heightLetter = 11;

      String? country;
      try {
        final Locale deviceLocale = ui.PlatformDispatcher.instance.locale;
        country = deviceLocale.countryCode;
      } catch (e) {
        dev.log("Error, getPdfPageDpis: deviceLocale not available");
      }
      final bool imperial;
      const imperialCountries = {"US", "LR", "MM"}; // USA, Liberia, Myanmar
      if (country != null && imperialCountries.contains(country)) {
        imperial = true;
      } else {
        imperial = false;
      }

      final double sharedWidth;
      if (widthsInInches.contains(imperial ? widthLetterLegal : widthA4)) {
        sharedWidth = imperial ? widthLetterLegal : widthA4;
      } else if (widthsInInches.contains(imperial ? heightLetter : heightA4)) {
        sharedWidth = imperial ? heightLetter : heightA4;
      } else {
        sharedWidth = widthA4;
      }
      widthsInInches = [sharedWidth];
    }

    // 2. Set correct aspect ratio
    List<pdf.PdfPageFormat> pageFormats = [];
    for (var (i, ratioValue) in ratioValues.indexed) {
      final double physicalWidth = useSameWidth
          ? widthsInInches.first * pdf.PdfPageFormat.inch
          : widthsInInches[i] * pdf.PdfPageFormat.inch;
      double? physicalHeight;
      if (versionIndex == 0) {
        // Calculate ratio for photo
        DecodeInfo? imageInfo = await AppGlobals.getImageInfo(imagePaths[i]);
        if (imageInfo != null) {
          double photoRatio =
              imageInfo.height.toDouble() / imageInfo.width.toDouble();
          physicalHeight = physicalWidth * photoRatio;
        }
      }
      physicalHeight ??= physicalWidth * (ratioValue ?? math.sqrt2);
      pageFormats.add(pdf.PdfPageFormat(physicalWidth, physicalHeight));
    }

    try {
      // Create PDF
      final pdfDoc = pdfw.Document();
      for (var (i, imagePath) in imagePaths.indexed) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          Uint8List pngBytes = imageFile.readAsBytesSync();
          pdfDoc.addPage(
            pdfw.Page(
              pageFormat: pageFormats[i],
              build: (pdfw.Context context) {
                return pdfw.Center(
                  child: pdfw.Image(
                    pdfw.MemoryImage(pngBytes),
                    fit: pdfw.BoxFit.contain,
                  ),
                );
              },
            ),
          );
        }
      }

      // DPI Scaling Delete
      if (maxDpi != null) {
        deleteCachedScaledImages();
      }

      return pdfDoc;
    } catch (e) {
      // DPI Scaling Delete
      if (maxDpi != null) {
        deleteCachedScaledImages();
      }
      throw StateError("Error, _convertImagesToPdf: $e");
    }
  }

  Future<List<String>> getImagePaths(
    List<int> pageIndexes,
    int? versionIndex,
    int docIndex,
  ) async {
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
        "Error, _getImagePaths: No images in Document $docIndex",
      );
    }
    return imagePaths;
  }

  Future<void> savePdfToDirectoy(
    int docIndex,
    BuildContext context, {
    List<int> pageIndexes = const [],
    int? versionIndex,
    int? maxDpi,
    bool useSameWidth = false,
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

    // PDF Name
    String docFileName = await _generateFileName(
      docIndex,
      pageIndexes,
      versionIndex,
      ".pdf",
    );

    // SnackBar
    messenger?.showSnackBar(snackBar!);

    // Save PDF
    pdfw.Document? pdf;
    pdf = await _convertImagesToPdf(
      docIndex,
      pageIndexes: pageIndexes,
      versionIndex: versionIndex,
      maxDpi: maxDpi,
      useSameWidth: useSameWidth,
    );
    // Ask user to pick a folder
    isTmpExternal = true;
    String? pdfPath;
    if (pdf != null) {
      try {
        pdfPath = await FilePicker.platform.saveFile(
          fileName: docFileName,
          type: FileType.custom,
          allowedExtensions: ["pdf"],
          bytes: await pdf.save(),
        );
      } catch (e) {
        dev.log("Error, pickFolderForDocumentPdf: $e");
        messenger?.hideCurrentSnackBar();
        isTmpExternal = false;
        throw StateError("Error, pickFolderForDocumentPdf: $e");
      }
      if (pdfPath == null) {
        dev.log("User-Action, pickFolderForDocumentPdf: cancelled");
        messenger?.hideCurrentSnackBar();
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
    Future.delayed(Duration(seconds: 1), () {
      isTmpExternal = false;
    });

    // Saved Toast
    const String basePath = "/document/primary:";
    final int filenamePos = pdfPath.lastIndexOf("/");
    final String readablePath = pdfPath.startsWith(basePath)
        ? pdfPath.substring(basePath.length, filenamePos)
        : pdfPath;
    dev.log("PDF saved at: $readablePath");
    Fluttertoast.showToast(
      msg: tr("toast.pdfSaved", namedArgs: {"path": readablePath}),
      toastLength: Toast.LENGTH_LONG,
    );
  }

  Future<List<int>> getImagesFilesizes(
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
    List<String> imagePaths = await getImagePaths(
      pageIndexes,
      versionIndex,
      docIndex,
    );
    List<int> imagesBytes = [];
    for (var imagePath in imagePaths) {
      if (imagePath.isNotEmpty) {
        imagesBytes.add(File(imagePath).lengthSync());
      }
    }
    return imagesBytes;
  }

  String formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    double size = bytes.toDouble();
    final Locale deviceLocale = ui.PlatformDispatcher.instance.locale;

    for (int i = 0; i < suffixes.length; i++) {
      double nextSize = size / 1024;
      if (nextSize < 1) {
        final formatter = NumberFormat.decimalPatternDigits(
          locale: deviceLocale.toString(),
          decimalDigits: decimals,
        );
        // \u{202F} = Narrow no-break space, \u{u00A0} = No-break space
        return "${formatter.format(size)}\u{202F}${suffixes[i]}";
      }
      size = nextSize;
    }
    final formatter = NumberFormat.decimalPatternDigits(
      locale: deviceLocale.toString(),
      decimalDigits: decimals,
    );
    return "${formatter.format(size)}\u{202F}TB";
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
    int? maxDpi,
    bool useSameWidth = false,
  }) async {
    // DPI Scaling
    List<String> imagePaths;
    (imagePaths, _) = await imageProcessingManager.scaleImagesToMaxDpi(
      docIndex,
      pageIndexes,
      versionIndex,
      maxDpi,
    );

    List<XFile> xFiles = [];
    for (var (pageIndex, imagePath) in imagePaths.indexed) {
      final extension = imagePath.split(".").last;
      final newName = await _generateFileName(
        docIndex,
        [pageIndex],
        versionIndex,
        ".$extension",
      );
      final renamedPath = imagePath.replaceFirst(RegExp(r"[^/]+$"), newName);
      await File(imagePath).copy(renamedPath);
      xFiles.add(XFile(renamedPath));
    }

    await SharePlus.instance.share(ShareParams(files: xFiles));
    for (var renamedFile in xFiles) {
      File(renamedFile.path).delete();
    }
    // DPI Scaling Delete
    if (maxDpi != null) {
      deleteCachedScaledImages();
    }
  }

  static Future<void> deleteCachedScaledImages() async {
    final tmpDir = await getTemporaryDirectory();
    for (var fse
        in tmpDir.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (fse.path.startsWith("${tmpDir.path}/scaled_")) {
        fse.deleteSync();
      }
    }
  }

  Future<void> sharePdf(
    BuildContext context,
    int docIndex, {
    List<int> pageIndexes = const [],
    int? versionIndex,
    int? maxDpi,
    bool useSameWidth = false,
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
      maxDpi: maxDpi,
      useSameWidth: useSameWidth,
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

  static Future<void> deleteImagePaths(List<String> paths) async {
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
    FilePickerResult? filePickerResult;
    try {
      filePickerResult = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ["pdf"],
      );
    } catch (e) {
      dev.log("Error, pickPdfToDocument: $e");
      isTmpExternal = false;
      throw StateError("Error, pickPdfToDocument: $e");
    }

    if (filePickerResult == null) {
      dev.log("User-Error, pickPdfToDocument: cancelled");
      isTmpExternal = false;
      return indexPairsList;
    }
    List<File> pickedFiles = filePickerResult.paths
        .map((path) => File(path!))
        .toList();
    if (pickedFiles.isEmpty) {
      dev.log("User-Error, pickPdfToDocument: cancelled");
      isTmpExternal = false;
      return indexPairsList;
    }
    // Process multiple PDFs
    for (var file in pickedFiles) {
      final docData = await imageProcessingManager.importPdf(
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
