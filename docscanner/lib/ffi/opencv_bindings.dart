import 'dart:io';
import 'dart:typed_data';

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' show malloc;

final ffi.DynamicLibrary nativeLib = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libopencv_wrapper.so')
    : throw UnsupportedError('Only Android supported');

// ----------------- Typedefs -----------------

typedef _WarpImageNative =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8>, // input pointer
      ffi.Int32, // input length
      ffi.Pointer<ffi.Int32>, // output length
    );
typedef _WarpImageDart =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Int32>,
    );

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

// ----------------- Lookup functions -----------------

final _WarpImageDart _warpImageNative = nativeLib
    .lookup<ffi.NativeFunction<_WarpImageNative>>('warpImage')
    .asFunction<_WarpImageDart>();

/// Free memory that was allocated in the library
final _FreeDart _freeNative = nativeLib
    .lookup<ffi.NativeFunction<_FreeNative>>('free')
    .asFunction<_FreeDart>();

// ----------------- Public functions -----------------

/// Calls native warpImage and returns a Dart-owned [Uint8List].
/// The native allocation is freed after the copy.
Future<Uint8List> warpImage(Uint8List inputBytes) async {
  final int inputLength = inputBytes.length;

  // Allocate native input buffer & copy Dart bytes into it
  final ffi.Pointer<ffi.Uint8> inputPtr = malloc.allocate<ffi.Uint8>(
    inputLength,
  );
  inputPtr.asTypedList(inputLength).setAll(0, inputBytes);

  // Allocate native output length int
  final ffi.Pointer<ffi.Int32> outLenPtr = malloc.allocate<ffi.Int32>(1);

  // Call the native function
  final ffi.Pointer<ffi.Uint8> resultPtr = _warpImageNative(
    inputPtr,
    inputLength,
    outLenPtr,
  );
  final int outLen = outLenPtr.value;

  // Copy native output buffer into a Dart-owned Uint8List
  final Uint8List result = Uint8List.fromList(resultPtr.asTypedList(outLen));

  // Free native buffers
  _freeNative(resultPtr.cast<ffi.Void>());
  malloc.free(inputPtr);
  malloc.free(outLenPtr);

  return result;
}
