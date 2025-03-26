// function:
import 'package:docscanner/main.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
//import 'dart:developer' as dev;
// my packages:
import 'opencv_helper.dart';
import 'package:docscanner/files_helper.dart';

class ImageProcessingManager {
  static Future<void> processPage(
    String picturePath,
    List<String> versionPaths,
  ) async {
    OpenCVHelper cvHelper = OpenCVHelper();

    // Original
    Uint8List picture = File(picturePath).readAsBytesSync();
    await FilesHelper.saveImage(versionPaths[0], picture);

    // Warped
    var ret = await compute(
      cvHelper.warpImage,
      ParamsWarpImage(versionPaths[0]),
    );
    Uint8List warped = ret.$1;
    List<int> borderCorrectionDepth = ret.$2;
    await FilesHelper.saveImage(versionPaths[1], warped);

    // Processed1 basierend auf dem Warped-Bild
    Uint8List processed1 = await compute(
      cvHelper.processImage1,
      ParamsProcessImage1(versionPaths[1]),
    );
    await FilesHelper.saveImage(versionPaths[2], processed1);

    // Processed2 basierend auf dem Processed1-Bild
    Uint8List processed2 = await compute(
      cvHelper.processImage2,
      ParamsProcessImage2(versionPaths[2], borderCorrectionDepth),
    );
    await FilesHelper.saveImage(versionPaths[3], processed2);
    // update thumbnails:
    globalNotifier.triggerEvent(NotifierEvent.loadThumbnails);
    globalNotifier.triggerEvent(NotifierEvent.loadDocThumbnails);
  }
}
