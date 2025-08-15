import 'dart:io';

import 'dart:ffi' as ffi;
import 'package:docscanner/app/app_globals.dart' show AspectRatioInfo;
import 'package:ffi/ffi.dart' show calloc, malloc, StringUtf8Pointer;

final ffi.DynamicLibrary _nativeLib = Platform.isAndroid
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

typedef _ProcessorSetAvailableAspectRatiosNative =
    ffi.Void Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Double>, // pointer to the array
      ffi.Int32, // length of the array
    );
typedef _ProcessorSetAvailableAspectRatiosDart =
    void Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Double>,
      int,
    );

typedef _ProcessorWarpImageNative =
    ffi.Int32 Function(
      ffi.Pointer<ImageProcessorHandle>, // processor
      ffi.Pointer<ffi.Int8>, // inWarpedPath
      ffi.Pointer<ffi.Double>, // inOutRatioValue
      ffi.Pointer<ffi.Int32>, // inOutCorners
      ffi.Bool, // passingInCorners
    );
typedef _ProcessorWarpImageDart =
    int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>,
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Int32>,
      bool,
    );

typedef _ProcessorContrastImageNative =
    ffi.Int32 Function(
      ffi.Pointer<ImageProcessorHandle>, // processor
      ffi.Pointer<ffi.Int8>, // inContrastPath
    );
typedef _ProcessorContrastImageDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

// ----------------- Lookup functions -----------------

final _createProcessor = _nativeLib
    .lookup<ffi.NativeFunction<_CreateProcessorNative>>('createProcessor')
    .asFunction<_CreateProcessorDart>();

final _freeProcessor = _nativeLib
    .lookup<ffi.NativeFunction<_FreeProcessorNative>>('freeProcessor')
    .asFunction<_FreeProcessorDart>();

final _processorLoadPhoto = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorLoadPhotoNative>>('processorLoadPhoto')
    .asFunction<_ProcessorLoadPhotoDart>();

final _processorSetAvailableAspectRatios = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorSetAvailableAspectRatiosNative>>(
      'processorSetAvailableAspectRatios',
    )
    .asFunction<_ProcessorSetAvailableAspectRatiosDart>();

final _processorWarpImage = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorWarpImageNative>>('processorWarpImage')
    .asFunction<_ProcessorWarpImageDart>();

final _ProcessorContrastImageDart _processorContrastImage = _nativeLib
    .lookupFunction<_ProcessorContrastImageNative, _ProcessorContrastImageDart>(
      'processorContrastImage',
    );

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

  void setAvailableAspectRatios(List<AspectRatioInfo> gAvailableAspectRatios) {
    final length = gAvailableAspectRatios.length;
    final ptr = malloc<ffi.Double>(length);
    for (var i = 0; i < length; i++) {
      ptr[i] = gAvailableAspectRatios[i].value;
    }

    _processorSetAvailableAspectRatios(_handle, ptr, length);

    malloc.free(ptr);
  }

  (
    double, // ratioValue
    List<List<int>>, // corners
  )
  warpImage(
    String warpedPath,
    double? ratioValueIn,
    List<List<int>>? cornerPointsIn,
  ) {
    const cornerCount = 4;
    final warpedPathPtr = warpedPath.toNativeUtf8().cast<ffi.Int8>();

    // Aspect ratio pointer
    final ratioPtr = malloc.allocate<ffi.Double>(1)..value = ratioValueIn ?? 0;

    // Corners pointer
    final cornersPtr = calloc<ffi.Int32>(cornerCount * 2);
    if (cornerPointsIn != null) {
      for (int i = 0; i < cornerCount; i++) {
        cornersPtr[i * 2] = cornerPointsIn[i][0];
        cornersPtr[i * 2 + 1] = cornerPointsIn[i][1];
      }
    } else {
      for (int i = 0; i < cornerCount * 2; i++) {
        cornersPtr[i] = 0;
      }
    }

    final result = _processorWarpImage(
      _handle,
      warpedPathPtr,
      ratioPtr,
      cornersPtr,
      cornerPointsIn != null,
    );

    malloc.free(warpedPathPtr);

    if (result == 0) {
      if (ratioPtr != ffi.nullptr) malloc.free(ratioPtr);
      if (cornersPtr != ffi.nullptr) calloc.free(cornersPtr);
      throw Exception('Native error, warpImage: Processing / Saving failed');
    }

    // Read outputs
    final ratioOut = ratioPtr == ffi.nullptr ? 0.0 : ratioPtr.value;

    List<List<int>> cornersOut = [];
    final flat = cornersPtr.asTypedList(cornerCount * 2);
    for (int i = 0; i < cornerCount; i++) {
      cornersOut.add([flat[i * 2], flat[i * 2 + 1]]);
    }

    if (ratioPtr != ffi.nullptr) malloc.free(ratioPtr);
    if (cornersPtr != ffi.nullptr) calloc.free(cornersPtr);

    return (ratioOut, cornersOut);
  }

  void contrastImage(String contrastPath) {
    final contrastPathPtr = contrastPath.toNativeUtf8().cast<ffi.Int8>();

    final result = _processorContrastImage(_handle, contrastPathPtr);

    malloc.free(contrastPathPtr);

    if (result == 0) {
      throw Exception(
        'Native error, contrastImage: Processing / Saving failed',
      );
    }
  }
}
