import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:docscanner/app_globals.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart'
    show CompressFormat, FlutterImageCompress;
import 'package:opencv_core/opencv.dart' as cv;
import 'dart:math' as math;

class ParamsWarpImage {
  String pathIn = "";
  String shape;
  double? ratioValueIn;
  List<List<int>>? cornerPoints;
  bool onlyCalculateBorder;

  ParamsWarpImage(
    this.pathIn,
    this.shape, {
    this.ratioValueIn,
    this.cornerPoints,
    this.onlyCalculateBorder = false,
  });
}

class ParamsProcessImage1 {
  String pathIn = "";

  ParamsProcessImage1(this.pathIn);
}

class ParamsProcessImage2 {
  String pathIn = "";
  List<int> borderCorrectionDepth = List<int>.generate(4, (_) => 0);

  ParamsProcessImage2(this.pathIn, this.borderCorrectionDepth);
}

class OpenCVHelper {
  int K = 0;
  int rows = 0;
  int cols = 0;
  int height = 0;
  int width = 0;
  List<int>? borderCutIn = List<int>.generate(8, (_) => 0);
  var borderCorrectionDepth = List<int>.generate(4, (_) => 0);

  AppGlobals g;
  OpenCVHelper(gIn) : g = gIn;

  Future<(Uint8List, Uint8List, List<int>, double, List<List<int>>)> warpImage(
    ParamsWarpImage params,
  ) async {
    cv.Mat imageMat = _loadImage(params.pathIn);
    cv.Mat? shape = (params.shape.isNotEmpty) ? _loadImage(params.shape) : null;

    final warpedRes = _warpImage(
      imageMat,
      shape,
      params.ratioValueIn,
      params.cornerPoints,
      params.onlyCalculateBorder,
    );
    cv.Mat? warped = warpedRes.$1;
    shape = warpedRes.$2;
    double ratioValue = warpedRes.$3;
    List<List<int>> cornerPoints = warpedRes.$4;
    return (
      await _returnImage(warped),
      await _returnImage(shape),
      borderCorrectionDepth,
      ratioValue,
      cornerPoints,
    );
  }

  Future<Uint8List> processImage1(ParamsProcessImage1 params) {
    cv.Mat? warped = _loadWarped(params.pathIn);

    cv.Mat? filtered1 = _filterImage1(warped);

    return _returnImage(filtered1);
  }

  Future<Uint8List> processImage2(ParamsProcessImage2 params) {
    borderCorrectionDepth = params.borderCorrectionDepth;

    cv.Mat? filtered1 = _loadWarped(params.pathIn);

    cv.Mat? filtered2 = _filterImage2(filtered1);

    return _returnImage(filtered2);
  }

  Future<Uint8List> rotateImage(String pathIn, int angle) {
    cv.Mat mat = _loadImage(pathIn);

    if (angle != 0) {
      mat = mat.rotate(
        angle == 90
            ? cv.ROTATE_90_CLOCKWISE
            : (angle == 270)
            ? cv.ROTATE_90_COUNTERCLOCKWISE
            : cv.ROTATE_180,
      );
    }

    return _returnImage(mat, uncompressed: true);
  }

  Future<Uint8List> scaleImageToWidth(String pathIn, int newWidth) {
    cv.Mat mat = _loadWarped(pathIn);

    int newHeight = (height * (newWidth / width)).toInt();
    //dev.log("$width x $height -> $newWidth x $newHeight");
    cv.Mat scaled;
    try {
      scaled = cv.resize(mat, (
        newWidth,
        newHeight,
      ), interpolation: cv.INTER_LINEAR);
    } catch (e) {
      scaled = cv.Mat.zeros(newHeight, newWidth, cv.MatType.CV_8UC3);
      dev.log("Exception: $e");
    }

    return _returnImage(scaled);
  }

  cv.Mat _loadImage(String imagePath) {
    // Load image
    cv.Mat imageMat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    if (imageMat.isEmpty) {
      throw StateError("Error: Failed to load photo.");
    }

    // Compute K based on image dimensions
    rows = imageMat.rows;
    cols = imageMat.cols;
    K = ((rows + cols) ~/ 100.0).clamp(3, -1 >>> 1);
    //dev.log("rows = $rows");
    //dev.log("cols = $cols");
    //dev.log("K = $K");

    return imageMat;
  }

  cv.Mat _loadWarped(String imagePath) {
    // Load image
    cv.Mat? imageMat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    if (imageMat.isEmpty) {
      throw StateError(
        "Error: Failed to load warped/processed1/processed2 image.",
      );
    }

    // Compute K based on image dimensions
    height = imageMat.rows;
    width = imageMat.cols;
    K = ((height + width) ~/ 50.0).clamp(3, -1 >>> 1);
    //dev.log("height = $height");
    //dev.log("width = $width");
    //dev.log("K = $K");

    return imageMat;
  }

  Future<Uint8List> _returnImage(
    cv.Mat? imageMat, {
    bool uncompressed = false,
  }) async {
    if (imageMat == null || imageMat.isEmpty) {
      dev.log("Error: Mat empty, can't convert to Image.");
      return Uint8List(0);
    }
    // Convert final Mat to Uint8List for Flutter
    var (resultSuccess, resultImageBytes) = cv.imencode(".png", imageMat);
    if (!resultSuccess) {
      dev.log("Error: Failed to encode image.");
    }

    if (uncompressed) {
      return resultImageBytes;
    } else {
      final imgInfo = AppGlobals.getPngInfo(resultImageBytes);
      final Uint8List pngBytes = await FlutterImageCompress.compressWithList(
        resultImageBytes,
        minWidth: imgInfo!.width,
        minHeight: imgInfo.height,
        format: CompressFormat.png,
        quality: 100,
      );
      return pngBytes;
    }
  }

  /// Warp Image: Edge detection, stretch to A4
  (cv.Mat?, cv.Mat, double, List<List<int>>) _warpImage(
    cv.Mat imageMat,
    cv.Mat? shape,
    final double? ratioValueIn,
    final List<List<int>>? cornerPointsIn,
    final bool onlyCalculateBorder,
  ) {
    List<List<int>> corners;
    double ratioValue;
    if (cornerPointsIn != null) borderCutIn = null;

    if (shape == null) {
      // 1. Isolate remove Text and Images to get Shape
      cv.Mat? bg = _removeTextAndImages(imageMat);

      // 2. create a binary image, white representing the shape of the document
      shape = _documentMask(bg);
      //return (shape, shape, 1.4, []);
      bg.dispose();
      bg = null;
    } else {
      if (shape.type != cv.MatType.CV_8UC1) {
        shape = cv.split(shape)[0]; //cv.cvtColor(shape, cv.COLOR_BGR2GRAY);
      }
    }
    if (cornerPointsIn == null) {
      // 3. Corner detection
      corners = _detectCorners(shape);
    } else {
      corners = cornerPointsIn;
    }
    if (ratioValueIn == null) {
      // 4. Perspective transformation
      ratioValue = _calculateTransformation(shape, corners);
    } else {
      ratioValue = ratioValueIn;
      _setHeightFromCorners(corners, ratioValue);
      //cv.Mat warpedShape = _transformImage(shape, corners);
      _calculateBorderSize(shape, corners);
    }

    cv.Mat? warped;
    if (!onlyCalculateBorder) {
      warped = _correctedTransformImage(imageMat, corners);
    }
    imageMat.dispose();

    return (warped, shape, ratioValue, corners);
  }

  /// Filter Image 1: subtract background quickly
  cv.Mat? _filterImage1(cv.Mat? imageMat) {
    if (imageMat == null) return null;

    // 5. Simple background subtraction
    imageMat = _isolateAndSubtractBGSimple(imageMat);

    return imageMat;
  }

  /// Filter Image 2: subtract background fully
  cv.Mat? _filterImage2(cv.Mat? imageMat) {
    if (imageMat == null) return null;

    // 5. Background subtraction
    imageMat = _isolateAndSubtractBG(imageMat);

    // 6. Border correction
    imageMat = _correctBorder(imageMat);
    if (imageMat == null) return null;

    // 7. Sharpen
    imageMat = _sharpenImage(imageMat, sharpeningStrength: 0.5);

    return imageMat;
  }

  /// Step 1: Isolate Form (Removes glow & dark structures)
  cv.Mat _removeTextAndImages(cv.Mat imageMat) {
    int k1 = (K ~/ 17).clamp(3, -1 >>> 1);
    cv.Mat kernelGlow = cv.getStructuringElement(cv.MORPH_RECT, (k1, k1));
    imageMat = cv.morphologyEx(
      imageMat,
      cv.MORPH_OPEN,
      kernelGlow,
      borderType: cv.BORDER_REPLICATE,
    );

    int k2 = (K * 2).clamp(3, -1 >>> 1);
    cv.Mat kernelDark = cv.getStructuringElement(cv.MORPH_RECT, (k2, k2));
    imageMat = cv.morphologyEx(
      imageMat,
      cv.MORPH_CLOSE,
      kernelDark,
      borderType: cv.BORDER_REPLICATE,
    );

    return imageMat;
  }

  bool _testNoSpillover(cv.Mat testShape) {
    if (testShape.at<int>(0, 0) == 0 &&
        testShape.at<int>(0, cols ~/ 2) == 0 &&
        testShape.at<int>(0, cols - 1) == 0 &&
        testShape.at<int>(rows - 1, 0) == 0 &&
        testShape.at<int>(rows - 1, cols ~/ 2) == 0 &&
        testShape.at<int>(rows - 1, cols - 1) == 0 &&
        testShape.at<int>(rows ~/ 2, 0) == 0 &&
        testShape.at<int>(rows ~/ 2, cols - 1) == 0) {
      return true;
    }
    return false;
  }

  /// Step 2: Edge Detection & Filling -> Shape of document
  cv.Mat _documentMask(cv.Mat imageMat) {
    if (imageMat.isEmpty) {
      throw StateError("Error, Edge Detection & Filling: split channels");
    }

    cv.Mat edges = _rgbEdges(imageMat);
    cv.Mat houghEdges1 = _houghEdges1(edges);
    cv.Mat houghEdges2 = _houghEdges2(edges);
    //return edges;

    bool hough1good = false;
    cv.Mat houghShape1 = _houghShape(houghEdges1);
    if (_testNoSpillover(houghShape1)) {
      borderCutIn = null;
      hough1good = true;
    }
    bool hough2good = false;
    cv.Mat houghShape2 = _houghShape(houghEdges2);
    if (_testNoSpillover(houghShape2)) {
      borderCutIn = null;
      hough2good = true;
    }
    if (hough1good && hough2good) {
      if (houghShape1.countNoneZero > houghShape2.countNoneZero) {
        return houghShape1;
      } else {
        return houghShape2;
      }
    } else if (hough1good) {
      return houghShape1;
    } else if (hough2good) {
      return houghShape2;
    }

    edges = edges.add(houghEdges2);
    //return edges;
    // 1. try just filling edges
    cv.Mat tightRiskyShape = _tightRiskyShape(edges);
    if (_testNoSpillover(tightRiskyShape)) {
      return tightRiskyShape;
    }

    cv.Mat mediumShape = _mediumShape(edges);
    if (_testNoSpillover(mediumShape)) {
      return mediumShape;
    }

    //cv.Mat looseSafeShape = _looseSafeShape(edges);
    //cv.Mat combinedShape = cv.multiply(tightRiskyShape, looseSafeShape);
    //
    //// edges without stuff around
    //edges = cv.multiply(edges, combinedShape);
    //
    //cv.Mat shape = _closeEdgesAndFill(edges);

    return cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);
  }

  cv.Mat _rgbEdges(cv.Mat mat) {
    // Initial guess for Canny thresholds
    double baseThreshold = 62.5;
    double highT = baseThreshold + K * 0.1;
    double lowT = 0.7 * highT;

    // Step 1: Run Canny with initial thresholds on all channels
    cv.VecMat channelsVec = cv.split(mat);
    cv.Mat edgesInitial = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC1);
    for (cv.Mat channel in channelsVec) {
      cv.Mat channelEdges = cv.canny(channel, lowT, highT);
      edgesInitial = cv.add(edgesInitial, channelEdges);
    }
    // Add saturation edges
    cv.VecMat hsv = cv.split(cv.cvtColor(mat, cv.COLOR_BGR2HSV));
    cv.Mat sEdges = cv.canny(hsv[1], lowT, highT);
    edgesInitial = cv.add(edgesInitial, sEdges);

    // Step 2: Calculate edge density
    int edgePixels = cv.countNonZero(edgesInitial);
    int totalPixels = mat.rows * mat.cols;
    double edgeDensity = edgePixels / totalPixels;

    // Step 3: Define target edge density and adjust thresholds
    double targetDensity = 0.00275;
    double scale = (edgeDensity / targetDensity).clamp(0.6, 1.9);

    highT = (highT * scale);
    lowT = 0.7 * highT;

    // Step 4: Run Canny again with adjusted thresholds
    cv.Mat finalEdges = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC1);
    for (cv.Mat channel in channelsVec) {
      cv.Mat channelEdges = cv.canny(channel, lowT, highT);
      finalEdges = cv.add(finalEdges, channelEdges);
    }
    // Add saturation edges
    hsv = cv.split(cv.cvtColor(mat, cv.COLOR_BGR2HSV));
    sEdges = cv.canny(hsv[1], lowT * 0.6, highT * 0.6);
    finalEdges = cv.add(finalEdges, sEdges);

    return finalEdges;
  }

  cv.Mat _houghEdges1(cv.Mat edges) {
    final double rhoRes = K * 0.15;
    final double thetaRes = (math.pi / 180);
    final int threshold = (K * 20).toInt();
    cv.Mat houghEdges = cv.Mat.zeros(
      edges.rows,
      edges.cols,
      cv.MatType.CV_8UC1,
    );

    cv.Mat allLines = cv.HoughLines(edges, rhoRes, thetaRes, threshold);

    int linesCount = math.min(10, allLines.rows);
    List<cv.Vec2f> lines = [];
    for (int i = 0; i < linesCount; i++) {
      final seg = allLines.at<cv.Vec2f>(i, 0);
      lines.add(seg);
    }

    for (var line in lines) {
      double rho = line.val1;
      double theta = line.val2;

      double a = math.cos(theta);
      double b = math.sin(theta);
      double x0 = a * rho;
      double y0 = b * rho;

      // Extend length
      int x1 = (x0 + K * 100 * (-b)).round();
      int y1 = (y0 + K * 100 * (a)).round();
      int x2 = (x0 - K * 100 * (-b)).round();
      int y2 = (y0 - K * 100 * (a)).round();

      // Draw line
      cv.line(
        houghEdges,
        cv.Point(x1, y1),
        cv.Point(x2, y2),
        cv.Scalar.all(255),
        thickness: 2,
      );
    }

    return houghEdges;
  }

  cv.Mat _houghEdges2(cv.Mat edges) {
    final double rhoRes = K * 0.15;
    final double thetaRes = (math.pi / 180);
    final int threshold = (K * 20).toInt();
    final double minLineLength = (K / 2).clamp(4.0, double.nan);
    final double maxLineGap = (K * 20).toDouble();
    cv.Mat houghEdges = cv.Mat.zeros(
      edges.rows,
      edges.cols,
      cv.MatType.CV_8UC1,
    );

    cv.Mat allSegments = cv.HoughLinesP(
      edges,
      rhoRes,
      thetaRes,
      threshold,
      minLineLength: minLineLength,
      maxLineGap: maxLineGap,
    );

    List<cv.Vec4i> segments = [];
    for (int i = 0; i < allSegments.rows; i++) {
      final seg = allSegments.at<cv.Vec4i>(i, 0);
      segments.add(seg);
    }

    for (var segment in segments) {
      int x1 = segment.val1;
      int y1 = segment.val2;
      int x2 = segment.val3;
      int y2 = segment.val4;

      // Extend the line by 25% on each end
      int dx = x2 - x1;
      int dy = y2 - y1;
      int ex1 = (x1 - dx * 0.0).round();
      int ey1 = (y1 - dy * 0.0).round();
      int ex2 = (x2 + dx * 0.0).round();
      int ey2 = (y2 + dy * 0.0).round();

      // Draw segments
      cv.line(
        houghEdges,
        cv.Point(ex1, ey1),
        cv.Point(ex2, ey2),
        cv.Scalar.all(255),
        thickness: 1,
      );
    }

    return houghEdges;
  }

  cv.Mat _houghShape(cv.Mat edges) {
    cv.Mat mask = cv.Mat.zeros(rows + 2, cols + 2, cv.MatType.CV_8UC1);
    cv.Mat shape1 = edges.clone();
    cv.floodFill(
      shape1, // input + output
      cv.Point(cols ~/ 2, rows ~/ 2),
      cv.Scalar.all(255),
      mask: mask, // useless
    );
    shape1 = cv.subtract(shape1, edges);
    cv.Mat kernel2 = cv.Mat.ones(5, 5, cv.MatType.CV_8UC1);
    shape1 = cv.dilate(shape1, kernel2, borderType: cv.BORDER_CONSTANT);
    return shape1;
  }

  cv.Mat _tightRiskyShape(cv.Mat edges) {
    cv.Mat kernel1 = cv.Mat.ones(3, 3, cv.MatType.CV_8UC1);
    cv.Mat mask = cv.Mat.zeros(rows + 2, cols + 2, cv.MatType.CV_8UC1);
    cv.Mat dilEdges = cv.dilate(edges, kernel1, borderType: cv.BORDER_CONSTANT);
    cv.Mat shape1 = dilEdges.clone();
    cv.floodFill(
      shape1, // input + output
      cv.Point(cols ~/ 2, rows ~/ 2),
      cv.Scalar.all(255),
      mask: mask, // useless
    );
    shape1 = cv.subtract(shape1, dilEdges);
    cv.Mat kernel2 = cv.Mat.ones(5, 5, cv.MatType.CV_8UC1);
    shape1 = cv.dilate(shape1, kernel2, borderType: cv.BORDER_CONSTANT);
    return shape1;
  }

  cv.Mat _mediumShape(cv.Mat edges) {
    int kSize = K ~/ 2 * 2 + 1;
    cv.Mat kernel1 = cv.Mat.ones(kSize, kSize, cv.MatType.CV_8UC1);
    cv.Mat mask = cv.Mat.zeros(rows + 2, cols + 2, cv.MatType.CV_8UC1);
    cv.Mat dilEdges = cv.dilate(edges, kernel1, borderType: cv.BORDER_CONSTANT);
    cv.Mat shape1 = dilEdges.clone();
    cv.floodFill(
      shape1, // input + output
      cv.Point(cols ~/ 2, rows ~/ 2),
      cv.Scalar.all(255),
      mask: mask, // useless
    );
    shape1 = cv.subtract(shape1, dilEdges);
    cv.Mat kernel2 = cv.Mat.ones(kSize + 2, kSize + 2, cv.MatType.CV_8UC1);
    shape1 = cv.dilate(shape1, kernel2, borderType: cv.BORDER_CONSTANT);
    return shape1;
  }

  //  cv.Mat _looseSafeShape(cv.Mat edges) {
  //    // padding
  //    int pad = K * 6;
  //    cv.Mat paddedEdges = cv.copyMakeBorder(
  //      edges,
  //      pad,
  //      pad,
  //      pad,
  //      pad, // Add padding on all sides
  //      cv.BORDER_CONSTANT,
  //      value: cv.Scalar.all(0), // Extend the background as black
  //    );
  //    // 1. close edges
  //    cv.Mat kernel = cv.getStructuringElement(cv.MORPH_RECT, (pad, pad));
  //    cv.Mat edgesClosed = cv.morphologyEx(
  //      paddedEdges,
  //      cv.MORPH_CLOSE,
  //      kernel,
  //      borderType: cv.BORDER_CONSTANT,
  //      iterations: 1,
  //    );
  //    // 2. black rectangle in the center
  //    int rectWidth = (paddedEdges.cols ~/ 5);
  //    int rectHeight = (paddedEdges.rows ~/ 5);
  //    cv.Rect rect = cv.Rect(
  //      (paddedEdges.cols - rectWidth) ~/ 2,
  //      (paddedEdges.rows - rectHeight) ~/ 2,
  //      rectWidth,
  //      rectHeight,
  //    );
  //    edgesClosed = cv.rectangle(
  //      edgesClosed,
  //      rect,
  //      cv.Scalar.all(0),
  //      thickness: cv.FILLED,
  //    );
  //    // 3. fill
  //    cv.Mat closedShape = edgesClosed.clone();
  //    cv.Mat mask = cv.Mat.zeros(
  //      paddedEdges.rows + 2,
  //      paddedEdges.cols + 2,
  //      cv.MatType.CV_8UC1,
  //    );
  //    cv.floodFill(
  //      closedShape,
  //      cv.Point(paddedEdges.cols ~/ 2, paddedEdges.rows ~/ 2),
  //      cv.Scalar.all(255),
  //      mask: mask,
  //    );
  //    // 4. only keep inside + dilate
  //    closedShape = cv.subtract(closedShape, edgesClosed);
  //    cv.Mat kernelLimit = cv.Mat.ones(
  //      (pad * 0.4).toInt(),
  //      (pad * 0.4).toInt(),
  //      cv.MatType.CV_8UC1,
  //    ); // 0.7 ~= 1/sqrt2 <- when closing with rect is diagonal, but 0,7 is too much if border is unclear
  //    closedShape = cv.dilate(
  //      closedShape,
  //      kernelLimit,
  //      borderType: cv.BORDER_CONSTANT,
  //    );
  //    // remove padding
  //    cv.Mat newShape = closedShape
  //        .rowRange(pad, pad + edges.rows)
  //        .colRange(pad, pad + edges.cols);
  //    return newShape;
  //  }
  //
  //  cv.Mat _closeEdgesAndFill(cv.Mat edges) {
  //    // padding, because morophological operations in openvc suck:
  //    int pad = K * 20;
  //    cv.Mat paddedEdges = cv.copyMakeBorder(
  //      edges,
  //      pad,
  //      pad,
  //      pad,
  //      pad, // Add padding on all sides
  //      cv.BORDER_CONSTANT,
  //      value: cv.Scalar.all(0), // Extend the background as black
  //    );
  //    // close inside
  //    cv.Mat kernelDilate = cv.getStructuringElement(cv.MORPH_RECT, (pad, pad));
  //    cv.Mat kernelErode = kernelDilate;
  //    //cv.Mat kernelErode1 = cv.Mat.ones(pad ~/ 2, pad ~/ 2, cv.MatType.CV_8UC1);
  //    cv.Mat paddedEdgesClosed = cv.dilate(
  //      paddedEdges,
  //      kernelDilate,
  //      borderType: cv.BORDER_CONSTANT,
  //      borderValue: cv.Scalar.all(0),
  //    );
  //
  //    // black rectangle in the center
  //    int rectWidth = (cols ~/ 4);
  //    int rectHeight = (rows ~/ 4);
  //    cv.Rect rect = cv.Rect(
  //      (paddedEdgesClosed.cols - rectWidth) ~/ 2,
  //      (paddedEdgesClosed.rows - rectHeight) ~/ 2,
  //      rectWidth,
  //      rectHeight,
  //    );
  //    paddedEdgesClosed = cv.rectangle(
  //      paddedEdgesClosed,
  //      rect,
  //      cv.Scalar.all(0),
  //      thickness: cv.FILLED,
  //    );
  //
  //    //return paddedEdgesClosed;
  //
  //    // fill
  //    cv.Mat mask = cv.Mat.zeros(
  //      paddedEdgesClosed.rows + 2,
  //      paddedEdgesClosed.cols + 2,
  //      cv.MatType.CV_8UC1,
  //    );
  //    cv.floodFill(
  //      paddedEdgesClosed,
  //      cv.Point(paddedEdgesClosed.cols ~/ 2, paddedEdgesClosed.rows ~/ 2),
  //      cv.Scalar.all(255),
  //      mask: mask,
  //    );
  //
  //    //return paddedEdgesClosed;
  //
  //    cv.Mat paddedShape = cv.erode(
  //      paddedEdgesClosed,
  //      kernelErode,
  //      borderType: cv.BORDER_CONSTANT,
  //      borderValue: cv.Scalar.all(0),
  //    );
  //    cv.Mat shape = paddedShape
  //        .rowRange(pad, pad + edges.rows)
  //        .colRange(pad, pad + edges.cols);
  //
  //    // remove small appendages
  //    int k1 = (K ~/ 16).clamp(3, -1 >>> 1);
  //    cv.Mat kernel2 = cv.Mat.ones(k1, k1, cv.MatType.CV_8UC1);
  //    shape = cv.erode(shape, kernel2, iterations: 3);
  //
  //    return shape;
  //  }

  /// Step 3: Corner Detection (Hit-or-Miss Transformation)
  List<List<int>> _detectCorners(cv.Mat shape) {
    int hitmissSize = (K * 1.5).round() * 2 + 1;
    //// padding
    //int pad = hitmissSize ~/ 2;
    //cv.Mat paddedShape = cv.copyMakeBorder(
    //  shape,
    //  pad,
    //  pad,
    //  pad,
    //  pad, // Add padding on all sides
    //  cv.BORDER_CONSTANT,
    //  value: cv.Scalar.all(0), // Extend the background as black
    //);
    //int rows = paddedShape.rows;
    //int cols = paddedShape.cols;

    // kernels to detect corners -> kernel1,2,3,4
    int hitmissTolerance = (K ~/ 10).clamp(1, -1 >>> 1);
    cv.Mat kernel1 = cv.Mat.zeros(hitmissSize, hitmissSize, cv.MatType.CV_8SC1);
    kernel1.set(hitmissSize ~/ 2, hitmissSize ~/ 2, 1);
    kernel1.set(hitmissSize ~/ 2 - 1, hitmissSize ~/ 2 - 1, -1);
    kernel1.set(hitmissSize - hitmissTolerance, 0, -1);
    kernel1.set(0, hitmissSize - hitmissTolerance, -1);
    cv.Mat kernel2 = kernel1.rotate(cv.ROTATE_90_COUNTERCLOCKWISE);
    cv.Mat kernel3 = kernel1.rotate(cv.ROTATE_90_CLOCKWISE);
    cv.Mat kernel4 = kernel1.rotate(cv.ROTATE_180);
    // shape.quadrants to detect corners -> detectedCorners
    cv.Mat detectedCorners1 = cv.morphologyEx(
      shape.rowRange(0, rows ~/ 2).colRange(0, cols ~/ 2),
      cv.MORPH_HITMISS,
      kernel1,
      borderType: cv.BORDER_REPLICATE,
    );
    cv.Mat detectedCorners2 = cv.morphologyEx(
      shape.rowRange(rows ~/ 2, rows).colRange(0, cols ~/ 2),
      cv.MORPH_HITMISS,
      kernel2,
      borderType: cv.BORDER_REPLICATE,
    );
    cv.Mat detectedCorners3 = cv.morphologyEx(
      shape.rowRange(0, rows ~/ 2).colRange(cols ~/ 2, cols),
      cv.MORPH_HITMISS,
      kernel3,
      borderType: cv.BORDER_REPLICATE,
    );
    cv.Mat detectedCorners4 = cv.morphologyEx(
      shape.rowRange(rows ~/ 2, rows).colRange(cols ~/ 2, cols),
      cv.MORPH_HITMISS,
      kernel4,
      borderType: cv.BORDER_REPLICATE,
    );

    //// quadrants
    //cv.Mat q1 = shape.rowRange(0, rows ~/ 2).colRange(0, cols ~/ 2);
    //cv.Mat q2 = shape.rowRange(rows ~/ 2, rows).colRange(0, cols ~/ 2);
    //cv.Mat q3 = shape.rowRange(0, rows ~/ 2).colRange(cols ~/ 2, cols);
    //cv.Mat q4 = shape.rowRange(rows ~/ 2, rows).colRange(cols ~/ 2, cols);

    // select outer points -> outerPoints (offset for quadrants)
    var outerPoints = List<cv.Point>.generate(4, (_) => cv.Point(0, 0));
    var xy1 = _toPoints(detectedCorners1, yOffset: 0, xOffset: 0);
    var xy2 = _toPoints(detectedCorners2, yOffset: rows ~/ 2, xOffset: 0);
    var xy3 = _toPoints(detectedCorners3, yOffset: 0, xOffset: cols ~/ 2);
    var xy4 = _toPoints(
      detectedCorners4,
      yOffset: rows ~/ 2,
      xOffset: cols ~/ 2,
    );
    List<int> fallbacks = [];
    try {
      outerPoints[0] = xy1.reduce((a, b) {
        int scoreA = -a.y - a.x;
        int scoreB = -b.y - b.x;
        return scoreA > scoreB ? a : b;
      });
    } catch (e) {
      // fallback in middle if quadrants are empty
      fallbacks.add(0);
      outerPoints[0] = cv.Point(cols ~/ 2 - 1, rows ~/ 2 - 1);
    }
    try {
      outerPoints[1] = xy2.reduce((a, b) {
        int scoreA = a.y - a.x;
        int scoreB = b.y - b.x;
        return scoreA > scoreB ? a : b;
      });
    } catch (e) {
      fallbacks.add(1);
      outerPoints[1] = cv.Point(cols ~/ 2 - 1, rows ~/ 2 + 1);
    }
    try {
      outerPoints[2] = xy3.reduce((a, b) {
        int scoreA = -a.y + a.x;
        int scoreB = -b.y + b.x;
        return scoreA > scoreB ? a : b;
      });
    } catch (e) {
      fallbacks.add(2);
      outerPoints[2] = cv.Point(cols ~/ 2 + 1, rows ~/ 2 - 1);
    }
    try {
      outerPoints[3] = xy4.reduce((a, b) {
        int scoreA = a.y + a.x;
        int scoreB = b.y + b.x;
        return scoreA > scoreB ? a : b;
      });
    } catch (e) {
      fallbacks.add(3);
      outerPoints[3] = cv.Point(cols ~/ 2 + 1, rows ~/ 2 + 1);
    }
    // if all failed -> to image corners
    if (fallbacks.length == 4) {
      outerPoints = [
        cv.Point(0, 0),
        cv.Point(0, rows - 1),
        cv.Point(cols - 1, 0),
        cv.Point(cols - 1, rows - 1),
      ];
    } else if (fallbacks.isNotEmpty) {
      for (var cornerIndex in fallbacks) {
        int? xRef;
        int? yRef;
        switch (cornerIndex) {
          case 0:
            xRef = 1;
            yRef = 2;
            break;
          case 1:
            xRef = 0;
            yRef = 3;
            break;
          case 2:
            xRef = 3;
            yRef = 0;
            break;
          case 3:
            xRef = 2;
            yRef = 1;
            break;
        }
        outerPoints[cornerIndex] = cv.Point(
          outerPoints[xRef!].x,
          outerPoints[yRef!].y,
        );
      }
    }

    // to List
    List<List<int>> outerPointsList = [];
    for (var point in outerPoints) {
      outerPointsList.add([point.y, point.x]);
    } // [point.y - pad, point.x - pad]
    //dev.log("outerPoints: $outerPoints");
    return outerPointsList;
  }

  List<cv.Point> _toPoints(
    cv.Mat detectedCorners, {
    int xOffset = 0,
    int yOffset = 0,
  }) {
    List<cv.Point> edgePoints = [];
    cv.Mat nonZero = cv.findNonZero(detectedCorners);

    // Convert to points
    for (int i = 0; i < nonZero.rows; i++) {
      edgePoints.add(
        cv.Point(
          nonZero.at<cv.Vec2i>(i, 0).val1 + xOffset,
          nonZero.at<cv.Vec2i>(i, 0).val2 + yOffset,
        ),
      );
    }

    return edgePoints;
  }

  /// Step 4: Perspective Transformation

  // Step 4.1: Calculate Border Corrections
  double _calculateTransformation(cv.Mat shape, List<List<int>> corners) {
    // Estimate aspect ratio
    double calculatedRatio = _calculateAspectRatio(corners);
    final matchedRatio = matchAspectRatioAndOrientation(calculatedRatio);
    calculatedRatio = matchedRatio;

    _setHeightFromCorners(corners, calculatedRatio);

    _calculateBorderSize(shape, corners);

    return calculatedRatio;
  }

  void _calculateBorderSize(cv.Mat shape, List<List<int>> corners) {
    cv.Mat warpedShape = _transformImage(shape, corners);

    final int maxBorderSize = (K ~/ 2).clamp(1, -1 >>> 1);
    // Top border
    var depths = List<int>.generate(width, (_) => 0);
    for (int j = 0; j < width; j++) {
      for (int i = 0; i < maxBorderSize; i++) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = i;
          depths[j] = val;
        } else {
          break;
        }
      }
    }
    _setTransformation(0, depths);

    // Bottom border
    depths = List<int>.generate(width, (_) => 0);
    for (int j = 0; j < width; j++) {
      for (int i = height - 1; i > height - maxBorderSize; i--) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = height - i;
          depths[j] = val;
        } else {
          break;
        }
      }
    }
    _setTransformation(1, depths);

    // Left border
    depths = List<int>.generate(height, (_) => 0);
    for (int i = 0; i < height; i++) {
      for (int j = 0; j < maxBorderSize; j++) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = j;
          depths[i] = val;
        } else {
          break;
        }
      }
    }
    _setTransformation(2, depths);

    // Right border
    depths = List<int>.generate(height, (_) => 0);
    for (int i = 0; i < height; i++) {
      for (int j = width - 1; j > width - maxBorderSize; j--) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = width - j;
          depths[i] = val;
        } else {
          break;
        }
      }
    }
    _setTransformation(3, depths);

    //dev.log("borderCutIn: $borderCutIn");
    //dev.log("borderCorrectionDepth: $borderCorrectionDepth");
  }

  void _setHeightFromCorners(List<List<int>> corners, double ratio) {
    // New pixel count without data loss
    height = math.max(
      (corners[1][0] - corners[0][0]).abs(),
      (corners[3][0] - corners[2][0]).abs(),
    );
    width = math.max(
      (corners[2][1] - corners[0][1]).abs(),
      (corners[3][1] - corners[1][1]).abs(),
    );
    if (width < (height / ratio).round()) {
      width = (height / ratio).round();
    } else {
      height = (width * ratio).round();
    }
    height = height.clamp(10, -1 >>> 1);
    width = width.clamp(10, -1 >>> 1);
  }

  double _calculateAspectRatio(List<List<int>> corners) {
    // Compute Euclidean distances
    double widthTop = math.sqrt(
      math.pow(corners[2][0] - corners[0][0], 2) +
          math.pow(corners[2][1] - corners[0][1], 2),
    );

    double widthBottom = math.sqrt(
      math.pow(corners[3][0] - corners[1][0], 2) +
          math.pow(corners[3][1] - corners[1][1], 2),
    );

    double heightLeft = math.sqrt(
      math.pow(corners[1][0] - corners[0][0], 2) +
          math.pow(corners[1][1] - corners[0][1], 2),
    );

    double heightRight = math.sqrt(
      math.pow(corners[3][0] - corners[2][0], 2) +
          math.pow(corners[3][1] - corners[2][1], 2),
    );

    // Compute averages
    double avgWidth = (widthTop + widthBottom) / 2;
    double avgHeight = (heightLeft + heightRight) / 2;

    // Calculate distortion factors
    double widthDistortion = widthTop / widthBottom;
    double heightDistortion = heightLeft / heightRight;
    widthDistortion = widthDistortion > 1
        ? widthDistortion
        : 1 / widthDistortion;
    heightDistortion = heightDistortion > 1
        ? heightDistortion
        : 1 / heightDistortion;

    // Correct for foreshortening
    double correctedHeight = avgHeight * math.sqrt(widthDistortion);
    double correctedWidth = avgWidth * math.sqrt(heightDistortion);

    // Return corrected aspect ratio
    // (assume portrait for now, fixed in _matchAspectRatio)
    double ratio = correctedHeight / correctedWidth;
    return ratio;
  }

  double matchAspectRatioAndOrientation(double calculatedRatioIn) {
    double matchingValue = math.sqrt2;
    bool portrait = true;
    // to portrait, for comparability
    double portraitValue = calculatedRatioIn;
    if (calculatedRatioIn < 1.0) {
      portraitValue = 1.0 / calculatedRatioIn;
      portrait = false;
    }
    // find closest match
    double smallestDifference = double.infinity;
    for (var availableRatio in g.availableAspectRatios) {
      double difference = (availableRatio.value - portraitValue).abs();
      if (difference < smallestDifference) {
        smallestDifference = difference;
        matchingValue = availableRatio.value;
      }
    }

    //dev.log(
    //  "Aspect Ratio: ${availableAspectRatios[matchIndex].name}: ${availableAspectRatios[matchIndex].value} (${ratioValueIn == null ? "calculated: $inputAspectRatio, " : ""}${portrait ? "portrait" : "horizontal"})",
    //);
    double matchingRatio = portrait ? matchingValue : 1.0 / matchingValue;
    return matchingRatio;
  }

  // Step 4.1.1: Set Border Corrections
  void _setTransformation(int borderIndex, List<int> depths) {
    final int borderTolerance = 6 + (K ~/ 9);
    if (borderCutIn != null) {
      borderCutIn![borderIndex * 2] = _percentileValueInt(
        depths.sublist(0, depths.length ~/ 2),
        0.67,
      );
      borderCutIn![borderIndex * 2 + 1] = _percentileValueInt(
        depths.sublist(depths.length ~/ 2),
        0.67,
      );
    }
    borderCorrectionDepth[borderIndex] =
        depths
            .sublist(depths.length ~/ 10, depths.length * 9 ~/ 10)
            .reduce(math.max) -
        (borderCutIn == null
            ? 0
            : (borderCutIn![borderIndex * 2] +
                      borderCutIn![borderIndex * 2 + 1]) ~/
                  2) +
        borderTolerance;
  }

  // Step 4.2: Apply Border Corrections and Transformation
  cv.Mat _correctedTransformImage(cv.Mat imageMat, List<List<int>> corners) {
    if (borderCutIn != null) {
      //top
      corners[0][0] += borderCutIn![0];
      corners[2][0] += borderCutIn![1];
      //bottom
      corners[1][0] -= borderCutIn![2];
      corners[3][0] -= borderCutIn![3];
      //left
      corners[0][1] += borderCutIn![4];
      corners[1][1] += borderCutIn![5];
      //right
      corners[2][1] -= borderCutIn![6];
      corners[3][1] -= borderCutIn![7];
    }

    //dev.log("correctedCorners = $corners");

    return _transformImage(imageMat, corners);
  }

  cv.Mat _transformImage(cv.Mat imageMat, List<List<int>> corners) {
    cv.VecPoint srcPoints = cv.VecPoint.fromList([
      cv.Point(corners[0][1], corners[0][0]),
      cv.Point(corners[1][1], corners[1][0]),
      cv.Point(corners[2][1], corners[2][0]),
      cv.Point(corners[3][1], corners[3][0]),
    ]);
    cv.VecPoint dstPoints = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(0, height),
      cv.Point(width, 0),
      cv.Point(width, height),
    ]);
    cv.Mat transformationMatrix = cv.getPerspectiveTransform(
      srcPoints,
      dstPoints,
    );

    cv.Mat? warped = cv.warpPerspective(imageMat, transformationMatrix, (
      width,
      height,
    ));

    return warped;
  }

  /// Step 5: Background Subtraction 1
  cv.Mat _isolateAndSubtractBGSimple(cv.Mat warped) {
    cv.Mat? bg = _warpedBgSimple(warped);
    //return bg;

    cv.Mat subtracted = cv.addWeighted(warped, 1, bg, -1, 255);
    //return subtracted;

    subtracted = _stretchMat(
      subtracted,
      lowPercentile: 0.005,
      highValue: 255,
      gamma: null,
    );
    return subtracted;
  }

  /// Step 7: Background Subtraction 2
  cv.Mat _isolateAndSubtractBG(cv.Mat warped) {
    cv.Mat bg = _warpedBg(warped);
    //return bg;

    cv.Mat subtracted = cv.addWeighted(warped, 1, bg, -1, 255);
    //return subtracted;

    subtracted = _stretchMat(
      subtracted,
      lowPercentile: 0.15,
      highValue: 230,
      gamma: 0.45,
    );

    // Median blur color
    try {
      int k1 = (K ~/ 70) * 2 + 3;
      cv.VecMat hsv = cv.split(cv.cvtColor(subtracted, cv.COLOR_BGR2HSV));
      //hsv[0] = cv.medianBlur(hsv[0], k1 * 2 + 1);
      hsv[1] = cv.min(cv.medianBlur(hsv[1], k1), hsv[1]);
      subtracted = cv.cvtColor(cv.merge(hsv), cv.COLOR_HSV2BGR);
    } catch (e) {
      dev.log("Warning, _warpedBg, medianBlur: $e");
    }

    return subtracted;
  }

  cv.Mat _warpedBg(cv.Mat warped) {
    // 1. Remove glow (Opening)
    int k1 = ((K ~/ 18) + 1).clamp(3, -1 >>> 1);
    cv.Mat kernel1 = cv.getStructuringElement(cv.MORPH_RECT, (k1, k1));
    cv.Mat bg = cv.morphologyEx(
      warped,
      cv.MORPH_OPEN,
      kernel1,
      borderType: cv.BORDER_REPLICATE,
    );
    // 2. Remove colorful blobs like markers (Median)
    try {
      bg = cv.medianBlur(bg, (K * 2) + 1);
    } catch (e) {
      dev.log("Warning, _warpedBg, medianBlur: $e");
    }
    // 3. Remove dark structures (Closing)
    int k2 = K;
    cv.Mat kernel2 = cv.getStructuringElement(cv.MORPH_CROSS, (k2, k2));
    bg = cv.morphologyEx(
      bg,
      cv.MORPH_CLOSE,
      kernel2,
      borderType: cv.BORDER_REPLICATE,
      iterations: 2,
    );
    // 4. set bg value to warped value, if brighter
    cv.VecMat bgHsvChannels = cv.split(cv.cvtColor(bg, cv.COLOR_BGR2HSV));
    cv.Mat wpV = cv.split(cv.cvtColor(warped, cv.COLOR_BGR2HSV))[2];

    int k3 = ((K ~/ 18) + 1).clamp(3, -1 >>> 1);
    cv.Mat kernel3 = cv.getStructuringElement(cv.MORPH_CROSS, (k3, k3));
    wpV = cv.morphologyEx(
      wpV,
      cv.MORPH_CLOSE,
      kernel3,
      borderType: cv.BORDER_REPLICATE,
      iterations: 2,
    );

    bgHsvChannels[2] = cv.max(bgHsvChannels[2], wpV);
    bg = cv.cvtColor(cv.merge(bgHsvChannels), cv.COLOR_HSV2BGR);

    return bg;
  }

  cv.Mat _warpedBgSimple(cv.Mat warped) {
    // 1. Remove Glow (Opening)
    int k1 = ((K ~/ 18) + 1).clamp(3, -1 >>> 1);
    cv.Mat kernel1 = cv.getStructuringElement(cv.MORPH_RECT, (k1, k1));
    cv.Mat bg = cv.morphologyEx(
      warped,
      cv.MORPH_OPEN,
      kernel1,
      borderType: cv.BORDER_REPLICATE,
    );
    // 2. blur
    bg = cv.blur(bg, ((K * 2) + 1, (K * 2) + 1));
    // 3. Remove dark structures (Closing)
    int k2 = K * 2;
    cv.Mat kernel2 = cv.getStructuringElement(cv.MORPH_RECT, (k2, k2));
    bg = cv.morphologyEx(
      bg,
      cv.MORPH_CLOSE,
      kernel2,
      borderType: cv.BORDER_REPLICATE,
      iterations: 1,
    );

    return bg;
  }

  /// Step 8: Border Correction
  cv.Mat? _correctBorder(cv.Mat warped) {
    final int whiteThreshold = 242;
    cv.Mat borderCorrect = warped.clone();
    warped = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
    bool wasWhite = false;

    // Top border
    for (int j = 0; j < width; j++) {
      wasWhite = false;
      for (int i = borderCorrectionDepth[0]; i >= 0; i--) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        }
        if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    // Bottom border
    for (int j = 0; j < width; j++) {
      wasWhite = false;
      for (int i = height - borderCorrectionDepth[1] - 1; i < height; i++) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        }
        if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    // Left border
    for (int i = 0; i < height; i++) {
      wasWhite = false;
      for (int j = borderCorrectionDepth[2]; j >= 0; j--) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        }
        if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    // Right border
    for (int i = 0; i < height; i++) {
      wasWhite = false;
      for (int j = width - borderCorrectionDepth[3] - 1; j < width; j++) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        }
        if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    return borderCorrect;
  }

  /// Step 9: Sharpen
  cv.Mat _sharpenImage(cv.Mat warped, {final double sharpeningStrength = 0.6}) {
    cv.Mat sharpenKernel = cv.Mat.fromList(5, 5, cv.MatType.CV_32FC1, [
      00.00,
      -0.05,
      -0.05,
      -0.05,
      00.00,
      -0.05,
      -0.20,
      -0.20,
      -0.20,
      -0.05,
      -0.05,
      -0.20,
      00.00,
      -0.20,
      -0.05,
      -0.05,
      -0.20,
      -0.20,
      -0.20,
      -0.05,
      00.00,
      -0.05,
      -0.05,
      -0.05,
      00.00,
    ]);

    sharpenKernel = sharpenKernel.multiply(sharpeningStrength);
    final double sharpenKernelCenter = -cv.sum(sharpenKernel).val1 + 1.0;
    sharpenKernel.set<double>(2, 2, sharpenKernelCenter);

    // Apply the filter with border replication
    cv.Mat sharpened = cv.filter2D(
      warped,
      -1, // Keep same depth
      sharpenKernel,
      borderType: cv.BORDER_REPLICATE,
    );

    // apply sharpening only to text / fine lines
    sharpened = _applyToText(warped, sharpened);

    //return mask.multiply(255);
    return sharpened;
  }

  cv.Mat _applyToText(
    cv.Mat base,
    cv.Mat special, {
    bool aroundText = true,
    bool applyToText = true,
    double thresh = 15.0,
    double textFineness = 22,
  }) {
    // find Text or fine lines
    int k = ((K ~/ textFineness) ~/ 2 * 2 + 1).clamp(3, -1 >>> 1);
    cv.Mat kernel1 = cv.getStructuringElement(cv.MORPH_RECT, (k, k));
    cv.Mat noText = cv.morphologyEx(
      base,
      cv.MORPH_CLOSE,
      kernel1,
      borderType: cv.BORDER_REPLICATE,
      iterations: 1,
    );
    cv.Mat diff = cv.absDiff(base, noText);
    if (aroundText) {
      cv.Mat kernel2 = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      diff = cv.morphologyEx(
        diff,
        cv.MORPH_DILATE,
        kernel2,
        borderType: cv.BORDER_REPLICATE,
        iterations: 1,
      );
    }
    cv.Mat mask = cv.threshold(diff, thresh, 1, cv.THRESH_BINARY).$2;
    cv.Mat maskInv = cv.threshold(diff, thresh, 1, cv.THRESH_BINARY_INV).$2;

    if (applyToText) {
      special = cv.add(cv.multiply(special, mask), cv.multiply(base, maskInv));
    } else {
      special = cv.add(cv.multiply(special, maskInv), cv.multiply(base, mask));
    }
    return special;
  }

  int _percentileValueInt(List<int> a, double percentile) {
    if (a.isEmpty) return 0;
    a.sort();
    int index = (a.length.toDouble() * percentile).toInt();
    return a[index];
  }

  cv.Mat _stretchMat(
    cv.Mat mat, {
    final double lowPercentile = 0.02,
    final double highValue = 230,
    final double? gamma,
  }) {
    cv.Mat ref;
    if (height > 1000 && width > 1000) {
      ref = cv.resize(mat, (height ~/ 4, width ~/ 4));
    } else {
      ref = mat;
    }
    ref = cv.cvtColor(ref, cv.COLOR_BGR2GRAY);
    List<int> a = ref.data.toList();
    a.removeWhere((value) => value == 255);
    if (a.isEmpty) return mat;
    a.sort();
    int lowIndex = (a.length.toDouble() * lowPercentile).toInt();
    double lowValue = a[lowIndex].toDouble();

    cv.normalize(
      mat,
      mat,
      normType: cv.NORM_MINMAX,
      alpha: -lowValue,
      beta: (255 - highValue) + 255,
    );

    if (gamma != null) mat = _applyGammaCorrection(mat, gamma);

    return mat;
  }

  cv.Mat _applyGammaCorrection(cv.Mat img, double gamma) {
    // Step 1: Create a lookup table (256 values)
    List<num> lookupTable = List.generate(256, (i) {
      double normalized = i / 255.0;
      double corrected = math.pow(normalized, gamma) * 255.0;
      return corrected.clamp(0, 255).toInt();
    });

    // Step 2: Convert lookup table to a cv.Mat (1 row, 256 columns)
    cv.Mat lut = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, lookupTable);

    // Step 3: Apply lookup table to the image
    cv.Mat result = cv.LUT(img, lut);

    return result;
  }
}
