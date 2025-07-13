import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'package:docscanner/main.dart'
    show globalNotifier, imageProcessingManager;
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
      Directory(docPath).createSync(recursive: true);
    }
    final file = File("$docPath/metadata.json");
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(
          file,
          supressWarnings: supressWarnings,
        );
      } catch (e) {
        dev.log("Warning, _writeDoc, $keyIn: Reading metadata: $e");
      }
    } else if (!supressWarnings) {
      dev.log(
        "Warning, _writeDoc, $keyIn: No existing metadata, creating new one.",
      );
      file.createSync();
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
        "Warning, saveDocName: Document does not exist: Document $docIndex",
      );
      return null;
    }
    final file = File("$docPath/metadata.json");
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(file);
        return metadata[keyIn];
      } catch (e) {
        dev.log("Warning, _readDoc, $keyIn: $e");
      }
    } else {
      dev.log("Warning, _readDoc, $keyIn: No existing metadata.");
    }
    return null;
  }

  static Future<void> _writePage(
    int docIndex,
    int pageIndex,
    String keyIn,
    dynamic value,
    AppGlobals? gIn,
  ) async {
    gIn ??= g;
    final pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    if (!Directory(pagePath).existsSync()) {
      Directory(pagePath).createSync(recursive: true);
    }
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(file);
      } catch (e) {
        dev.log("Warning, _writePage, $keyIn: $e");
      }
    } else {
      file.createSync();
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
    gIn ??= g;
    final pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    if (!Directory(pagePath).existsSync() && !supressWarnings) {
      dev.log(
        "Warning, _readPage, $keyIn: Page does not exist: Document $docIndex Page $pageIndex",
      );
      return;
    }
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(
          file,
          supressWarnings: supressWarnings,
        );
        return metadata[keyIn];
      } catch (e) {
        if (!supressWarnings) {
          dev.log("Warning, _readPage, $keyIn: No existing metadata: $e");
        }
      }
    } else if (!supressWarnings) {
      dev.log("Warning, _readPage, $keyIn: No existing metadata.");
    }
    return null;
  }

  Future<void> writeDocName(int docIndex, String newName) async {
    _writeDoc(docIndex, "name", newName);
  }

  Future<String?> readDocName(int docIndex) async {
    dynamic value = await _readDoc(docIndex, "name");
    if (value is String && value.isNotEmpty) {
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
    await _writeDoc(docIndex, "unlocked", unlocked ? "true" : "false");

    if (unlocked) {
      // Re-lock after 1 hour
      Future.delayed(Duration(hours: 1)).then((_) async {
        await writeDocUnlocked(docIndex, false);
        globalNotifier.triggerEvent(NotifierEvent.setState);
      });
    }
  }

  Future<bool> readDocUnlocked(int docIndex) async {
    dynamic value = await _readDoc(docIndex, "unlocked");
    if (value is String) {
      return value == "true";
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
      unlocked ? "true" : "false",
      g,
    );

    if (unlocked) {
      // Re-lock after 1 hour
      Future.delayed(Duration(hours: 1)).then((_) async {
        await writePageUnlocked(docIndex, pageIndex, false);
        globalNotifier.triggerEvent(NotifierEvent.setState);
      });
    } else if (!g.proUnlocked) {
      // Change Thumbnail back to non PRO filter
      final currentIndex = await readPageThumbnailIndex(docIndex, pageIndex);
      if (g.proFilterIndexes.contains(currentIndex)) {
        imageProcessingManager.setNewThumbnail(
          docIndex,
          pageIndex,
          g.defaultIndex,
        );
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
      return value == "true";
    } else {
      return false;
    }
  }

  static Future<void> writePageProcessingMetadata(
    int docIndex,
    int pageIndex,
    double? ratioValue,
    List<List<int>>? cornerPoints, {
    AppGlobals? gIn,
  }) async {
    if (ratioValue == 0.0) {
      throw StateError("aspectRatio should not be saved as 0");
    }
    gIn ??= g;
    String pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(file);
      } catch (e) {
        dev.log("Warning, writePageProcessingMetadata, reading: $e");
      }
    }

    try {
      // Write + Encrypt
      if (ratioValue != null) metadata["aspectRatio"] = (ratioValue).toString();
      if (cornerPoints != null) metadata["corners"] = cornerPoints;
      final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
      await file.writeAsString(encrypted);
    } catch (e) {
      dev.log("Warning, writePageProcessingMetadata: $e");
    }
  }

  Future<(double?, List<List<int>>?)> readPageProcessingMetadata(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
    AppGlobals? gIn,
  }) async {
    double? ratioValue;
    List<List<int>>? cornerPoints;

    String pagePath = (gIn != null)
        ? await gIn.filesHelper.getPagePath(docIndex, pageIndex)
        : await g.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      metadata = await MetadataCryptoHelper.decryptMetadata(
        file,
        supressWarnings: supressWarnings,
      );
      try {
        ratioValue = double.tryParse(metadata["aspectRatio"]);
        if (ratioValue == 0.0) {
          throw StateError("aspectRatio should not be saved as 0");
        }
      } catch (e) {
        if (!supressWarnings) {
          dev.log("Warning, readPageProcessingMetadata, ratioValue: $e");
        }
      }
      try {
        cornerPoints = (metadata["corners"] as List)
            .map<List<int>>((e) => (e as List).map((v) => v as int).toList())
            .toList();
      } catch (e) {
        if (!supressWarnings) {
          dev.log("Warning, readPageProcessingMetadata, cornerPoints: $e");
        }
      }
    } else if (!supressWarnings) {
      dev.log(
        "Warning, readPageProcessingMetadata: Metadata does not exist for $pagePath",
      );
    }
    return (ratioValue, cornerPoints);
  }

  static Future<void> writePageThumbnailIndex(
    int docIndex,
    int pageIndex,
    int thumbnailIndexIn, {
    AppGlobals? gIn,
    bool tmpPro = false,
    bool supressWarnings = false,
  }) async {
    gIn ??= g;

    if (gIn.proFilterIndexes.contains(thumbnailIndexIn) &&
        !(gIn.proUnlocked == true) &&
        !tmpPro) {
      thumbnailIndexIn = gIn.defaultIndex;
    }
    String newThumbnailName = versionNamesInternal[thumbnailIndexIn];
    String pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    Map<String, dynamic> metadata = {};

    try {
      // Read + Decrypt
      String? oldThumbnailName;
      if (await file.exists()) {
        try {
          metadata = await MetadataCryptoHelper.decryptMetadata(
            file,
            supressWarnings: supressWarnings,
          );
          oldThumbnailName = metadata["thumbnail"];
        } catch (e) {
          if (!supressWarnings) {
            dev.log("Warning, writePageThumbnailIndex, Read: $e");
          }
        }
      } else if (!supressWarnings) {
        dev.log(
          "Warning, writePageThumbnailIndex: metadata File does not exist (Page $pageIndex, Document $docIndex)",
        );
      }

      // Write new thumbnailIndex
      bool isNewIndex = false;
      if (oldThumbnailName == null || oldThumbnailName != newThumbnailName) {
        isNewIndex = true;
      }
      if (isNewIndex) {
        metadata["thumbnail"] = newThumbnailName;
        final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
        await file.writeAsString(encrypted);
      }
    } catch (e) {
      dev.log("Warning, writePageThumbnailIndex: $e");
    }
  }

  static Future<void> writePageImportedPdf(
    int docIndex,
    int pageIndex,
    bool isImportedPdf, {
    AppGlobals? gIn,
  }) async {
    gIn ??= g;
    await _writePage(
      docIndex,
      pageIndex,
      "importedPdf",
      isImportedPdf ? "true" : "false",
      gIn,
    );
  }

  static Future<bool> readPageImportedPdf(
    int docIndex,
    int pageIndex, {
    bool supressWarnings = false,
    AppGlobals? gIn,
  }) async {
    gIn ??= g;
    dynamic value = await _readPage(
      docIndex,
      pageIndex,
      "importedPdf",
      supressWarnings: supressWarnings,
      gIn: gIn,
    );
    if (value is String) {
      return value == "true";
    } else {
      return false;
    }
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

  static Future<int?> readPageThumbnailIndex(
    int docIndex,
    int pageIndex, {
    AppGlobals? gIn,
    bool supressWarnings = false,
  }) async {
    gIn ??= g;
    dynamic value = await _readPage(
      docIndex,
      pageIndex,
      "thumbnail",
      supressWarnings: supressWarnings,
      gIn: gIn,
    );
    if (value is String) {
      int thumbnailIndex = versionNamesInternal.indexOf(value);
      if (thumbnailIndex == -1) return null;
      return thumbnailIndex;
    } else {
      return null;
    }
  }

  static Future<void> writePageCornerPoints(
    int docIndex,
    int pageIndex,
    List<List<int>> cornerPoints,
  ) async {
    await _writePage(docIndex, pageIndex, "corners", cornerPoints, g);
  }

  static Future<List<List<int>>?> readPageCornerPoints(
    int docIndex,
    int pageIndex, {
    AppGlobals? gIn,
    bool supressWarnings = false,
  }) async {
    gIn ??= g;

    String pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(
          file,
          supressWarnings: supressWarnings,
        );
        List<List<int>> cornerPoints = (metadata["corners"] as List)
            .map<List<int>>(
              (e) => (e as List).map<int>((v) => v as int).toList(),
            )
            .toList();
        return cornerPoints;
      } catch (e) {
        if (!supressWarnings) {
          dev.log("Warning, readPageCornerPoints: $e");
        }
      }
    }
    if (!supressWarnings) {
      dev.log(
        "Warning, readPageCornerPoints: Metadata does not exist for $pagePath",
      );
    }
    return null;
  }

  static Future<void> writeOldVersionFileNames(
    int docIndex,
    int pageIndex,
    List<String> oldVersionFileNames,
  ) async {
    await _writePage(
      docIndex,
      pageIndex,
      "oldVersionFileNames",
      oldVersionFileNames,
      g,
    );
  }

  static Future<List<String>?> readOldPageFileNames(
    int docIndex,
    int pageIndex, {
    AppGlobals? gIn,
    bool supressWarnings = false,
  }) async {
    gIn ??= g;

    String pagePath = await gIn.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (await file.exists()) {
      try {
        metadata = await MetadataCryptoHelper.decryptMetadata(
          file,
          supressWarnings: supressWarnings,
        );
        List<String> oldVersionFileNames =
            (metadata["oldVersionFileNames"] as List)
                .map<String>((e) => e as String)
                .toList();
        return oldVersionFileNames;
      } catch (e) {
        if (!supressWarnings) {
          dev.log("Warning, readOldVersionFileNames: $e");
        }
      }
    }
    if (!supressWarnings) {
      dev.log(
        "Warning, readOldVersionFileNames: Metadata does not exist for $pagePath",
      );
    }
    return null;
  }

  static Future<String?> readOldThumbnailVersionFileName(
    int docIndex,
    int pageIndex, {
    AppGlobals? gIn,
    bool supressWarnings = false,
  }) async {
    gIn ??= g;

    List<String>? names = await readOldPageFileNames(
      docIndex,
      pageIndex,
      gIn: gIn,
      supressWarnings: supressWarnings,
    );
    final int versionIndex =
        await readPageThumbnailIndex(docIndex, pageIndex) ?? gIn.defaultIndex;

    return names == null ? null : names[versionIndex];
  }
}

class MetadataCryptoHelper {
  static const _storageKey = "encryption_key";
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
      dev.log("Warning, _getOrCreateKey: $e");
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
      dev.log("Warning, encryptMetadata: $e");
      throw StateError("encryptMetadata: $e");
    }
  }

  static Future<Map<String, dynamic>> decryptMetadata(
    File metadataFile, {
    RootIsolateToken? token,
    bool supressWarnings = false,
  }) async {
    final String encryptedJson = metadataFile.readAsStringSync();
    if (encryptedJson.isEmpty) {
      if (!supressWarnings) dev.log("Warning, decryptMetadata: no metadata");
      return {};
    }
    try {
      final key = await _getOrCreateKey(token);
      final Map<String, dynamic> decodedJson = jsonDecode(encryptedJson);
      final iv = IV.fromBase64(decodedJson["iv"]);
      final encryptedData = decodedJson["data"];

      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final decrypted = encrypter.decrypt(
        Encrypted.fromBase64(encryptedData),
        iv: iv,
      );

      return jsonDecode(decrypted);
    } catch (e) {
      if (!supressWarnings) dev.log("Warning, decryptMetadata: $e");
      throw StateError("decryptMetadata: $e");
    }
  }
}
