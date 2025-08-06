import 'dart:ffi' as dffi;
import 'dart:typed_data';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;

final dffi.DynamicLibrary nativeLib = Platform.isAndroid
    ? dffi.DynamicLibrary.open("libopencv_wrapper.so")
    : throw UnsupportedError("Only Android is supported");

typedef _WarpImageNative =
    dffi.Pointer<dffi.Uint8> Function(
      dffi.Pointer<dffi.Uint8>,
      dffi.Int32,
      dffi.Pointer<dffi.Int32>,
    );
typedef WarpImageDart =
    dffi.Pointer<dffi.Uint8> Function(
      dffi.Pointer<dffi.Uint8>,
      int,
      dffi.Pointer<dffi.Int32>,
    );

final WarpImageDart warpImageNative = nativeLib
    .lookup<dffi.NativeFunction<_WarpImageNative>>('warpImage')
    .asFunction();

Future<Uint8List> warpImage(Uint8List inputBytes) async {
  final inputPtr = ffi.malloc.allocate<dffi.Uint8>(inputBytes.length);
  final outLenPtr = ffi.malloc.allocate<dffi.Int32>(1);

  // Copy input into allocated memory
  inputPtr.asTypedList(inputBytes.length).setAll(0, inputBytes);

  // Call native function
  final resultPtr = warpImageNative(inputPtr, inputBytes.length, outLenPtr);
  final outLen = outLenPtr.value;

  // Convert result back to Dart
  final result = resultPtr.asTypedList(outLen);

  // Clean up
  ffi.malloc.free(inputPtr);
  ffi.malloc.free(outLenPtr);
  // ⚠️ You must free resultPtr in native code eventually

  return Uint8List.fromList(result);
}
