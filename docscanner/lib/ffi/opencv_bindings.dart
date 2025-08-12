import 'dart:developer' as dev show log;
import 'dart:io';

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' show malloc, StringUtf8Pointer;

final ffi.DynamicLibrary nativeLib = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libopencv_wrapper.so')
    : throw UnsupportedError('Only Android supported');

final bool warpImageFound = nativeLib.providesSymbol('warpImage');
final bool freeBufferFound = nativeLib.providesSymbol('freeBuffer');

// ----------------- Typedefs -----------------

typedef _WarpImageNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Int8>, // inPhotoPath
      ffi.Pointer<ffi.Int8>, // inWarpedPath
    );
typedef _WarpImageDart =
    int Function(ffi.Pointer<ffi.Int8>, ffi.Pointer<ffi.Int8>);

typedef _FreeBufferNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeBufferDart = void Function(ffi.Pointer<ffi.Void>);

// ----------------- Lookup functions -----------------

final _WarpImageDart _warpImageNative = nativeLib
    .lookup<ffi.NativeFunction<_WarpImageNative>>('warpImage')
    .asFunction<_WarpImageDart>();

/// Free memory that was allocated in the library
final _FreeBufferDart _freeNative = nativeLib
    .lookup<ffi.NativeFunction<_FreeBufferNative>>('freeBuffer')
    .asFunction<_FreeBufferDart>();

// ----------------- Public functions -----------------

Future<void> warpImage(String photoPath, String warpedPath) async {
  if (!warpImageFound) dev.log("Lib has no 'warpImage' function");
  if (!freeBufferFound) dev.log("Lib has no 'freeBuffer' function");

  // Convert Dart strings to native UTF-8 pointers
  final ffi.Pointer<ffi.Int8> photoPathPtr = photoPath
      .toNativeUtf8()
      .cast<ffi.Int8>();
  final ffi.Pointer<ffi.Int8> warpedPathPtr = warpedPath
      .toNativeUtf8()
      .cast<ffi.Int8>();

  final int result = _warpImageNative(photoPathPtr, warpedPathPtr);

  // Free allocated memory for strings
  malloc.free(photoPathPtr);
  malloc.free(warpedPathPtr);

  if (result == 0) {
    throw Exception('warpImage failed for $photoPath → $warpedPath');
  }
}
