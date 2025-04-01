import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
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
  String docsPath = "";

  Future<String> _getDocumentsPath() async {
    if (docsPath.isNotEmpty && Directory(docsPath).existsSync()) {
      return docsPath;
    }

    final baseDir = await getApplicationDocumentsDirectory();
    docsPath = '${baseDir.path}/Documents';
    var docsDir = Directory(docsPath);
    if (!docsDir.existsSync()) {
      await docsDir.create(recursive: true);
    }
    return docsPath;
  }

  Future<(String, int)> _reserveNewDocument() async {
    String docsPath = await _getDocumentsPath();

    int docIndex = 0;
    while (await Directory('$docsPath/Document $docIndex').exists()) {
      docIndex++;
    }

    String newDocPath = '$docsPath/Document $docIndex';
    await Directory(newDocPath).create();
    return (newDocPath, docIndex);
  }

  Future<String> getDocumentPath(int docIndex) async {
    String docsPath = await _getDocumentsPath();

    String docPath = '$docsPath/Document $docIndex';
    if (!Directory(docPath).existsSync()) {
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

  Future<String> getPagePath(int docIndex, int pageIndex) async {
    String documentPath = await getDocumentPath(docIndex);
    String pagePath = '$documentPath/Page $pageIndex';
    if (!Directory(pagePath).existsSync()) {
      dev.log(
        "Warning, getPagePath: Requested directory \"$pagePath\" does not exist.",
      );
    }
    return pagePath;
  }

  static Future<void> saveImage(
    String toImagePath,
    Uint8List imageBytes,
  ) async {
    await File(toImagePath).writeAsBytes(imageBytes);
    if (!File(toImagePath).existsSync()) {
      dev.log("Image SAVE FAILED at: $toImagePath");
    } else {
      //dev.log("Image saved at: $toImagePath");
    }
  }

  Future<List<String>> getDocThumbnails() async {
    String docsPath = await _getDocumentsPath();
    List<String> docThumbnails = [];
    List<FileSystemEntity> docs =
        Directory(docsPath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (docs.isEmpty) return [];
    for (var doc in docs) {
      List<FileSystemEntity> pages =
          (Directory(doc.path).listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path)));
      String page0Path = "";
      if (pages.isNotEmpty) {
        page0Path = pages.first.path;
      } else {
        continue;
      }
      final imageName = "processed2";
      final thumbnailPath = ('$page0Path/$imageName.png');
      if (File(thumbnailPath).existsSync()) {
        docThumbnails.add(thumbnailPath);
      } else {
        dev.log("Warning, getDocThumbnails: Image NOT Found: $thumbnailPath");
      }
    }

    return docThumbnails;
  }

  Future<List<String>> getPagesThumbnails(int docIndex) async {
    String docsPath = await _getDocumentsPath();
    List<FileSystemEntity> docs =
        Directory(docsPath).listSync()
          ..sort((a, b) => a.path.compareTo(b.path));

    if (docs.isEmpty) return [];
    if (docs.length - 1 < docIndex) return [];
    String docPath = docs[docIndex].path;
    List<FileSystemEntity> pages =
        Directory(docPath).listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (pages.isEmpty) return [];

    List<String> thumbnailPaths = [];
    for (var page in pages) {
      final pagePath = page.path;
      final imageName = "processed2";
      final thumbnailPath = ('$pagePath/$imageName.png');
      if (File(thumbnailPath).existsSync()) {
        thumbnailPaths.add(thumbnailPath);
      } else {
        dev.log("Warning, getPagesThumbnails: Image NOT Found: $thumbnailPath");
      }
    }

    return thumbnailPaths;
  }

  Future<void> deleteEmptyDirectories() async {
    String docsDir = await _getDocumentsPath();
    if (!await Directory(docsDir).exists()) return;

    List<FileSystemEntity> docs = Directory(docsDir).listSync();

    for (var (docIndex, doc) in docs.indexed) {
      if (doc is Directory) {
        List<FileSystemEntity> pages =
            Directory(doc.path).listSync().whereType<Directory>().toList();

        // Delete empty pages
        for (var (pageIndex, page) in pages.indexed) {
          int versionCount = await getPageVersionsCount(docIndex, pageIndex);
          if (versionCount < 4) {
            if (versionCount == 0) {
              dev.log("Deleting empty page directory: ${page.path}");
            } else {
              dev.log("Deleting half-empty page directory: ${page.path}");
            }
            await deletePage(docIndex, pageIndex);
          }
        }
        // Info: deletePage already deletes as a result empty Documents
      }
    }
  }

  Future<void> deleteDocument(int docIndex) async {
    String docPath = await getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Warning, deleteDocument: Document $docIndex nonexistent, moving following Documents up",
      );
    } else {
      dev.log("deleteDocument: Deleting document directory: $docPath");
      Directory(docPath).deleteSync(recursive: true);
    }

    // rename all with higher docIndex to close the gap
    Directory fromDirectory = Directory(await getDocumentPath(docIndex + 1));
    String toPath = docPath;
    for (int i = docIndex; i < await getDocumentsCount();) {
      if (fromDirectory.existsSync()) {
        dev.log("Renaming ${fromDirectory.path} -> $toPath");
        await fromDirectory.rename(toPath);
        i++;
      }

      docIndex++;
      fromDirectory = Directory(await getDocumentPath(docIndex + 1));
      toPath = await getDocumentPath(docIndex);
    }
    globalNotifier.triggerEvent(NotifierEvent.reloadDocsThumbnails);
  }

  Future<void> deletePage(int docIndex, int pageIndex) async {
    String pagePath = await getPagePath(docIndex, pageIndex);
    if (!await Directory(pagePath).exists()) {
      dev.log(
        "Warning, deletePage: Document $docIndex, Page $pageIndex nonexistent, moving following Pages up",
      );
    } else {
      dev.log("Deleting page directory: $pagePath");
      Directory(pagePath).deleteSync(recursive: true);
    }

    // rename all with higher pageIndex to close the gap
    Directory fromDirectory = Directory(
      await getPagePath(docIndex, pageIndex + 1),
    );
    String toPath = pagePath;
    for (int i = pageIndex; i < await getPagesCount(docIndex);) {
      if (fromDirectory.existsSync()) {
        dev.log("Renaming ${fromDirectory.path} -> $toPath");
        await fromDirectory.rename(toPath);
        i++;
      }

      pageIndex++;
      fromDirectory = Directory(await getPagePath(docIndex, pageIndex + 1));
      toPath = await getPagePath(docIndex, pageIndex);
    }
    // Check if document is now empty and delete it
    if ((await getPagesCount(docIndex)) == 0) {
      dev.log("Deleting empty Document $docIndex");
      deleteDocument(docIndex);
      globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
    } else {
      globalNotifier.triggerEvent(NotifierEvent.loadPageVersions);
      globalNotifier.triggerEvent(NotifierEvent.reloadPagesThumbnails);
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
    List<String> processedNames = ["warped", "processed1", "processed2"];
    for (var file in Directory(pagePath).listSync()) {
      for (var name in processedNames) {
        if (file.path.endsWith("$name.png")) {
          file.delete();
          //dev.log("deleteProcessedVersionsOfPage: Deleting ${file.path}");
        }
      }
    }
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
    List<String> imageNames = ["picture", "warped", "processed1", "processed2"];
    String pagePath = await getPagePath(docIndex, pageIndex);

    List<String> imagePaths = [];
    for (var imageName in imageNames) {
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
        String toPath = await getDocumentPath(rollingIndex);
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
        String toPath = await getDocumentPath(rollingIndex);
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
        String toPath = await getPagePath(docIndex, rollingIndex);
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
        String toPath = await getPagePath(docIndex, rollingIndex);
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
    List<String> imagePaths = await getPagesThumbnails(docIndex);
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
      List<String> imagePaths = await getPagesThumbnails(docIndex);
      if (imagePaths.isEmpty) {
        dev.log(
          "Error, _convertDocumentToPdf: No images in Document $docIndex",
        );
      }
      return _convertImagesToPdf(imagePaths);
    } catch (e) {
      dev.log("Error, _convertDocumentToPdf: $e");
    }
    return null;
  }

  static Future<pdfw.Document?> _convertImagesToPdf(
    List<String> imagePaths,
  ) async {
    try {
      // Create PDF
      final pdf = pdfw.Document();
      for (String imagePath in imagePaths) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          final imageBytes = await imageFile.readAsBytes();
          final image = pdfw.MemoryImage(imageBytes);

          pdf.addPage(
            pdfw.Page(
              pageFormat: PdfPageFormat.a4,
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
      String pdfPath = "$selectedDirectory/document_$docIndex.pdf";
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
    String imagePath, {
    int? docIndex,
    int? pageIndex,
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
          "$selectedDirectory/doc${docIndex != null ? docIndex + 1 : ""}_page${pageIndex != null ? pageIndex + 1 : ""}${versionName != null ? "_$versionName" : ""}.pdf";
      pdfw.Document? pdf = await _convertImagesToPdf([imagePath]);
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
    List<String> imagePaths = await getPagesThumbnails(docIndex);
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
    String pdfPath = "$docsPath/document_$docIndex.pdf";

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
    List<String> imagePaths, {
    int? docIndex,
    int? pageIndex,
    String? versionName,
  }) async {
    // Save PDF
    final docsDir = await _getDocumentsPath();
    String pdfPath =
        "$docsDir/doc${docIndex != null ? docIndex + 1 : ""}_page${pageIndex != null ? pageIndex + 1 : ""}${versionName != null ? "_$versionName" : ""}.pdf";
    pdfw.Document? pdf = await _convertImagesToPdf(imagePaths);
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
    final receivePort = ReceivePort();
    OpenCVHelper cvHelper = OpenCVHelper();
    Isolate.spawn(cvHelper.rotateImageInTmpDir, [
      receivePort.sendPort,
      imagePath,
      rotatedFilePath,
      angle,
    ]);

    // Wait for the background isolate to finish
    await receivePort.first;

    return rotatedFilePath;
  }

  static Future<void> deleteTmpDir() async {
    var tmpDir = await getTemporaryDirectory();
    List<FileSystemEntity> files = tmpDir.listSync(recursive: true);
    for (var file in files) {
      imageCache.evict(FileImage(File(file.path)), includeLive: true);
    }
    await tmpDir.delete(recursive: true);
  }
}
