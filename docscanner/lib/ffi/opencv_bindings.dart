import 'dart:io';

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' show malloc, StringUtf8Pointer;

final ffi.DynamicLibrary nativeLib = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libopencv_wrapper.so')
    : throw UnsupportedError('Only Android supported');

final class ImageProcessorHandle extends ffi.Opaque {}

// ----------------- Typedefs -----------------

typedef _CreateProcessorNative = ffi.Pointer<ImageProcessorHandle> Function();
typedef _CreateProcessorDart = ffi.Pointer<ImageProcessorHandle> Function();

typedef _FreeProcessorNative =
    ffi.Void Function(ffi.Pointer<ImageProcessorHandle>);
typedef _FreeProcessorDart = void Function(ffi.Pointer<ImageProcessorHandle>);

typedef _ProcessorLoadPhotoNative =
    ffi.Int32 Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>,
    );
typedef _ProcessorLoadPhotoDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _ProcessorWarpImageNative =
    ffi.Int32 Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>,
    );
typedef _ProcessorWarpImageDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

// ----------------- Lookup functions -----------------

final _createProcessor = nativeLib
    .lookup<ffi.NativeFunction<_CreateProcessorNative>>('createProcessor')
    .asFunction<_CreateProcessorDart>();

final _freeProcessor = nativeLib
    .lookup<ffi.NativeFunction<_FreeProcessorNative>>('freeProcessor')
    .asFunction<_FreeProcessorDart>();

final _processorLoadPhoto = nativeLib
    .lookup<ffi.NativeFunction<_ProcessorLoadPhotoNative>>('processorLoadPhoto')
    .asFunction<_ProcessorLoadPhotoDart>();

final _processorWarpImage = nativeLib
    .lookup<ffi.NativeFunction<_ProcessorWarpImageNative>>('processorWarpImage')
    .asFunction<_ProcessorWarpImageDart>();

// ----------------- Public functions -----------------

class ImageProcessor {
  late final ffi.Pointer<ImageProcessorHandle> _handle;

  ImageProcessor() {
    _handle = _createProcessor();
    if (_handle.address == 0) {
      throw Exception('Native error: Failed to create ImageProcessor');
    }
  }

  void dispose() {
    _freeProcessor(_handle);
  }

  void loadPhoto(String path) {
    final pathPtr = path.toNativeUtf8().cast<ffi.Int8>();
    final result = _processorLoadPhoto(_handle, pathPtr);
    malloc.free(pathPtr);
    if (result == 0) throw Exception('Native error, loadPhoto: $path');
  }

  void warpImage(String outPath) {
    final pathPtr = outPath.toNativeUtf8().cast<ffi.Int8>();
    final result = _processorWarpImage(_handle, pathPtr);
    malloc.free(pathPtr);
    if (result == 0) {
      throw Exception(
        'Native error, warpImage: Processing / Saving failed to $outPath',
      );
    }
  }
}
