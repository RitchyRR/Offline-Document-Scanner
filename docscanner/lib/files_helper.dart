import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:docscanner/image_prosessing_manager.dart';
import 'package:docscanner/main.dart';
import 'package:docscanner/opencv_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as dev;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdfw;
//import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

class FilesHelper {
  late String docsPath = "";
  int screenWidth;

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
      await getDocumentPath(docIndex, supressWarning: true),
    ).exists()) {
      docIndex++;
    }

    String newDocPath = await getDocumentPath(docIndex, supressWarning: true);
    await Directory(newDocPath).create();
    return (newDocPath, docIndex);
  }

  Future<String> getDocumentPath(
    int docIndex, {
    bool supressWarning = false,
  }) async {
    await _initializeDocumentsPath();

    String docPath = '$docsPath/Document $docIndex';
    if (!Directory(docPath).existsSync() && !supressWarning) {
      dev.log(
        "Warning, getDocumentPath: Requested Document $docIndex does not exist.",
      );
    }
    return docPath;
  }

  Future<(String, int)> _reserveNewPage(int docIndex) async {
    String documentPath = await getDocumentPath(docIndex);
    int pageIndex = 0;
    while (await Directory('$documentPath/Page $pageIndex').exists()) {
      pageIndex++;
    }

    String newPagePath = '$documentPath/Page $pageIndex';
    await Directory(newPagePath).create();
    return (newPagePath, pageIndex);
  }

  Future<String> getPagePath(
    int docIndex,
    int pageIndex, {
    bool supressWarning = false,
  }) async {
    String documentPath = await getDocumentPath(docIndex);
    String pagePath = '$documentPath/Page $pageIndex';
    if (!Directory(pagePath).existsSync() && !supressWarning) {
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
    SendPort? sendPort,
  ) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(docIndex, pageIndex);
    String versionName = versionNames[versionIndex];
    for (var fse in Directory(pagePath).listSync()) {
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
    if (sendPort != null) {
      switch (versionIndex) {
        case 0:
          sendPort.send(NotifierEvent.pictureSaved);
          break;
        case 1:
          sendPort.send(NotifierEvent.warpSaved);
          break;
        case 2:
          sendPort.send(NotifierEvent.processed1Saved);
          break;
        case 3:
          sendPort.send(NotifierEvent.processed2Saved);
          break;
        default:
      }
    } else if (versionIndex == 0) {
      globalNotifier.triggerEvent(NotifierEvent.pictureSaved);
    }
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
    for (var fse in Directory(pagePath).listSync()) {
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
    bool supresswarning = false,
  }) async {
    await _initializeDocumentsPath();
    String pagePath = await getPagePath(docIndex, pageIndex);
    String fileName = "shape";
    for (var fse in Directory(pagePath).listSync()) {
      if (fse.path.endsWith("$fileName.png")) {
        return fse.path;
      }
    }
    if (!supresswarning) {
      dev.log("Warning, getPageShape: No shape in page");
    }
    return "";
  }

  Future<(List<String>, int)> getDocThumbnails() async {
    await _initializeDocumentsPath();
    int docsCount = await filesHelper.getDocumentsCount();
    List<String> thumbnailPaths = List.generate(docsCount, (_) => "");
    for (var docIndex = 0; docIndex < docsCount; docIndex++) {
      final page0Path = await getPagePath(docIndex, 0);
      int thumbnailIndex = await ImageProcessingManager.readPageThumbnailIndex(
        docIndex,
        0,
        supressWarning: true,
      );
      final thumbnailName = "thumbnail";
      final backupName = versionNames[thumbnailIndex];
      String? thumbnailPath;
      String? backupPath;
      List<FileSystemEntity> versions = [];
      try {
        versions =
            (Directory(page0Path).listSync()
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
      pagesCount = await filesHelper.getPagesCount(docIndex);
      pageIndexes = List.generate(pagesCount, (index) => index);
    } else {
      pagesCount = pageIndexes.length;
    }
    List<String> thumbnailPaths = List.generate(pagesCount, (_) => "");

    for (int pageIndex in pageIndexes) {
      final pagePath = await getPagePath(docIndex, pageIndex);
      final thumbnailIndex =
          await ImageProcessingManager.readPageThumbnailIndex(
            docIndex,
            pageIndex,
            supressWarning: true,
          );
      final thumbnailName = "thumbnail";
      final backupName = versionNames[thumbnailIndex];
      String? thumbnailPath;
      String? backupPath;
      try {
        List<FileSystemEntity> versions = Directory(pagePath).listSync();
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

  Future<void> repairDirectoryStructure(BuildContext? context) async {
    await _initializeDocumentsPath();
    // repeat repairing until there are no more changes
    var i = 0;
    for (; i < 5; i++) {
      try {
        // ignore: use_build_context_synchronously
        if (!(await _repairDirectoryStructure(context))) break;
      } catch (e) {
        dev.log("Error, repairDirectoryStructure: $e");
      }
    }
    if (i == 5) {
      dev.log(
        "Warning, repairDirectoryStructure: Could not repair after $i tries.",
      );
    }
  }

  Future<bool> _repairDirectoryStructure(BuildContext? context) async {
    bool anyChange = false;
    List<Future<void>> repairFutures = [];

    List<FileSystemEntity> docs =
        Directory(docsPath).listSync().whereType<Directory>().toList();
    for (var (docIndex, doc) in docs.indexed) {
      // Rename documents to match their index
      String expectedDocPath = await getDocumentPath(
        docIndex,
        supressWarning: true,
      );
      if (doc.path != expectedDocPath) {
        dev.log("Renaming ${doc.path} -> $expectedDocPath");
        doc.renameSync(expectedDocPath);
        anyChange = true;
      }

      List<FileSystemEntity> pages =
          Directory(expectedDocPath).listSync().whereType<Directory>().toList();
      if (pages.isNotEmpty) {
        for (var (pageIndex, pageFse) in pages.indexed) {
          // Reanme pages to match their index
          String expectedPagePath = await getPagePath(
            docIndex,
            pageIndex,
            supressWarning: true,
          );
          if (pageFse.path != expectedPagePath) {
            dev.log("Renaming ${pageFse.path} -> $expectedPagePath");
            pageFse.renameSync(expectedPagePath);
            anyChange = true;
          }

          // Delete empty pages
          int versionCount = await getPageImagesCount(docIndex, pageIndex);

          // versions + thumbnail + shape
          if (versionCount < versionNames.length + 2) {
            anyChange = true;
            bool photoExists = false;
            if (versionCount == 0) {
              dev.log("Deleting empty Doc $docIndex Page $pageIndex");
            } else {
              String photoName = versionNames[0];
              for (var pageFse in Directory(expectedPagePath).listSync()) {
                if (pageFse.path.contains(photoName)) {
                  photoExists = true;
                  break;
                }
              }
              if (photoExists) {
                dev.log("Repairing Doc $docIndex Page $pageIndex");
              } else {
                dev.log("Deleting half-empty Doc $docIndex Page $pageIndex");
              }
            }
            if (!photoExists) {
              // ignore: use_build_context_synchronously
              await deletePage(context, docIndex, pageIndex, isBroken: true);
              // Info: If deletePage() results in empty Documents,
              //       deletePage() will delete these Documents
            } else {
              repairFutures.add(
                imageProcessingManager.repairPage(docIndex, pageIndex),
              );
            }
          }
        }
      } else {
        anyChange = true;
        // ignore: use_build_context_synchronously
        deleteDocument(context, docIndex, isBroken: true);
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
      deleteDocument(context, docIndex);
    } else {
      for (var pageIndex in pageIndexes) {
        deletePage(context, docIndex, pageIndex);
      }
    }
  }

  Future<void> deleteDocument(
    BuildContext? context,
    int docIndex, {
    bool supressInfo = false,
    bool isBroken = false,
  }) async {
    ScaffoldMessengerState? messenger;
    SnackBar? snackBar;
    bool cancelDelete = false;
    if (context != null) {
      messenger = ScaffoldMessenger.of(context);
      snackBar = SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Deleting Document ${docIndex + 1}...'),
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
        action:
            isBroken
                ? null
                : SnackBarAction(
                  label: 'Cancel',
                  onPressed: () {
                    cancelDelete = true;
                  },
                ),
      );
    }
    String docPath = await getDocumentPath(docIndex, supressWarning: true);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Warning, deleteDocument: Document $docIndex nonexistent, moving following Documents up",
      );
    } else {
      if (!supressInfo) {
        dev.log("deleteDocument: Deleting document directory: $docPath");
      }

      messenger?.showSnackBar(snackBar!);
      await imageProcessingManager.awaitIsolatesOfHigherIndexedDocuments(
        docIndex,
      );
      messenger?.hideCurrentSnackBar();
      if (cancelDelete) return;

      imageProcessingManager.killIsolatesOfDocument(docIndex);
      Directory(docPath).deleteSync(recursive: true);
      Fluttertoast.showToast(msg: "Document ${docIndex + 1} deleted");
    }

    // rename all with higher docIndex to close the gap
    Directory fromDirectory = Directory(
      await getDocumentPath(docIndex + 1, supressWarning: true),
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
        await getDocumentPath(docIndex + 1, supressWarning: true),
      );
      toPath = await getDocumentPath(docIndex, supressWarning: true);
    }
    globalNotifier.triggerEvent(
      NotifierEvent.loadDocsThumbnails,
    ); // to not show deleted document
  }

  Future<void> deletePage(
    BuildContext? context,
    int docIndex,
    int pageIndex, {
    bool isBroken = false,
  }) async {
    ScaffoldMessengerState? messenger;
    SnackBar? snackBar;
    bool cancelDelete = false;
    if (context != null) {
      messenger = ScaffoldMessenger.of(context);
      snackBar = SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Deleting Document ${docIndex + 1}...'),
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
        action:
            isBroken
                ? null
                : SnackBarAction(
                  label: 'Cancel',
                  onPressed: () {
                    cancelDelete = true;
                  },
                ),
      );
    }
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

      messenger?.showSnackBar(snackBar!);
      await imageProcessingManager.awaitIsolatesOfHigherIndexedPages(
        docIndex,
        pageIndex,
      );
      messenger?.hideCurrentSnackBar();
      if (cancelDelete) return;

      imageProcessingManager.killIsolatesOfPage(docIndex, pageIndex);
      pageDir.deleteSync(recursive: true);
      Fluttertoast.showToast(
        msg: "Page ${pageIndex + 1} of Document ${docIndex + 1} deleted",
      );
    }

    // rename all with higher pageIndex to close the gap
    Directory fromDirectory = Directory(
      await getPagePath(docIndex, pageIndex + 1, supressWarning: true),
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
        await getPagePath(docIndex, pageIndex + 1, supressWarning: true),
      );
      toPath = await getPagePath(docIndex, pageIndex, supressWarning: true);
    }
    // Check if document is now empty and delete it
    if ((await getPagesCount(docIndex)) == 0) {
      dev.log("Deleting empty Document $docIndex");
      await deleteDocument(
        // ignore: use_build_context_synchronously
        context,
        docIndex,
        supressInfo: true,
        isBroken: true,
      );
      globalNotifier.triggerEvent(
        NotifierEvent.loadPagesThumbnails,
      ); // to not show deleted page and to Navigator.pop
    } else {
      //globalNotifier.triggerEvent(
      //  NotifierEvent.loadPageVersions,
      //); // otherwise they show the ones of other pages
      globalNotifier.triggerEvent(
        NotifierEvent.loadPagesThumbnails,
      ); // otherwise they show the ones of other pages
      globalNotifier.triggerEvent(
        NotifierEvent.loadDocsThumbnails,
      ); // for page count
    }
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
    for (var fse in Directory(pagePath).listSync()) {
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
    int? firstPageIndex;
    for (var i = 0; i < pageCount; i++) {
      final newPage = await _reserveNewPage(docIndex);
      firstPageIndex ??= newPage.$2;
    }

    return firstPageIndex!;
  }

  Future<(List<String>, String, String)> getImagePathsForPage(
    int docIndex,
    int pageIndex,
  ) async {
    String pagePath = await getPagePath(docIndex, pageIndex);
    List<String> versionPaths = ["", "", "", ""];
    String shapePath = "";
    String thumbnailPath = "";
    List<FileSystemEntity> versionsFSE =
        (Directory(pagePath).listSync()
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

    return (versionPaths, shapePath, thumbnailPath);
  }

  Future<String> getVersionPath(
    int docIndex,
    int pageIndex,
    int versionIndex,
  ) async {
    String pagePath = await getPagePath(docIndex, pageIndex);

    List<FileSystemEntity> versionsFSE =
        (Directory(pagePath).listSync()
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
          supressWarning: true,
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
          supressWarning: true,
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
          supressWarning: true,
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
          supressWarning: true,
        );
        await Directory(fromPath).rename(toPath);
      }
    }
    String newPath = await getPagePath(docIndex, newIndex);
    await Directory(tmpPath).rename(newPath);
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
        ).listSync().whereType<Directory>().toList();
    return dirList.length;
  }

  Future<void> saveDocumentImagesToGallery(int docIndex) async {
    List<String> imagePaths =
        (await getPagesThumbnails(docIndex, fullSized: true)).$1;
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
      imagePaths =
          (await getPagesThumbnails(
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

  bool _pickingImage = false;
  Future<List<String>> pickImage(
    BuildContext context,
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    if (_pickingImage) return [];
    _pickingImage = true;

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
    ReceivePort port = ReceivePort();
    RootIsolateToken token = RootIsolateToken.instance!;
    Isolate isolate = await Isolate.spawn(_pickImageIsolate, (
      port.sendPort,
      token,
      source,
      isMultiImage,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 1000));
      if (context.mounted) {
        messenger.showSnackBar(snackBar);
      }
    });

    final completer = Completer<List<String>>();
    port.listen((message) async {
      if (message is List<String>) {
        messenger.hideCurrentSnackBar();
        completer.complete(message);
        _pickingImage = false;
        port.close();
        isolate.kill();
      }
    });
    return await completer.future;
  }

  static Future<void> _pickImageIsolate(
    (
      SendPort sendPort,
      RootIsolateToken token,
      ImageSource source,
      bool isMultiImage,
    )
    data,
  ) async {
    SendPort sendPort = data.$1;
    RootIsolateToken token = data.$2;
    ImageSource source = data.$3;
    bool isMultiImage = data.$4;
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);

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
    sendPort.send(imagePaths);
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
      imagePaths =
          (await getPagesThumbnails(
            docIndex,
            pageIndexes: pageIndexes,
            fullSized: true,
          )).$1;
    }
    if (imagePaths.isEmpty) {
      dev.log("Error, _convertImagesToPdf: No images in Document $docIndex");
    }

    // Metadata
    List<int> ratioIndexes = [];
    List<int> orientations = [];
    if (pageIndexes.isEmpty) {
      pageIndexes = List.generate(imagePaths.length, (index) => index);
    }

    for (var pageIndex in pageIndexes) {
      ratioIndexes.add(
        await ImageProcessingManager.readPageRatioIndex(docIndex, pageIndex) ??
            0,
      );
      orientations.add(
        await ImageProcessingManager.readPageOrientationIndex(
              docIndex,
              pageIndex,
            ) ??
            0,
      );
    }

    try {
      // Select Aspect ratio
      double width = 21.0 * PdfPageFormat.cm;
      // 1. Get common width (shared across pages)
      for (int ratioIndex in ratioIndexes) {
        if (ratioIndex == 0) // A4
        {
          width = 21.0 * PdfPageFormat.cm;
          break;
        } else if (ratioIndex == 1 || ratioIndex == 2) // Legal / Letter
        {
          width = 8.5 * PdfPageFormat.inch;
          break;
        }
      }
      // 2. Set correct aspect ratio
      List<PdfPageFormat> pageFormats = [];
      for (var (i, ratioIndex) in ratioIndexes.indexed) {
        late double height;
        if (versionIndex == 0) {
          final image = await decodeImageFromList(
            (File(imagePaths[i]).readAsBytesSync()),
          );
          double photoRatio = image.height.toDouble() / image.width.toDouble();
          height = width * photoRatio;
        } else {
          height =
              (orientations[i] == 0)
                  ? width * commonAspectRatios[ratioIndex].value
                  : width / commonAspectRatios[ratioIndex].value;
        }
        pageFormats.add(PdfPageFormat(width, height));
      }

      // Create PDF
      final pdf = pdfw.Document();
      for (var (i, imagePath) in imagePaths.indexed) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          final imageBytes = await imageFile.readAsBytes();
          final image = pdfw.MemoryImage(imageBytes);

          pdf.addPage(
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

      return pdf;
    } catch (e) {
      dev.log("Error, _convertImageToPdf: $e");
    }
    return null;
  }

  Future<void> pickFolderForImagesPdf(
    int docIndex,
    BuildContext context, {
    List<int> pageIndexes = const [],
    int? versionIndex,
  }) async {
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
      String? selectedDirectory = await getDirectoryPath(
        confirmButtonText: "Select a Folder to Save PDF",
      );
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
      final String? versionName =
          versionIndex != null ? versionNames[versionIndex] : null;
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
        );
      }

      pdfw.Document? pdf;
      pdf = await _convertImagesToPdf(
        docIndex,
        pageIndexes: pageIndexes,
        versionIndex: versionIndex,
      );

      // Isolate
      Isolate isolate = await Isolate.spawn(_writePfdToPathIsolate, (
        port.sendPort,
        token,
        pdfPath,
        pdf,
      ));

      final completer = Completer();
      port.listen((message) {
        if (message is bool) {
          if (message) {
            completer.complete(message);
            messenger?.hideCurrentSnackBar();
            // Saved Toast
            const String basePath = "/storage/emulated/0";
            final readablePath =
                pdfPath.startsWith(basePath)
                    ? pdfPath.substring(basePath.length)
                    : pdfPath;
            dev.log("PDF saved at: $readablePath");
            Fluttertoast.showToast(
              msg: "PDF saved at: $readablePath",
              toastLength: Toast.LENGTH_LONG,
            );
            port.close();
            isolate.kill();
          } else {
            messenger?.hideCurrentSnackBar();
            messenger?.showSnackBar(
              SnackBar(content: Text("Error: No PDF available to save.")),
            );
          }
        }
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
        dev.log("Error, _pickFolderForDocumentPdfIsolate: $e");
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
    List<String> imagePaths =
        (await getPagesThumbnails(docIndex, fullSized: true)).$1;
    if (imagePaths.isNotEmpty) {
      shareImages(docIndex);
    } else {
      messenger?.showSnackBar(
        SnackBar(content: Text("No images available to share.")),
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
      imagePaths =
          (await getPagesThumbnails(
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

    await Share.shareXFiles(xFiles);
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
    final String? versionName =
        versionIndex != null ? versionNames[versionIndex] : null;
    String pdfPath =
        "$docsDir/doc${docIndex + 1}${pageIndexes.length == 1 ? "_page${pageIndexes.isNotEmpty ? pageIndexes.first + 1 : 1}" : ""}${versionName != null ? "_$versionName" : ""}.pdf";
    pdfw.Document? pdf = await _convertImagesToPdf(
      docIndex,
      pageIndexes: pageIndexes,
      versionIndex: versionIndex,
    );

    // Isolate
    Isolate isolate = await Isolate.spawn(_writePfdToPathIsolate, (
      port.sendPort,
      token,
      pdfPath,
      pdf,
    ));

    final completer = Completer();
    port.listen((message) async {
      if (message is bool) {
        if (message) {
          port.close();
          messenger?.hideCurrentSnackBar();
          completer.complete(message);
          await Share.shareXFiles([XFile(pdfPath)]);
          File(pdfPath).delete();
          isolate.kill();
        } else {
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            SnackBar(content: Text("Error: No PDF available to share.")),
          );
        }
      }
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
      Isolate.spawn(_rotateImageInTmpDirIsolate, (
        port.sendPort,
        imagePath,
        rotatedFilePath,
        rotationIn,
      ));
      await port.first;
      port.close();
    }

    return rotatedFilePath;
  }

  static Future<void> _rotateImageInTmpDirIsolate(
    (SendPort sendPort, String imagePath, String rotatedFilePath, int angle)
    data,
  ) async {
    SendPort sendPort = data.$1;
    String imagePath = data.$2;
    String rotatedFilePath = data.$3;
    int angle = data.$4;
    OpenCVHelper cvHelper = OpenCVHelper();

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
}
