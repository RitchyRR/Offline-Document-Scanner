import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
// my packages:
import 'package:docscanner/app_globals.dart';
import 'package:docscanner/image_prosessing_manager.dart';
// encryption:
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart';

class MetadataHelper {
  static Future<void> _writeDoc(
    int docIndex,
    String keyIn,
    dynamic valueIn, {
    bool supressWarnings = false,
  }) async {
    final docPath = await g.filesHelper.getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Error, _writeDoc, $keyIn: Document does not exist: Document $docIndex",
      );
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
        dev.log("Error, _writeDoc, $keyIn: Reading metadata: $e");
      }
    } else if (!supressWarnings) {
      dev.log(
        "Warning, _writeDoc, $keyIn: No existing metadata, creating new one.",
      );
    }

    // Write + Encrypt
    metadata[keyIn] = valueIn;
    final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
    await file.writeAsString(encrypted);
  }

  static Future<dynamic> _readDoc(int docIndex, String keyIn) async {
    final docPath = await g.filesHelper.getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Error, saveDocName: Document does not exist: Document $docIndex",
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
        dev.log("Error, _readDoc, $keyIn: $e");
      }
    } else {
      dev.log("Error, _readDoc, $keyIn: No existing metadata.");
    }
    return null;
  }

  static Future<void> _writePage(
    int docIndex,
    int pageIndex,
    String keyIn,
    dynamic value,
  ) async {
    final pagePath = await g.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    if (!Directory(pagePath).existsSync()) {
      dev.log(
        "Error, _writePage, $keyIn: Page does not exist: Document $docIndex Page $pageIndex",
      );
      return;
    }
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      } catch (e) {
        dev.log("Error, _writePage, $keyIn: $e");
      }
    }

    // Write + Encrypt
    metadata[keyIn] = value;
    final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
    await file.writeAsString(encrypted);
  }

  static Future<dynamic> _readPage(
    int docIndex,
    int pageIndex,
    String keyIn, {
    bool supressWarnings = false,
    AppGlobals? gIn,
  }) async {
    bool isIsolate = false;
    if (gIn != null) isIsolate = true;
    final pagePath =
        await (isIsolate
            ? gIn!.filesHelper.getPagePath(docIndex, pageIndex)
            : g.filesHelper.getPagePath(docIndex, pageIndex));
    final file = File('$pagePath/metadata.json');
    if (!Directory(pagePath).existsSync()) {
      dev.log(
        "Error, _readPage, $keyIn: Page does not exist: Document $docIndex Page $pageIndex",
      );
      return;
    }
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
        return metadata[keyIn];
      } catch (e) {
        dev.log("Error, _readPage, $keyIn: No existing metadata: $e");
      }
    } else if (!supressWarnings) {
      dev.log("Error, _readPage, $keyIn: No existing metadata.");
    }
    return null;
  }

  Future<void> writeDocName(int docIndex, String newName) async {
    _writeDoc(docIndex, "name", newName);
  }

  Future<String?> readDocName(int docIndex) async {
    dynamic value = await _readDoc(docIndex, "name");
    if (value is String) {
      return value;
    } else {
      return null;
    }
  }

  Future<void> writeDocDate(
    int docIndex,
    String newDate, {
    bool supressWarnings = false,
  }) async {
    await _writeDoc(
      docIndex,
      "date",
      newDate,
      supressWarnings: supressWarnings,
    );
  }

  Future<String?> readDocDate(int docIndex) async {
    dynamic value = await _readDoc(docIndex, "date");
    if (value is String) {
      return value;
    } else {
      return null;
    }
  }

  Future<void> writeDocUnlocked(int docIndex, bool unlocked) async {
    await _writeDoc(docIndex, "unlocked", unlocked ? 'true' : 'false');

    if (unlocked) {
      // Re-lock after 1 hour
      Future.delayed(Duration(hours: 1)).then((_) {
        writeDocUnlocked(docIndex, false);
      });
    }
  }

  Future<bool> readDocUnlocked(int docIndex) async {
    dynamic value = await _readDoc(docIndex, "unlocked");
    if (value is String) {
      return value == 'true';
    } else {
      return false;
    }
  }

  Future<void> writePageUnlocked(
    int docIndex,
    int pageIndex,
    bool unlocked,
  ) async {
    await _writePage(
      docIndex,
      pageIndex,
      "unlocked",
      unlocked ? 'true' : 'false',
    );

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
  }

  Future<bool> readPageUnlocked(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    dynamic value = await _readPage(
      docIndex,
      pageIndex,
      "unlocked",
      supressWarnings: supressWarnings,
    );
    if (value is String) {
      return value == 'true';
    } else {
      return false;
    }
  }

  static Future<void> writePageProcessingMetadata(
    int docIndex,
    int pageIndex,
    double? ratioValue,
    int? orientationIndex,
    List<List<int>>? cornerPoints, {
    AppGlobals? gIn,
  }) async {
    if (ratioValue == 0.0) {
      throw StateError("aspectRatio should not be saved as 0");
    }
    bool isIsolate = false;
    if (gIn != null) isIsolate = true;
    String pagePath = await (isIsolate ? gIn!.filesHelper : g.filesHelper)
        .getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      } catch (e) {
        dev.log("Error, writePageMetadata, reading: $e");
      }
    }

    try {
      // Write + Encrypt
      if (ratioValue != null) metadata["aspectRatio"] = (ratioValue).toString();
      if (orientationIndex != null) {
        metadata["orientation"] =
            orientationIndex == 0 ? "portrait" : "landscape";
      }
      if (cornerPoints != null) metadata["corners"] = cornerPoints;
      final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
      await file.writeAsString(encrypted);
    } catch (e) {
      dev.log("Error, writePageMetadata: $e");
    }
  }

  Future<(double?, int?, List<List<int>>?)> readPageProcessingMetadata(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    double? ratioValue;
    int? orientationIndex;
    List<List<int>>? cornerPoints;

    String pagePath = await g.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      final encryptedContent = file.readAsStringSync();
      metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      try {
        ratioValue = double.tryParse(metadata["aspectRatio"]);
        if (ratioValue == 0.0) {
          throw StateError("aspectRatio should not be saved as 0");
        }
      } catch (e) {
        dev.log("Error, readPageMetadata, ratioValue: $e");
      }
      try {
        String orientationString = metadata["orientation"];
        orientationIndex = (orientationString == "portrait") ? 0 : 1;
      } catch (e) {
        dev.log("Error, readPageMetadata, orientationString: $e");
      }
      try {
        cornerPoints =
            (metadata["corners"] as List)
                .map<List<int>>(
                  (e) => (e as List).map((v) => v as int).toList(),
                )
                .toList();
      } catch (e) {
        dev.log("Error, readPageMetadata, cornerPoints: $e");
      }
    } else if (!supressWarnings) {
      dev.log(
        "Warning, readPageMetadata: Metadata does not exist for $pagePath",
      );
    }
    return (ratioValue, orientationIndex, cornerPoints);
  }

  static Future<bool> writePageThumbnailIndex(
    int docIndex,
    int pageIndex,
    int thumbnailIndexIn, {
    AppGlobals? gIn,
    bool tmpPro = false,
  }) async {
    bool isIsolate = false;
    if (gIn != null) isIsolate = true;

    bool isNewIndex = false;

    if (thumbnailIndexIn == 0) return false;
    if (thumbnailIndexIn == 3 &&
        !(isIsolate ? gIn!.proUnlocked == true : g.proUnlocked == true) &&
        !tmpPro) {
      thumbnailIndexIn = 2;
    }
    String newThumbnailName = versionNames[thumbnailIndexIn];
    String pagePath =
        await (isIsolate
            ? gIn!.filesHelper.getPagePath(docIndex, pageIndex)
            : g.filesHelper.getPagePath(docIndex, pageIndex));
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    try {
      // Read + Decrypt
      String? oldThumbnailName;
      if (await file.exists()) {
        try {
          final encryptedContent = file.readAsStringSync();
          metadata = await MetadataCryptoHelper.decryptMetadata(
            encryptedContent,
          );
          oldThumbnailName = metadata["thumbnail"];
        } catch (e) {
          dev.log("Error, writePageThumbnailIndex, Read: $e");
        }
      } else {
        dev.log(
          "Warning, writePageThumbnailIndex: metadata File does not exist (Page $pageIndex, Document $docIndex)",
        );
      }
      if (oldThumbnailName == null || oldThumbnailName != newThumbnailName) {
        isNewIndex = true;
      }

      // Write + Encrypt
      if (isNewIndex) {
        metadata["thumbnail"] = newThumbnailName;
        final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
        await file.writeAsString(encrypted);
      }
    } catch (e) {
      dev.log("Error, writePageThumbnailIndex: $e");
    }
    return isNewIndex;
  }

  static Future<void> writePageCornerPoints(
    int docIndex,
    int pageIndex,
    List<List<int>> cornerPoints,
  ) async {
    await _writePage(docIndex, pageIndex, "corners", cornerPoints);
  }

  static Future<double?> readPageRatioValue(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    dynamic value = await _readPage(
      docIndex,
      pageIndex,
      "aspectRatio",
      supressWarnings: supressWarnings,
    );
    if (value is String) {
      double? ratioValue = double.tryParse(value);
      if (ratioValue == 0.0) {
        throw StateError("aspectRatio should not be saved as 0");
      }
      return ratioValue;
    } else {
      return null;
    }
  }

  static Future<int?> readPageOrientationIndex(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
  }) async {
    dynamic value = await _readPage(
      docIndex,
      pageIndex,
      "orientation",
      supressWarnings: supressWarnings,
    );
    if (value is String) {
      return (value == "portrait") ? 0 : 1;
    } else {
      return null;
    }
  }

  static Future<int> readPageThumbnailIndex(
    int docIndex,
    int pageIndex, {
    AppGlobals? gIn,
    bool supressWarnings = false,
  }) async {
    bool isIsolate = false;
    if (gIn != null) isIsolate = true;

    dynamic value = await _readPage(
      docIndex,
      pageIndex,
      "thumbnail",
      supressWarnings: supressWarnings,
      gIn: gIn,
    );
    if (value is String) {
      int thumbnailIndex = versionNames.indexOf(value);
      if (thumbnailIndex == 0) {
        throw StateError('metadata: thumbnail cant be the photo');
      }
      return thumbnailIndex;
    } else {
      return (isIsolate ? gIn!.proUnlocked == true : g.proUnlocked == true)
          ? 3
          : 2;
    }
  }

  static Future<List<List<int>>> readPageCornerPoints(
    int docIndex,
    int pageIndex, {
    AppGlobals? gIn,
    bool supressWarnings = false,
  }) async {
    bool isIsolate = false;
    if (gIn != null) isIsolate = true;

    String pagePath = await (isIsolate ? gIn!.filesHelper : g.filesHelper)
        .getPagePath(docIndex, pageIndex);
    final file = File('$pagePath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
        List<List<int>> cornerPoints =
            (metadata["corners"] as List)
                .map<List<int>>(
                  (e) => (e as List).map((v) => v as int).toList(),
                )
                .toList();
        return cornerPoints;
      } catch (e) {
        dev.log("Error, readPageCornerPoints: $e");
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

  static Future<Key> _getOrCreateKey(RootIsolateToken? token) async {
    try {
      if (token != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      }
      String? keyBase64 = await _secureStorage.read(key: _storageKey);

      if (keyBase64 == null) {
        final random = math.Random.secure();
        final keyBytes = List<int>.generate(
          _keySize,
          (_) => random.nextInt(256),
        );
        keyBase64 = base64UrlEncode(keyBytes);
        await _secureStorage.write(key: _storageKey, value: keyBase64);
      }

      return Key(base64Url.decode(keyBase64));
    } catch (e) {
      dev.log("Error, _getOrCreateKey: $e");
      throw StateError("_getOrCreateKey: $e");
    }
  }

  static Future<String> encryptMetadata(
    Map<String, dynamic> metadata, {
    RootIsolateToken? token,
  }) async {
    try {
      final key = await _getOrCreateKey(token);
      final iv = IV.fromSecureRandom(16);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

      final encrypted = encrypter.encrypt(jsonEncode(metadata), iv: iv);
      final encryptedWithIv = jsonEncode({
        "iv": base64UrlEncode(iv.bytes),
        "data": encrypted.base64,
      });

      return encryptedWithIv;
    } catch (e) {
      dev.log("Error, encryptMetadata: $e");
      throw StateError("encryptMetadata: $e");
    }
  }

  static Future<Map<String, dynamic>> decryptMetadata(
    String encryptedJson, {
    RootIsolateToken? token,
  }) async {
    try {
      final key = await _getOrCreateKey(token);
      final Map<String, dynamic> decoded = jsonDecode(encryptedJson);
      final iv = IV.fromBase64(decoded["iv"]);
      final encryptedData = decoded["data"];

      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final decrypted = encrypter.decrypt(
        Encrypted.fromBase64(encryptedData),
        iv: iv,
      );

      return jsonDecode(decrypted);
    } catch (e) {
      dev.log("Error, decryptMetadata: $e");
      throw StateError("decryptMetadata: $e");
    }
  }
}
