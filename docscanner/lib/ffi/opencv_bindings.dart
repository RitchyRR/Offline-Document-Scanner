import 'dart:developer' as dev show log;
import 'dart:io';
import 'dart:typed_data';

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' show malloc;

final ffi.DynamicLibrary nativeLib = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libopencv_wrapper.so')
    : throw UnsupportedError('Only Android supported');

final bool warpImageFound = nativeLib.providesSymbol('warpImage');
final bool freeBufferFound = nativeLib.providesSymbol('freeBuffer');

// ----------------- Typedefs -----------------

typedef _WarpImageNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Uint8>, // inBytes
      ffi.Int32, // inLength
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>, // outBytes (pointer to pointer)
      ffi.Pointer<ffi.Int32>, // outLength
    );
typedef _WarpImageDart =
    void Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Int32>,
    );

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

Future<Uint8List> warpImage(Uint8List inputBytes) async {
  if (!warpImageFound) dev.log("Lib has no 'warpImage' function");
  if (!freeBufferFound) dev.log("Lib has no 'freeBuffer' function");

  final int inputLength = inputBytes.length;

  // Allocate native input buffer & copy Dart bytes into it
  final ffi.Pointer<ffi.Uint8> inputPtr = malloc.allocate<ffi.Uint8>(
    inputLength,
  );
  inputPtr.asTypedList(inputLength).setAll(0, inputBytes);

  // Allocate output
  final outBytesPtrPtr = malloc.allocate<ffi.Pointer<ffi.Uint8>>(1);
  final outLenPtr = malloc.allocate<ffi.Int32>(1);

  _warpImageNative(inputPtr, inputLength, outBytesPtrPtr, outLenPtr);

  // Copy into Dart-owned list
  final result = Uint8List.fromList(
    outBytesPtrPtr.value.asTypedList(outLenPtr.value),
  );

  // Free memory
  _freeNative(outBytesPtrPtr.value.cast<ffi.Void>());
  malloc.free(outBytesPtrPtr);
  malloc.free(inputPtr);
  malloc.free(outLenPtr);

  return result;
}
