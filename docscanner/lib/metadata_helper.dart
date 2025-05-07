import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:docscanner/files_helper.dart';
import 'package:docscanner/image_prosessing_manager.dart';

class MetadataHelper {
  late FilesHelper filesHelper;
  MetadataHelper(FilesHelper filesHelperIn) : filesHelper = filesHelperIn;

  Future<void> writeDocName(int docIndex, String newName) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Error, _saveDocName: Trying to save metadata into empty Document $docIndex",
      );
      return;
    }
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (file.existsSync()) {
      try {
        String content = file.readAsStringSync();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } catch (e) {
        dev.log("Error,_saveDocName: Reading metadata: $e");
      }
    }

    // Write
    if (!file.existsSync()) {
      dev.log("Warning,_saveDocName: Metadata file missing, creating new one");
      metadata = {};
    }
    metadata["name"] = newName;

    await file.writeAsString(jsonEncode(metadata));
  }

  Future<void> writeDocDate(int docIndex, String newDate) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (file.existsSync()) {
      try {
        String content = file.readAsStringSync();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } catch (e) {
        dev.log("Error reading existing metadata, creating new one: $e");
      }
    }

    // Write
    metadata["date"] = newDate;
    await file.writeAsString(jsonEncode(metadata));
  }

  Future<void> writeDocUnlocked(int docIndex, bool unlocked) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (file.existsSync()) {
      try {
        String content = file.readAsStringSync();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } catch (e) {
        dev.log(
          "Error, _writeDocUnlocked: No existing metadata, creating new one: $e",
        );
      }
    }

    if (unlocked) {
      // disable after one hour (only necessary if in backround for over 1 hour)
      Future.delayed(Duration(hours: 1)).then((_) {
        writeDocUnlocked(docIndex, false);
      });
    }

    // Write
    metadata["unlocked"] = unlocked;
    await file.writeAsString(jsonEncode(metadata));
  }

  Future<bool> readDocUnlocked(int docIndex) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (file.existsSync()) {
      try {
        String content = file.readAsStringSync();
        metadata = jsonDecode(content).cast<String, dynamic>();
        return metadata["unlocked"] == true;
      } catch (e) {
        dev.log(
          "Error, _readDocUnlocked: No existing metadata, creating new one: $e",
        );
      }
    }
    return false;
  }

  Future<void> writePageUnlocked(
    int docIndex,
    int pageIndex,
    bool unlocked,
  ) async {
    final pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (file.existsSync()) {
      try {
        String content = file.readAsStringSync();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } catch (e) {
        dev.log(
          "Error, _writePageUnlocked: No existing metadata, creating new one: $e",
        );
      }
    }

    if (unlocked) {
      // disable after one hour (only necessary if in backround for over 1 hour)
      Future.delayed(Duration(hours: 1)).then((_) {
        writePageUnlocked(docIndex, pageIndex, false);
      });
    } else {
      if (3 ==
          await ImageProcessingManager.readPageThumbnailIndex(
            docIndex,
            pageIndex,
          )) {
        ImageProcessingManager.writePageThumbnailIndex(docIndex, pageIndex, 2);
      }
    }

    // Write
    metadata["unlocked"] = unlocked;
    await file.writeAsString(jsonEncode(metadata));
  }

  Future<bool> readPageUnlocked(int docIndex, int pageIndex) async {
    final pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (file.existsSync()) {
      try {
        String content = file.readAsStringSync();
        metadata = jsonDecode(content).cast<String, dynamic>();
        return metadata["unlocked"] == true;
      } catch (e) {
        dev.log(
          "Error, _readPageUnlocked: No existing metadata, creating new one: $e",
        );
      }
    }
    return false;
  }
}
