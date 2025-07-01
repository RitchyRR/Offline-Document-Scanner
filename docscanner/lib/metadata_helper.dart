import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'package:docscanner/main.dart' show globalNotifier;
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
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
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
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
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
  ) async {
    final pagePath = await g.filesHelper.getPagePath(docIndex, pageIndex);
    final file = File("$pagePath/metadata.json");
    if (!Directory(pagePath).existsSync()) {
      Directory(pagePath).createSync(recursive: true);
    }
    Map<String, dynamic> metadata = {};

    // Read + Decrypt
    if (file.existsSync()) {
      try {
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
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
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
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
    );

    if (unlocked) {
      // Re-lock after 1 hour
      Future.delayed(Duration(hours: 1)).then((_) async {
        await writePageUnlocked(docIndex, pageIndex, false);
        globalNotifier.triggerEvent(NotifierEvent.setState);
      });
    } else {
      final currentIndex = await readPageThumbnailIndex(docIndex, pageIndex);
      if (g.proFilterIndexes.contains(currentIndex)) {
        writePageThumbnailIndex(docIndex, pageIndex, g.defaultIndexes.$1);
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
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      } catch (e) {
        dev.log("Warning, writePageMetadata, reading: $e");
      }
    }

    try {
      // Write + Encrypt
      metadata["aspectRatio"] = (ratioValue).toString();
      metadata["corners"] = cornerPoints;
      final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
      await file.writeAsString(encrypted);
    } catch (e) {
      dev.log("Warning, writePageMetadata: $e");
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
      final encryptedContent = file.readAsStringSync();
      metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
      try {
        ratioValue = double.tryParse(metadata["aspectRatio"]);
        if (ratioValue == 0.0) {
          throw StateError("aspectRatio should not be saved as 0");
        }
      } catch (e) {
        dev.log("Warning, readPageMetadata, ratioValue: $e");
      }
      try {
        cornerPoints = (metadata["corners"] as List)
            .map<List<int>>((e) => (e as List).map((v) => v as int).toList())
            .toList();
      } catch (e) {
        dev.log("Warning, readPageMetadata, cornerPoints: $e");
      }
    } else if (!supressWarnings) {
      dev.log(
        "Warning, readPageMetadata: Metadata does not exist for $pagePath",
      );
    }
    return (ratioValue, cornerPoints);
  }

  static Future<bool> writePageThumbnailIndex(
    int docIndex,
    int pageIndex,
    int thumbnailIndexIn, {
    AppGlobals? gIn,
    bool tmpPro = false,
    bool supressWarnings = false,
  }) async {
    gIn ??= g;

    bool isNewIndex = false;

    if (gIn.proFilterIndexes.contains(thumbnailIndexIn) &&
        !(gIn.proUnlocked == true) &&
        !tmpPro) {
      thumbnailIndexIn = gIn.defaultIndexes.$1;
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
          final encryptedContent = file.readAsStringSync();
          metadata = await MetadataCryptoHelper.decryptMetadata(
            encryptedContent,
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
      if (oldThumbnailName == null || oldThumbnailName != newThumbnailName) {
        isNewIndex = true;
      }

      // Write + Encrypt
      if (isNewIndex) {
        if (newThumbnailName == "contrast") {
          dev.log("contrast, toto remove");
        }
        metadata["thumbnail"] = newThumbnailName;
        final encrypted = await MetadataCryptoHelper.encryptMetadata(metadata);
        await file.writeAsString(encrypted);
      }
    } catch (e) {
      dev.log("Warning, writePageThumbnailIndex: $e");
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

  static Future<List<List<int>>> readPageCornerPoints(
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
        final encryptedContent = file.readAsStringSync();
        metadata = await MetadataCryptoHelper.decryptMetadata(encryptedContent);
        List<List<int>> cornerPoints = (metadata["corners"] as List)
            .map<List<int>>((e) => (e as List).map((v) => v as int).toList())
            .toList();
        return cornerPoints;
      } catch (e) {
        dev.log("Warning, readPageCornerPoints: $e");
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
      dev.log("Warning, decryptMetadata: $e");
      throw StateError("decryptMetadata: $e");
    }
  }
}
