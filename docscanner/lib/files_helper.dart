import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:docscanner/image_prosessing_manager.dart';
import 'package:docscanner/main.dart';
import 'package:docscanner/opencv_helper.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as dev;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdfw;
import 'package:file_picker/file_picker.dart';
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

  Future<void> saveImage(String toImagePath, Uint8List imageBytes) async {
    File(toImagePath).writeAsBytesSync(imageBytes);
    if (!File(toImagePath).existsSync()) {
      dev.log("Error, saveImage: Failed to save $toImagePath");
      return;
    } //else {
    //dev.log("Image saved at: $toImagePath");
    //}
  }

  Future<(List<String>, int)> getDocThumbnails() async {
    await _initializeDocumentsPath();
    int docsCount = await filesHelper.getDocumentsCount();
    List<String> thumbnailPaths = List.generate(docsCount, (_) {
      return "";
    });
    List<FileSystemEntity> docs =
        Directory(docsPath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (docs.isEmpty) return (thumbnailPaths, docsCount);
    for (var (docIndex, doc) in docs.indexed) {
      List<FileSystemEntity> pages =
          (Directory(doc.path).listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path)));
      String page0Path = "";
      if (pages.isNotEmpty) {
        page0Path = pages.first.path;
      } else {
        continue;
      }
      final thumbnailName = "thumbnail";
      final thumbnailPath = ('$page0Path/$thumbnailName.png');
      // read metadata: thumbnailIndex
      int thumbnailIndex =
          await ImageProcessingManager.readPageThumbnailIndex(docIndex, 0) ?? 3;
      final backupName = versionNames[thumbnailIndex];
      final backupPath = '$page0Path/$backupName.png';
      if (File(thumbnailPath).existsSync()) {
        thumbnailPaths[docIndex] = thumbnailPath;
        imageCache.evict(FileImage(File(backupPath)), includeLive: false);
      } else {
        if (File(backupPath).existsSync()) {
          thumbnailPaths[docIndex] = backupPath;
        }
      }
    }

    return (thumbnailPaths, docsCount);
  }

  Future<(List<String>, int)> getPagesThumbnails(int docIndex) async {
    await _initializeDocumentsPath();
    int pagesCount = await filesHelper.getPagesCount(docIndex);
    List<String> thumbnailPaths = List.generate(pagesCount, (_) {
      return "";
    });
    String docPath = await getDocumentPath(docIndex);
    List<FileSystemEntity> pages = [];
    try {
      pages =
          Directory(docPath).listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
    } catch (e) {
      dev.log('Error while listing pages: $e');
    }
    if (pages.isEmpty) return (thumbnailPaths, pagesCount);
    for (var (pageIndex, page) in pages.indexed) {
      final pagePath = page.path;
      final thumbnailName = "thumbnail";
      final thumbnailPath = '$pagePath/$thumbnailName.png';
      // read metadata: thumbnailIndex
      int thumbnailIndex =
          await ImageProcessingManager.readPageThumbnailIndex(
            docIndex,
            pageIndex,
          ) ??
          3;
      final backupName = versionNames[thumbnailIndex];
      final backupPath = '$pagePath/$backupName.png';
      if (File(thumbnailPath).existsSync()) {
        thumbnailPaths[pageIndex] = thumbnailPath;
        imageCache.evict(FileImage(File(backupPath)), includeLive: false);
      } else {
        if (File(backupPath).existsSync()) {
          thumbnailPaths[pageIndex] = backupPath;
        }
      }
    }

    return (thumbnailPaths, pagesCount);
  }

  Future<void> repairDirectoryStructure() async {
    await _initializeDocumentsPath();
    // repeat repairing until there are no more changes
    var i = 0;
    for (; i < 5; i++) {
      try {
        if (!(await _repairDirectoryStructure())) break;
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

  Future<bool> _repairDirectoryStructure() async {
    bool anyChange = false;

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
        for (var (pageIndex, page) in pages.indexed) {
          // Reanme pages to match their index
          String expectedPagePath = await getPagePath(
            docIndex,
            pageIndex,
            supressWarning: true,
          );
          if (page.path != expectedPagePath) {
            dev.log("Renaming ${page.path} -> $expectedPagePath");
            page.renameSync(expectedPagePath);
            anyChange = true;
          }

          // Delete empty pages
          int versionCount = await getPageVersionsCount(docIndex, pageIndex);
          if (versionCount < 5) {
            anyChange = true;
            if (versionCount == 0) {
              dev.log("Deleting empty Page $pageIndex");
            } else {
              dev.log("Deleting half-empty Page $pageIndex");
            }
            await deletePage(docIndex, pageIndex);
            // Info: If deletePage() results in empty Documents,
            //       deletePage() will delete these Documents
          }
        }
      } else {
        anyChange = true;
        deleteDocument(docIndex);
      }
    }
    return anyChange;
  }

  Future<void> deleteDocument(int docIndex, {bool supressInfo = false}) async {
    String docPath = await getDocumentPath(docIndex, supressWarning: true);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Warning, deleteDocument: Document $docIndex nonexistent, moving following Documents up",
      );
    } else {
      if (!supressInfo) {
        dev.log("deleteDocument: Deleting document directory: $docPath");
      }
      imageProcessingManager.killIsolatesOfDocument(docIndex);
      Directory(docPath).deleteSync(recursive: true);
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
      NotifierEvent.reloadDocsThumbnails,
    ); // to not show deleted document
  }

  Future<void> deletePage(int docIndex, int pageIndex) async {
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
      await deleteDocument(docIndex, supressInfo: true);
      globalNotifier.triggerEvent(
        NotifierEvent.loadPagesThumbnails,
      ); // to not show deleted page and to Navigator.pop
    } else {
      globalNotifier.triggerEvent(
        NotifierEvent.loadPageVersions,
      ); // otherwise they show the ones of other pages
      globalNotifier.triggerEvent(
        NotifierEvent.reloadPagesThumbnails,
      ); // otherwise they show the ones of other pages
      globalNotifier.triggerEvent(
        NotifierEvent.loadDocsThumbnailsAndInfo,
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
    List<String> processedNames = [
      "warped",
      "processed1",
      "processed2",
      "thumbnail",
    ];
    for (var fse in Directory(pagePath).listSync()) {
      for (var name in processedNames) {
        if (fse.path.endsWith("$name.png")) {
          imageCache.evict(FileImage(File(fse.path)), includeLive: true);
          fse.delete();
          //dev.log("deleteProcessedVersionsOfPage: Deleting ${file.path}");
        }
      }
    }
    globalNotifier.triggerEvent(NotifierEvent.loadDocsThumbnailsAndInfo);
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

  Future<List<String>> getImagePathsForPage(int docIndex, int pageIndex) async {
    String pagePath = await getPagePath(docIndex, pageIndex);

    List<String> imagePaths = [];
    for (var imageName in versionNames) {
      imagePaths.add('$pagePath/$imageName.png');
    }

    return imagePaths;
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

  Future<int> getPageVersionsCount(int docIndex, int pageIndex) async {
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
    List<String> imagePaths = (await getPagesThumbnails(docIndex)).$1;
    final albumName = "Scanned Documents";

    int i = 0;
    for (String imagePath in imagePaths) {
      await Gal.putImage(imagePath, album: albumName);
      i++;
    }
    Fluttertoast.showToast(msg: 'Saved $i images in album "$albumName"');
  }

  static Future<void> saveImagesToGallery(List<String> imagePaths) async {
    final albumName = "Scanned Documents";

    for (String imagePath in imagePaths) {
      await Gal.putImage(imagePath, album: albumName);
      Fluttertoast.showToast(msg: 'Saved in album "$albumName"');
    }
  }

  static void saveImageToGallery(String imagePath) {
    saveImagesToGallery([imagePath]);
  }

  static Future<List<String>> pickImage(
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
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
      if (pickedFile == null) {
        return [];
      } else {
        imagePaths = [pickedFile.path];
      }
    }

    return imagePaths;
  }

  Future<pdfw.Document?> _convertDocumentToPdf(int docIndex) async {
    try {
      List<String> imagePaths = (await getPagesThumbnails(docIndex)).$1;
      if (imagePaths.isEmpty) {
        dev.log(
          "Error, _convertDocumentToPdf: No images in Document $docIndex",
        );
      }
      return _convertImagesToPdf(imagePaths, docIndex, 0);
    } catch (e) {
      dev.log("Error, _convertDocumentToPdf: $e");
    }
    return null;
  }

  static Future<pdfw.Document?> _convertImagesToPdf(
    List<String> imagePaths,
    int docIndex,
    int firstPageIndex,
  ) async {
    // Metadata
    List<int> ratioIndexes = [];
    List<int> orientations = [];
    for (
      var pageIndex = firstPageIndex;
      pageIndex < imagePaths.length;
      pageIndex++
    ) {
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
        double height =
            (orientations[i] == 0)
                ? width * commonAspectRatios[ratioIndex].value
                : width / commonAspectRatios[ratioIndex].value;
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

  Future<void> pickFolderForDocumentPdf(int docIndex) async {
    try {
      // Ask user to pick a folder
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "Select a Folder to Save PDF",
      );
      if (selectedDirectory == null) {
        dev.log("User-Action, pickFolderForDocumentPdf: cancelled");
        return;
      }
      // Save PDF
      String pdfPath = "$selectedDirectory/doc${docIndex + 1}.pdf";
      File file = File(pdfPath);
      if (file.existsSync()) {
        file.renameSync(
          "${pdfPath}_old_${DateTime.now().millisecondsSinceEpoch}",
        );
      }
      pdfw.Document? pdf = await _convertDocumentToPdf(docIndex);
      if (pdf == null) return;
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(await pdf.save());
      // Toast
      const String basePath = "/storage/emulated/0";
      final readablePath =
          pdfPath.startsWith(basePath)
              ? pdfPath.substring(basePath.length)
              : pdfPath;
      dev.log("PDF saved at: $readablePath");
      Fluttertoast.showToast(msg: 'PDF saved at: "$readablePath"');
    } catch (e) {
      dev.log("Error, pickFolderForDocumentPdf: $e");
    }
  }

  static Future<void> pickFolderForImagePdf(
    String imagePath,
    int docIndex,
    int pageIndex, {
    String? versionName,
  }) async {
    try {
      // Ask user to pick a folder
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "Select a Folder to Save PDF",
      );
      if (selectedDirectory == null) {
        dev.log("User-Action, pickFolderForImagePdf: cancelled");
        return;
      }
      // Save PDF
      String pdfPath =
          "$selectedDirectory/doc${docIndex + 1}_page${pageIndex + 1}${versionName != null ? "_$versionName" : ""}.pdf";
      File file = File(pdfPath);
      if (file.existsSync()) {
        file.renameSync(
          "${pdfPath}_old_${DateTime.now().millisecondsSinceEpoch}",
        );
      }
      pdfw.Document? pdf = await _convertImagesToPdf(
        [imagePath],
        docIndex,
        pageIndex,
      );
      if (pdf == null) return;
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(await pdf.save());
      // Toast
      const String basePath = "/storage/emulated/0";
      final readablePath =
          pdfPath.startsWith(basePath)
              ? pdfPath.substring(basePath.length)
              : pdfPath;
      dev.log("PDF saved at: $readablePath");
      Fluttertoast.showToast(msg: 'PDF saved at: "$readablePath"');
    } catch (e) {
      dev.log("Error, pickFolderForImagePdf: $e");
    }
  }

  Future<void> shareDocumentImages(BuildContext context, int docIndex) async {
    List<String> imagePaths = (await getPagesThumbnails(docIndex)).$1;
    if (imagePaths.isNotEmpty) {
      shareImages(imagePaths, docIndex: docIndex);
    } else {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text("No images available to share.")));
    }
  }

  static Future<void> shareImages(
    List<String> imagePaths, {
    int? docIndex,
  }) async {
    // Unique filenames in temporary directory to prevent overwrites,
    // because shareXFiles is stupid
    final tempDir = await getApplicationSupportDirectory();
    await tempDir.create(recursive: true);
    List<XFile> xFiles = [];

    for (var i = 0; i < imagePaths.length; i++) {
      final originalPath = imagePaths[i];
      final ext = originalPath.split('.').last;
      final tempFilePath =
          '${tempDir.path}/${docIndex != null ? "doc${docIndex}_page" : "image_"}$i.$ext';
      await File(originalPath).copy(tempFilePath);

      xFiles.add(XFile(tempFilePath));
    }

    await Share.shareXFiles(xFiles);
    tempDir.delete(recursive: true);
  }

  Future<void> shareDocumentPdf(BuildContext context, int docIndex) async {
    // Save PDF
    final docsPath = await _getDocumentsPath();
    String pdfPath = "$docsPath/doc${docIndex + 1}.pdf";

    pdfw.Document? pdf = await _convertDocumentToPdf(docIndex);
    if (pdf != null) {
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(pdfPath)]);
      pdfFile.delete();
    } else {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text("No PDF available to share.")));
    }
  }

  Future<void> shareImagesPdf(
    BuildContext context,
    List<String> imagePaths,
    int docIndex,
    int firstPageIndex, {
    String? versionName,
  }) async {
    // Save PDF
    final docsDir = await _getDocumentsPath();
    String pdfPath =
        "$docsDir/doc${docIndex + 1}${imagePaths.length == 1 ? "_page${firstPageIndex + 1}" : ""}${versionName != null ? "_$versionName" : ""}}.pdf";
    pdfw.Document? pdf = await _convertImagesToPdf(
      imagePaths,
      docIndex,
      firstPageIndex,
    );
    if (pdf != null) {
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(await pdf.save());
      XFile xFile = XFile(pdfPath);

      await Share.shareXFiles([xFile]);
      pdfFile.delete();
    } else {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text("No PDF available to share.")));
    }
  }

  static Future<String> rotateImageInTmpDir(String imagePath, int angle) async {
    final tmpDir = await getTemporaryDirectory();
    final rotatedFilePath = "${tmpDir.path}/rotated_$angle.png";

    if (File(rotatedFilePath).existsSync()) return rotatedFilePath;
    final port = ReceivePort();
    OpenCVHelper cvHelper = OpenCVHelper();
    Isolate.spawn(cvHelper.rotateImageInTmpDir, (
      port.sendPort,
      imagePath,
      rotatedFilePath,
      angle,
    ));
    await port.first;
    port.close();
    return rotatedFilePath;
  }

  static Future<void> deleteCachedRoatedImages() async {
    List<String> paths = [];
    final tmpDir = await getTemporaryDirectory();
    for (var angle = 90; angle <= 270; angle += 90) {
      paths.add("${tmpDir.path}/rotated_$angle.png");
    }
    deleteImages(paths);
  }

  static Future<void> deleteImages(List<String> paths) async {
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
