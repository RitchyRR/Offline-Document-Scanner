import 'dart:io';

import 'dart:ffi' as ffi;
import 'package:docscanner/app/app_globals.dart'
    show AspectRatioInfo, AppGlobals;
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

typedef _ProcessorImportPhotoNative =
    ffi.Int32 Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>, // inSourcePath
      ffi.Pointer<ffi.Int8>, // inPhotoPath
    );
typedef _ProcessorImportPhotoDart =
    int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>,
      ffi.Pointer<ffi.Int8>,
    );

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
      ffi.Pointer<ImageProcessorHandle>,
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

typedef _ProcessorContrastFilterNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>, // inContrastPath
    );
typedef _ProcessorContrastFilterDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _ProcessorDocumentFilterNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>, // processor
      ffi.Pointer<ffi.Int8>, // inDocumentPath
    );
typedef _ProcessorDocumentFilterDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _ProcessorProFilterNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>, // processor
      ffi.Pointer<ffi.Int8>, // inProPath
    );
typedef _ProcessorProFilterDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _ProcessorProColorFilterNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>, // processor
      ffi.Pointer<ffi.Int8>, // inProColorPath
    );
typedef _ProcessorProColorFilterDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _RotateImageNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Int8>, // inSourcePath
      ffi.Pointer<ffi.Int8>, // inRotatedPath
      ffi.Int, // angle
    );
typedef _RotateImageDart =
    int Function(ffi.Pointer<ffi.Int8>, ffi.Pointer<ffi.Int8>, int);

typedef _ScaleImageToWidthNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Int8>, // inSourcePath
      ffi.Pointer<ffi.Int8>, // inScaledPath
      ffi.Int, // inNewWidth
      ffi.Pointer<ffi.Int>, // outNewHeight
    );
typedef _ScaleImageToWidthDart =
    int Function(
      ffi.Pointer<ffi.Int8>,
      ffi.Pointer<ffi.Int8>,
      int,
      ffi.Pointer<ffi.Int>,
    );

typedef _ScaleImageToMaxSizeNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Int8>, // inSourcePath
      ffi.Pointer<ffi.Int8>, // inScaledPath
      ffi.Int, // inMaxSize
    );
typedef _ScaleImageToMaxSizeDart =
    int Function(ffi.Pointer<ffi.Int8>, ffi.Pointer<ffi.Int8>, int);

typedef _ProcessorMatchAspectRatioAndOrientationNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Double, // inCalculatedRatio
      ffi.Pointer<ffi.Double>, // outMatchingRatio
    );
typedef _ProcessorMatchAspectRatioAndOrientationDart =
    int Function(
      ffi.Pointer<ImageProcessorHandle>,
      double,
      ffi.Pointer<ffi.Double>,
    );

typedef _ProcessorLoadPhotoNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>, // inSourcePath
    );
typedef _ProcessorLoadPhotoDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _ProcessorLoadWarpedNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>, // inSourcePath
    );
typedef _ProcessorLoadWarpedDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _ProcessorLoadProNative =
    ffi.Int Function(
      ffi.Pointer<ImageProcessorHandle>,
      ffi.Pointer<ffi.Int8>, // inSourcePath
    );
typedef _ProcessorLoadProDart =
    int Function(ffi.Pointer<ImageProcessorHandle>, ffi.Pointer<ffi.Int8>);

typedef _WriteCompressedPngNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Int8>, // inSourcePath
      ffi.Pointer<ffi.Int8>, // inPngPath
    );
typedef _WriteCompressedPngDart =
    int Function(ffi.Pointer<ffi.Int8>, ffi.Pointer<ffi.Int8>);

// ----------------- Lookup functions -----------------

final _createProcessor = _nativeLib
    .lookup<ffi.NativeFunction<_CreateProcessorNative>>('createProcessor')
    .asFunction<_CreateProcessorDart>();

final _freeProcessor = _nativeLib
    .lookup<ffi.NativeFunction<_FreeProcessorNative>>('freeProcessor')
    .asFunction<_FreeProcessorDart>();

final _processorImportPhoto = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorImportPhotoNative>>(
      'processorImportPhoto',
    )
    .asFunction<_ProcessorImportPhotoDart>();

final _processorSetAvailableAspectRatios = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorSetAvailableAspectRatiosNative>>(
      'processorSetAvailableAspectRatios',
    )
    .asFunction<_ProcessorSetAvailableAspectRatiosDart>();

final _processorWarpImage = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorWarpImageNative>>('processorWarpImage')
    .asFunction<_ProcessorWarpImageDart>();

final _ProcessorContrastFilterDart _processorContrastFilter = _nativeLib
    .lookupFunction<
      _ProcessorContrastFilterNative,
      _ProcessorContrastFilterDart
    >('processorContrastFilter');

final _ProcessorDocumentFilterDart _processorDocumentFilter = _nativeLib
    .lookupFunction<
      _ProcessorDocumentFilterNative,
      _ProcessorDocumentFilterDart
    >('processorDocumentFilter');

final _ProcessorProFilterDart _processorProFilter = _nativeLib
    .lookupFunction<_ProcessorProFilterNative, _ProcessorProFilterDart>(
      'processorProFilter',
    );

final _ProcessorProColorFilterDart _processorProColorFilter = _nativeLib
    .lookupFunction<
      _ProcessorProColorFilterNative,
      _ProcessorProColorFilterDart
    >('processorProColorFilter');

final _rotateImage = _nativeLib
    .lookup<ffi.NativeFunction<_RotateImageNative>>('rotateImage')
    .asFunction<_RotateImageDart>();

final _scaleImageToWidth = _nativeLib
    .lookup<ffi.NativeFunction<_ScaleImageToWidthNative>>('scaleImageToWidth')
    .asFunction<_ScaleImageToWidthDart>();

final _scaleImageToMaxHeight = _nativeLib
    .lookup<ffi.NativeFunction<_ScaleImageToMaxSizeNative>>(
      'scaleImageToMaxSize',
    )
    .asFunction<_ScaleImageToMaxSizeDart>();

final _processorMatchAspectRatioAndOrientation = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorMatchAspectRatioAndOrientationNative>>(
      'processorMatchAspectRatioAndOrientation',
    )
    .asFunction<_ProcessorMatchAspectRatioAndOrientationDart>();

final _processorLoadPhoto = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorLoadPhotoNative>>('processorLoadPhoto')
    .asFunction<_ProcessorLoadPhotoDart>();

final _processorLoadWarped = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorLoadWarpedNative>>(
      'processorLoadWarped',
    )
    .asFunction<_ProcessorLoadWarpedDart>();

final _processorLoadPro = _nativeLib
    .lookup<ffi.NativeFunction<_ProcessorLoadProNative>>('processorLoadPro')
    .asFunction<_ProcessorLoadProDart>();

final _writeCompressedPng = _nativeLib
    .lookup<ffi.NativeFunction<_WriteCompressedPngNative>>('writeCompressedPng')
    .asFunction<_WriteCompressedPngDart>();

// ----------------- Public functions -----------------

final Finalizer<ffi.Pointer<ffi.Void>> _finalizer =
    Finalizer<ffi.Pointer<ffi.Void>>((ptr) {
      _freeProcessor(ptr.cast<ImageProcessorHandle>());
    });

class ImageProcessor {
  late final ffi.Pointer<ImageProcessorHandle> _handle;
  ImageProcessor() {
    _handle = _createProcessor();
    if (_handle.address == 0) {
      throw Exception('Native error: Failed to create ImageProcessor');
    }
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _freeProcessor(_handle);
  }

  void importPhoto(String sourcePath, String photoPath) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final photoPathPtr = photoPath.toNativeUtf8().cast<ffi.Int8>();
    final result = _processorImportPhoto(_handle, sourcePathPtr, photoPathPtr);
    malloc.free(sourcePathPtr);
    malloc.free(photoPathPtr);
    if (result == 0) {
      throw Exception('Native error, importPhoto from: $sourcePath');
    }
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

  void contrastFilter(String contrastPath) {
    final contrastPathPtr = contrastPath.toNativeUtf8().cast<ffi.Int8>();

    final result = _processorContrastFilter(_handle, contrastPathPtr);

    malloc.free(contrastPathPtr);

    if (result == 0) {
      throw Exception(
        'Native error, contrastFilter: Processing / Saving failed',
      );
    }
  }

  void documentFilter(String documentPath) {
    final documentPathPtr = documentPath.toNativeUtf8().cast<ffi.Int8>();

    final result = _processorDocumentFilter(_handle, documentPathPtr);

    malloc.free(documentPathPtr);

    if (result == 0) {
      throw Exception(
        'Native error, documentFilter: Processing / Saving failed',
      );
    }
  }

  void proFilter(String proPath) {
    final proPathPtr = proPath.toNativeUtf8().cast<ffi.Int8>();

    final result = _processorProFilter(_handle, proPathPtr);

    malloc.free(proPathPtr);

    if (result == 0) {
      throw Exception('Native error, proFilter: Processing / Saving failed');
    }
  }

  void proColorFilter(String proColorPath) {
    final proColorPathPtr = proColorPath.toNativeUtf8().cast<ffi.Int8>();

    final result = _processorProColorFilter(_handle, proColorPathPtr);

    malloc.free(proColorPathPtr);

    if (result == 0) {
      throw Exception('Native error, proFilter: Processing / Saving failed');
    }
  }

  // Other image processing:

  void rotateImage(String sourcePath, String rotatedPath, int angle) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final rotatedPathPtr = rotatedPath.toNativeUtf8().cast<ffi.Int8>();
    final result = _rotateImage(sourcePathPtr, rotatedPathPtr, angle);
    malloc.free(sourcePathPtr);
    malloc.free(rotatedPathPtr);
    if (result == 0) {
      throw Exception('Native error, rotateImage from: $sourcePath');
    }
  }

  int scaleImageToWidth(String sourcePath, String scaledPath, int width) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final scaledPathPtr = scaledPath.toNativeUtf8().cast<ffi.Int8>();
    final heightPth = malloc.allocate<ffi.Int>(1);

    final result = _scaleImageToWidth(
      sourcePathPtr,
      scaledPathPtr,
      width,
      heightPth,
    );
    int outHeight = heightPth.value;

    malloc.free(sourcePathPtr);
    malloc.free(scaledPathPtr);
    if (result == 0) {
      throw Exception('Native error, _scaleImageToWidth from: $sourcePath');
    }
    return outHeight;
  }

  /// - returns true if image was scaled and saved to scaledPath
  /// - will not scale if image is already smaller than maxSize in width and height
  bool scaleImageToMaxSize(
    String sourcePath,
    String scaledPath, {
    int maxSize = AppGlobals.maxPhotoSize,
  }) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final scaledPathPtr = scaledPath.toNativeUtf8().cast<ffi.Int8>();

    final scaledAndSaved = _scaleImageToMaxHeight(
      sourcePathPtr,
      scaledPathPtr,
      maxSize,
    );

    malloc.free(sourcePathPtr);
    malloc.free(scaledPathPtr);

    // true: image was scaled and saved to scaledPath
    // false: source was already small enough / error
    return scaledAndSaved == 1;
  }

  double matchAspectRatioAndOrientation(double calculatedAspectRatio) {
    final matchingAspectRatioPtr = malloc.allocate<ffi.Double>(1);
    int result = _processorMatchAspectRatioAndOrientation(
      _handle,
      calculatedAspectRatio,
      matchingAspectRatioPtr,
    );

    double mathcingAspectRatio = matchingAspectRatioPtr.value;
    malloc.free(matchingAspectRatioPtr);
    if (result == 0) {
      throw Exception(
        'Native error, matchAspectRatioAndOrientation from ratio: $calculatedAspectRatio',
      );
    }
    return mathcingAspectRatio;
  }

  void loadPhoto(String sourcePath) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final result = _processorLoadPhoto(_handle, sourcePathPtr);
    malloc.free(sourcePathPtr);
    if (result == 0) {
      throw Exception('Native error, loadPhoto from: $sourcePath');
    }
  }

  void loadWarped(String sourcePath) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final result = _processorLoadWarped(_handle, sourcePathPtr);
    malloc.free(sourcePathPtr);
    if (result == 0) {
      throw Exception('Native error, loadWarped from: $sourcePath');
    }
  }

  void loadPro(String sourcePath) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final result = _processorLoadPro(_handle, sourcePathPtr);
    malloc.free(sourcePathPtr);
    if (result == 0) {
      throw Exception('Native error, loadPro from: $sourcePath');
    }
  }

  void writeCompressedPng(String sourcePath, String destinationPath) {
    final sourcePathPtr = sourcePath.toNativeUtf8().cast<ffi.Int8>();
    final destinationPathPtr = destinationPath.toNativeUtf8().cast<ffi.Int8>();

    final result = _writeCompressedPng(sourcePathPtr, destinationPathPtr);

    malloc.free(sourcePathPtr);
    malloc.free(destinationPathPtr);

    if (result == 0) {
      throw Exception(
        'Native error, writeCompressedPng: from $sourcePath, to $destinationPath',
      );
    }
  }
}
