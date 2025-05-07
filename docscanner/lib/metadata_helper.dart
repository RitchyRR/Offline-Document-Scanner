import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';
// my packages:
import 'package:docscanner/main.dart';
import 'package:docscanner/files_helper.dart';
import 'package:docscanner/image_prosessing_manager.dart';
// encryption:
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart';

class MetadataHelper {
  //late FilesHelper filesHelper;
  //late bool? proUnlocked;
  //MetadataHelper(FilesHelper filesHelperIn, bool? proUnlockedIn)
  //  : filesHelper = filesHelperIn,
  //    proUnlocked = proUnlockedIn;

  Future<void> _writeDoc(int docIndex, String keyIn, dynamic valueIn) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log("Error, _writeDoc, $keyIn: No document $docIndex");
      return;
    }
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};
    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      } catch (e) {
        dev.log("Error, saveDocName: Reading metadata: $e");
      }
    } else {
      dev.log("Warning, saveDocName: Metadata file missing, creating new one.");
    }
    // Write + Encrypt
    metadata[keyIn] = valueIn;
    final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
    await file.writeAsString(encrypted);
  }

  Future<dynamic> _readDoc(int docIndex, String keyIn) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Error, saveDocName: Trying to write metadata into empty Document $docIndex",
      );
      return null;
    }
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
        return metadata[keyIn];
      } catch (e) {
        dev.log("Error, readDocName: $e");
      }
    }
    return null;
  }

  Future<void> writeDocName(int docIndex, String newName) async {
    _writeDoc(docIndex, "name", newName);
  }

  Future<String?> readDocName(int docIndex) async {
    return (await _readDoc(docIndex, "name"))?.toString();
  }

  Future<void> writeDocDate(int docIndex, String newDate) async {
    _writeDoc(docIndex, "date", newDate);
  }

  Future<String?> readDocDate(int docIndex) async {
    return (await _readDoc(docIndex, "date"))?.toString();
  }

  Future<void> writeDocUnlocked(int docIndex, bool unlocked) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      } catch (e) {
        dev.log("Error, writeDocUnlocked: $e");
      }
    }

    if (unlocked) {
      // Re-lock after 1 hour
      Future.delayed(Duration(hours: 1)).then((_) {
        writeDocUnlocked(docIndex, false);
      });
    }

    // Write + Encrypt
    metadata["unlocked"] = unlocked;
    final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
    await file.writeAsString(encrypted);
  }

  Future<bool> readDocUnlocked(int docIndex) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
        return metadata["unlocked"] == true;
      } catch (e) {
        //dev.log(
        //  "Error, readDocUnlocked: $e",
        //);
      }
    } else {
      dev.log("Error, readDocUnlocked: No existing metadata.");
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

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      } catch (e) {
        dev.log("Error, writePageUnlocked: $e");
      }
    }

    if (unlocked) {
      // Re-lock after 1 hour
      Future.delayed(Duration(hours: 1)).then((_) {
        writePageUnlocked(docIndex, pageIndex, false);
      });
    } else {
      if (3 == await readPageThumbnailIndex(docIndex, pageIndex)) {
        writePageThumbnailIndex(docIndex, pageIndex, 2);
      }
    }

    // Write + Encrypt
    metadata["unlocked"] = unlocked;
    final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
    await file.writeAsString(encrypted);
  }

  Future<bool> readPageUnlocked(int docIndex, int pageIndex) async {
    final pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
        return metadata["unlocked"] == true;
      } catch (e) {
        //dev.log(
        //  "Error, readPageUnlocked: No existing metadata, creating new one: $e",
        //);
      }
    } else {
      dev.log("Error, readDocUnlocked: No existing metadata.");
    }
    return false;
  }

  static Future<void> writePageMetadata(
    int docIndex,
    int pageIndex,
    int? ratioIndex,
    int? orientationIndex,
    int? thumbnailIndex,
    List<List<int>>? cornerPoints, {
    FilesHelper? filesHelperIn,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Write
      if (ratioIndex != null) metadata["apectRatio"] = ratioIndex.toString();
      metadata["orientation"] =
          orientationIndex == 0 ? "portrait" : "landscape";
      metadata["thumbnail"] =
          versionNames[thumbnailIndex != null && thumbnailIndex != 0
              ? thumbnailIndex
              : ((proUnlocked == true) ? 3 : 2)];
      if (cornerPoints != null) metadata["corners"] = cornerPoints;
      await file.writeAsString(jsonEncode(metadata));
      if (filesHelperIn != null) {
        // if started outside of isolate
        globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
      }
    } catch (e) {
      dev.log("Error, writePageMetadata: $e");
    }
  }

  Future<(int?, int?, int?, List<List<int>>?)> readPageMetadata(
    int docIndex,
    int pageIndex, {
    bool supressWarning = false,
  }) async {
    int? ratioIndex;
    int? orientationIndex;
    int? thumbnailIndex;
    List<List<int>>? cornerPoints;

    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
        ratioIndex = int.parse(metadata["apectRatio"]);
        String orientationString = metadata["orientation"];
        orientationIndex =
            (orientationString == "portrait" || orientationString == "")
                ? 0
                : 1;
        String? thumbnailString = metadata["thumbnail"];
        if (thumbnailString != null) {
          thumbnailIndex = versionNames.indexOf(thumbnailString);
          if (thumbnailIndex == 0) {
            throw StateError('metadata: thumbnail cant be the picture');
          }
          cornerPoints =
              (metadata["corners"] as List)
                  .map<List<int>>(
                    (e) => (e as List).map((v) => v as int).toList(),
                  )
                  .toList();
        }
        return (ratioIndex, orientationIndex, thumbnailIndex, cornerPoints);
      } catch (e) {
        dev.log("Error, readPageMetadata: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageMetadata: Metadata does not exist for $pagePath",
      );
    }
    return (ratioIndex, orientationIndex, thumbnailIndex, cornerPoints);
  }

  static Future<void> writePageThumbnailIndex(
    int docIndex,
    int pageIndex,
    int thumbnailIndex,
  ) async {
    bool updateThumbnail = false; // is new and not picture
    String newThumbnailName = versionNames[thumbnailIndex];
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Read
      if (await file.exists()) {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } else {
        dev.log(
          "Error, writePageThumbnailIndex: metadata File does not exist (Page $pageIndex, Document $docIndex)",
        );
        return;
      }
      if (thumbnailIndex != 0 &&
          (metadata["thumbnail"] != null
                  ? versionNames.indexOf(metadata["thumbnail"])
                  : ((proUnlocked == true) ? 3 : 2)) !=
              thumbnailIndex) {
        updateThumbnail = true;
      }

      // Write
      if (updateThumbnail) {
        imageProcessingManager.applyThumbnail(
          docIndex,
          pageIndex,
          thumbnailIndex,
        );
        metadata["thumbnail"] = newThumbnailName;
        await file.writeAsString(jsonEncode(metadata));
      }
    } catch (e) {
      dev.log("Error, writePageThumbnailIndex: $e");
    }
  }

  static Future<void> writePageCornerPoints(
    int docIndex,
    int pageIndex,
    List<List<int>> cornerPoints,
  ) async {
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Read
      if (await file.exists()) {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
      } else {
        dev.log(
          "Error, writePageCornerPoints: metadata File does not exist (Page $pageIndex, Document $docIndex)",
        );
      }

      // Write
      metadata["corners"] = cornerPoints;
      await file.writeAsString(jsonEncode(metadata));
      globalNotifier.triggerEvent(NotifierEvent.loadPageMetadata);
    } catch (e) {
      dev.log("Error, writePageCornerPoints: $e");
    }
  }

  static Future<int?> readPageRatioIndex(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        return int.parse(metadata["apectRatio"]);
      } catch (e) {
        dev.log("Error, readPageRatioIndex: $e");
      }
    }
    if (!supressWarnings) {
      dev.log(
        "Warning, readPageRatioIndex: Metadata does not exist for $pagePath",
      );
    }
    return null;
  }

  static Future<int?> readPageOrientationIndex(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    String pagePath = await filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        String orientationString = metadata["orientation"];
        return (orientationString == "portrait" || orientationString == "")
            ? 0
            : 1;
      } catch (e) {
        dev.log("Error, readPageOrientationIndex: $e");
      }
    }
    if (!supressWarnings) {
      dev.log(
        "Warning, readPageOrientationIndex: Metadata does not exist for $pagePath",
      );
    }
    return null;
  }

  static Future<int> readPageThumbnailIndex(
    int docIndex,
    int pageIndex, {
    FilesHelper? filesHelperIn,
    bool supressWarning = false,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
        String? thumbnailString = metadata["thumbnail"];

        if (thumbnailString != null) {
          int? retInt = versionNames.indexOf(thumbnailString);
          if (retInt == 0) {
            throw StateError('metadata: thumbnail cant be the picture');
          } else {
            return retInt;
          }
        }
      } catch (e) {
        dev.log("Error, readPageThumbnailIndex: $e");
      }
    }
    if (!supressWarning) {
      dev.log(
        "Warning, readPageThumbnailIndex: Metadata does not exist for $pagePath",
      );
    }
    return (proUnlocked == true) ? 3 : 2;
  }

  static Future<List<List<int>>> readPageCornerPoints(
    int docIndex,
    int pageIndex, {
    FilesHelper? filesHelperIn,
    bool supressWarnings = false,
  }) async {
    String pagePath = await (filesHelperIn ?? filesHelper).getPagePath(
      docIndex,
      pageIndex,
    );
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, dynamic>();
        List<List<int>> cornerPoints =
            (metadata["corners"] as List)
                .map<List<int>>(
                  (e) => (e as List).map((v) => v as int).toList(),
                )
                .toList();
        return cornerPoints;
      } catch (e) {
        dev.log("Error, readPageThumbnailIndex: $e");
      }
    }
    if (!supressWarnings) {
      dev.log(
        "Warning, readPageCornerPoints: Metadata does not exist for $pagePath",
      );
    }
    return [];
  }
}

class MetadataCryptoHelper {
  static const _storageKey = 'encryption_key';
  static const _keySize = 32; // 256-bit AES
  static final _secureStorage = FlutterSecureStorage();

  static Future<Key> _getOrCreateKey() async {
    String? keyBase64 = await _secureStorage.read(key: _storageKey);

    if (keyBase64 == null) {
      final random = Random.secure();
      final keyBytes = List<int>.generate(_keySize, (_) => random.nextInt(256));
      keyBase64 = base64UrlEncode(keyBytes);
      await _secureStorage.write(key: _storageKey, value: keyBase64);
    }

    return Key(base64Url.decode(keyBase64));
  }

  static Future<String> encryptMetadata(Map<String, dynamic> metadata) async {
    final key = await _getOrCreateKey();
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

    final encrypted = encrypter.encrypt(jsonEncode(metadata), iv: iv);
    final encryptedWithIv = jsonEncode({
      "iv": base64UrlEncode(iv.bytes),
      "data": encrypted.base64,
    });

    return encryptedWithIv;
  }

  static Future<Map<String, dynamic>> decryptMetadata(
    String encryptedJson,
  ) async {
    final key = await _getOrCreateKey();
    final Map<String, dynamic> decoded = jsonDecode(encryptedJson);
    final iv = IV.fromBase64(decoded["iv"]);
    final encryptedData = decoded["data"];

    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decrypt(
      Encrypted.fromBase64(encryptedData),
      iv: iv,
    );

    return jsonDecode(decrypted);
  }
}
