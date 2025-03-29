import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:opencv_core/opencv.dart' as cv;
import 'dart:math' as math;

class AspectRatioInfo {
  final String name;
  final String description;
  final double value;

  AspectRatioInfo(this.name, this.description, this.value);
}

final List<AspectRatioInfo> commonAspectRatios = [
  //// International Standard (ISO 216 - A, B, C series)
  AspectRatioInfo("DIN A4", "DIN A/B/C (√2:1)", math.sqrt(2)), // ~1.414
  //// North American Paper Sizes (Letter, Legal, etc.)
  AspectRatioInfo("Letter", "Letter (8.5x11″, US)", 11 / 8.5), // ~1.294
  AspectRatioInfo("Legal", "Legal (8.5x14″, US)", 14 / 8.5), // ~1.647
  AspectRatioInfo(
    "Tabloid",
    "Tabloid / Ledger (11x17″, US)",
    17 / 11,
  ), // ~1.545
  //// Cards & Paper
  AspectRatioInfo("Business Card", "Business Card (3.5x2″)", 3.5 / 2), // 1.75
  AspectRatioInfo(
    "Credit Card",
    "Credit Card (ISO/ID-1, 85.6x53.98 mm)",
    85.6 / 53.98,
  ), // ~1.586
  AspectRatioInfo("Square", "1:1 Square (Notes, Covers)", 1.0), // 1.0
  //// Photo & Monitors
  AspectRatioInfo("5:4", "5:4 (Photo, Old Monitors)", 5 / 4), // 1.25
  AspectRatioInfo("4:3", "4:3 (Photo)", 4 / 3), // 1.333
  AspectRatioInfo("16:9", "16:9 (Video, Widescreen)", 16 / 9), // ~1.777
  AspectRatioInfo("16:10", "16:10 (Widescreen)", 16 / 10), // 1.6
  AspectRatioInfo("21:9", "21:9 (Ultrawide, Cinema)", 21 / 9), // ~2.333
];

class ParamsWarpImage {
  String pathIn = "";
  String pagePath = "";

  ParamsWarpImage(this.pathIn);
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
  var borderCutIn = List<int>.generate(4, (_) => 0);
  var borderCorrectionDepth = List<int>.generate(4, (_) => 0);

  (Uint8List, List<int>, int) warpImage(ParamsWarpImage params) {
    cv.Mat? imageMat = _loadImage(params.pathIn);

    final warpedRes = _warpImage(imageMat);
    cv.Mat? warped = warpedRes.$1;
    int ratioIndex = warpedRes.$2;
    return (_returnImage(warped), borderCorrectionDepth, ratioIndex);
  }

  Uint8List processImage1(ParamsProcessImage1 params) {
    cv.Mat? warped = _loadWarped(params.pathIn);

    cv.Mat? filtered1 = _filterImage1(warped);

    return _returnImage(filtered1);
  }

  Uint8List processImage2(ParamsProcessImage2 params) {
    borderCorrectionDepth = params.borderCorrectionDepth;

    cv.Mat? filtered1 = _loadWarped(params.pathIn);

    cv.Mat? filtered2 = _filterImage2(filtered1);

    return _returnImage(filtered2);
  }

  cv.Mat? _loadImage(String imagePath) {
    // Load image
    cv.Mat? imageMat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    if (imageMat.isEmpty) {
      dev.log("Error: Failed to load picture.");
      return null;
    }
    cv.normalize(
      imageMat,
      imageMat,
      normType: cv.NORM_MINMAX,
      alpha: 0,
      beta: 255,
    );

    // Compute K based on image dimensions
    rows = imageMat.rows;
    cols = imageMat.cols;
    K = ((rows + cols) ~/ 100.0);
    //dev.log("rows = $rows");
    //dev.log("cols = $cols");
    //dev.log("K = $K");

    return imageMat;
  }

  cv.Mat? _loadWarped(String imagePath) {
    // Load image
    cv.Mat? imageMat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    if (imageMat.isEmpty) {
      dev.log("Error: Failed to load warped/processed1/processed2 image.");
      return null;
    }
    cv.normalize(
      imageMat,
      imageMat,
      normType: cv.NORM_MINMAX,
      alpha: 0,
      beta: 255,
    );

    // Compute K based on image dimensions
    //rows = imageMat.rows;
    //cols = imageMat.cols;
    height = imageMat.rows;
    width = imageMat.cols;
    K = ((height + width) ~/ 50.0);
    //dev.log("height = $height");
    //dev.log("width = $width");
    //dev.log("K = $K");

    return imageMat;
  }

  Uint8List _returnImage(cv.Mat? imageMat) {
    if (imageMat == null || imageMat.isEmpty) {
      dev.log("Error: Mat empty, can't convert to Image.");
    }
    // Convert final Mat to Uint8List for Flutter
    var (resultSuccess, resultImage) = cv.imencode('.png', imageMat!);
    if (!resultSuccess) {
      dev.log("Error: Failed to encode image.");
    }

    return resultImage;
  }

  /// Warp Image: Edge detection, stretch to A4
  (cv.Mat?, int) _warpImage(cv.Mat? imageMat) {
    if (imageMat == null) return (null, 0);

    // scale down
    //if (cols > 1080) {
    //  rows = 1080 ~/ cols * rows;
    //  cols = 1080;
    //  imageMat = cv.resize(imageMat,(rows,cols));
    //}

    // 1. Isolate remove Text and Images to get Shape
    cv.Mat? bg = _removeTextAndImages(imageMat);

    // 2. create a binary image, white representing the shape of the document
    cv.Mat? shape = _documentMask(bg);
    bg.dispose();
    bg = null;
    //return shape;

    // 3. Corner detection
    List<List<int>> corners = _detectCorners(shape);

    // 4. Perspective transformation
    final ratioIndex = _calculateTransformation(shape, corners);
    shape.dispose();
    shape = null;

    cv.Mat? warped = _correctedTransformImage(imageMat, corners);
    if (warped == null) return (null, 0);
    imageMat.dispose();
    imageMat = null;

    return (warped, ratioIndex);
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
    imageMat = _sharpenImage(imageMat);

    return imageMat;
  }

  /// Step 1: Isolate Form (Removes glow & dark structures)
  cv.Mat _removeTextAndImages(cv.Mat imageMat) {
    cv.Mat kernelGlow = cv.getStructuringElement(cv.MORPH_RECT, (
      K ~/ 17,
      K ~/ 17,
    ));
    imageMat = cv.morphologyEx(
      imageMat,
      cv.MORPH_OPEN,
      kernelGlow,
      borderType: cv.BORDER_REPLICATE,
    );

    cv.Mat kernelDark = cv.getStructuringElement(cv.MORPH_RECT, (K * 2, K * 2));
    imageMat = cv.morphologyEx(
      imageMat,
      cv.MORPH_CLOSE,
      kernelDark,
      borderType: cv.BORDER_REPLICATE,
    );

    return imageMat;
  }

  /// Step 2: Edge Detection & Filling -> Shape of document
  cv.Mat _documentMask(cv.Mat imageMat) {
    if (imageMat.isEmpty) {
      dev.log("Error, Edge Detection & Filling: split channels");
    }

    cv.Mat edges = _rgbEdges(imageMat);

    // 1. try just filling edges
    cv.Mat tightRiskyShape = _tightRiskyShape(edges);
    if (tightRiskyShape.at<int>(0, 0) == 0 &&
        tightRiskyShape.at<int>(0, cols ~/ 2) == 0 &&
        tightRiskyShape.at<int>(0, cols - 1) == 0 &&
        tightRiskyShape.at<int>(rows - 1, 0) == 0 &&
        tightRiskyShape.at<int>(rows - 1, cols ~/ 2) == 0 &&
        tightRiskyShape.at<int>(rows - 1, cols - 1) == 0 &&
        tightRiskyShape.at<int>(rows ~/ 2, 0) == 0 &&
        tightRiskyShape.at<int>(rows ~/ 2, cols - 1) == 0) {
      dev.log("returning documentMask from simple edges");
      return tightRiskyShape;
    }

    cv.Mat looseSafeShape = _looseSafeShape(edges);
    cv.Mat combinedShape = cv.multiply(tightRiskyShape, looseSafeShape);

    // edges without stuff around
    edges = cv.multiply(edges, combinedShape);

    cv.Mat shape = _closeEdgesAndFill(edges);

    return shape;
  }

  cv.Mat _rgbEdges(cv.Mat mat) {
    cv.VecMat channels = cv.split(mat);
    cv.Mat edges = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC1);
    double highT = 60 + K * 0.1;
    double lowT = 0.7 * highT;
    //dev.log("canny thresholds: $lowT, $highT");
    // edges for all color channels:
    for (cv.Mat channel in channels) {
      cv.Mat channelEdges = cv.canny(channel, lowT, highT);
      edges = cv.add(edges, channelEdges);
    }
    return edges;
  }

  cv.Mat _tightRiskyShape(cv.Mat edges) {
    cv.Mat mask = cv.Mat.zeros(rows + 2, cols + 2, cv.MatType.CV_8UC1);
    cv.Mat shape1 = edges.clone();
    cv.floodFill(
      shape1, // input + output
      cv.Point(cols ~/ 2, rows ~/ 2),
      cv.Scalar.all(255),
      mask: mask, // useless
    );
    shape1 = cv.subtract(shape1, edges);
    cv.Mat kernel = cv.Mat.ones(5, 5, cv.MatType.CV_8UC1);
    shape1 = cv.dilate(shape1, kernel, borderType: cv.BORDER_CONSTANT);
    return shape1;
  }

  cv.Mat _looseSafeShape(cv.Mat edges) {
    // 1. close edges
    cv.Mat kernelDilate = cv.Mat.ones(K * 6, K * 6, cv.MatType.CV_8UC1);
    cv.Mat edgesClosed = cv.dilate(
      edges,
      kernelDilate,
      borderType: cv.BORDER_CONSTANT,
    );
    cv.Mat kernelErode = cv.Mat.ones(K * 5, K * 5, cv.MatType.CV_8UC1);
    edgesClosed = cv.erode(
      edgesClosed,
      kernelErode,
      borderType: cv.BORDER_CONSTANT,
    );
    // 2. black rectangle in the center
    int rectWidth = (cols ~/ 4);
    int rectHeight = (rows ~/ 4);
    cv.Rect rect = cv.Rect(
      (cols - rectWidth) ~/ 2,
      (rows - rectHeight) ~/ 2,
      rectWidth,
      rectHeight,
    );
    edgesClosed = cv.rectangle(
      edgesClosed,
      rect,
      cv.Scalar.all(0),
      thickness: cv.FILLED,
    );
    // 3. fill
    cv.Mat closedShape = edgesClosed.clone();
    cv.Mat mask = cv.Mat.zeros(
      edges.rows + 2,
      edges.cols + 2,
      cv.MatType.CV_8UC1,
    );
    cv.floodFill(
      closedShape,
      cv.Point(cols ~/ 2, rows ~/ 2),
      cv.Scalar.all(255),
      mask: mask,
    );
    // 4. only keep inside + dilate
    closedShape = cv.subtract(closedShape, edgesClosed);
    cv.Mat kernelLimit = cv.Mat.ones((K * 2), (K * 2), cv.MatType.CV_8UC1);
    closedShape = cv.dilate(
      closedShape,
      kernelLimit,
      borderType: cv.BORDER_CONSTANT,
    );
    return closedShape;
  }

  cv.Mat _closeEdgesAndFill(cv.Mat edges) {
    // padding, because morophological operations in openvc suck:
    int pad = K * 20;
    cv.Mat paddedEdges = cv.copyMakeBorder(
      edges,
      pad,
      pad,
      pad,
      pad, // Add padding on all sides
      cv.BORDER_CONSTANT,
      value: cv.Scalar.all(0), // Extend the background as black
    );
    // close inside
    cv.Mat kernelDilate = cv.Mat.ones(pad, pad, cv.MatType.CV_8UC1);
    cv.Mat kernelErode = kernelDilate;
    //cv.Mat kernelErode1 = cv.Mat.ones(pad ~/ 2, pad ~/ 2, cv.MatType.CV_8UC1);
    cv.Mat paddedEdgesClosed = cv.dilate(
      paddedEdges,
      kernelDilate,
      borderType: cv.BORDER_CONSTANT,
      borderValue: cv.Scalar.all(0),
    );

    // black rectangle in the center
    int rectWidth = (cols ~/ 4);
    int rectHeight = (rows ~/ 4);
    cv.Rect rect = cv.Rect(
      (paddedEdgesClosed.cols - rectWidth) ~/ 2,
      (paddedEdgesClosed.rows - rectHeight) ~/ 2,
      rectWidth,
      rectHeight,
    );
    paddedEdgesClosed = cv.rectangle(
      paddedEdgesClosed,
      rect,
      cv.Scalar.all(0),
      thickness: cv.FILLED,
    );

    //return paddedEdgesClosed;

    // fill
    cv.Mat mask = cv.Mat.zeros(
      paddedEdgesClosed.rows + 2,
      paddedEdgesClosed.cols + 2,
      cv.MatType.CV_8UC1,
    );
    cv.floodFill(
      paddedEdgesClosed,
      cv.Point(paddedEdgesClosed.cols ~/ 2, paddedEdgesClosed.rows ~/ 2),
      cv.Scalar.all(255),
      mask: mask,
    );

    //return paddedEdgesClosed;

    cv.Mat paddedShape = cv.erode(
      paddedEdgesClosed,
      kernelErode,
      borderType: cv.BORDER_CONSTANT,
      borderValue: cv.Scalar.all(0),
    );
    cv.Mat shape = paddedShape
        .rowRange(pad, pad + edges.rows)
        .colRange(pad, pad + edges.cols);

    // remove small appendages
    cv.Mat kernel2 = cv.Mat.ones(K ~/ 16, K ~/ 16, cv.MatType.CV_8UC1);
    shape = cv.erode(shape, kernel2, iterations: 3);

    return shape;
  }

  /// Step 3: Corner Detection (Hit-or-Miss Transformation)
  List<List<int>> _detectCorners(cv.Mat shape) {
    // kernels to detect corners -> kernel1, -2, -3, -4
    int hitmissSize = (K * 1.5).round() * 2 + 1;
    int hitmissTolerance = K ~/ 10;
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
    );
    cv.Mat detectedCorners2 = cv.morphologyEx(
      shape.rowRange(rows ~/ 2, rows).colRange(0, cols ~/ 2),
      cv.MORPH_HITMISS,
      kernel2,
    );
    cv.Mat detectedCorners3 = cv.morphologyEx(
      shape.rowRange(0, rows ~/ 2).colRange(cols ~/ 2, cols),
      cv.MORPH_HITMISS,
      kernel3,
    );
    cv.Mat detectedCorners4 = cv.morphologyEx(
      shape.rowRange(rows ~/ 2, rows).colRange(cols ~/ 2, cols),
      cv.MORPH_HITMISS,
      kernel4,
    );
    // select outer points -> outerPoints (offset for quadrants)
    var outerPoints = List<List<int>>.generate(4, (_) => []);
    var xy1 = _toXYLists(detectedCorners1, yOffset: 0, xOffset: 0);
    var xy2 = _toXYLists(detectedCorners2, yOffset: rows ~/ 2, xOffset: 0);
    var xy3 = _toXYLists(detectedCorners3, yOffset: 0, xOffset: cols ~/ 2);
    var xy4 = _toXYLists(
      detectedCorners4,
      yOffset: rows ~/ 2,
      xOffset: cols ~/ 2,
    );
    outerPoints[0] = [xy1.$2.reduce(math.min), xy1.$1.reduce(math.min)];
    outerPoints[1] = [xy2.$2.reduce(math.max), xy2.$1.reduce(math.min)];
    outerPoints[2] = [xy3.$2.reduce(math.min), xy3.$1.reduce(math.max)];
    outerPoints[3] = [xy4.$2.reduce(math.max), xy4.$1.reduce(math.max)];
    //dev.log("outerPoints: $outerPoints");
    return outerPoints;
    // remove detectedCorners distant from outerPoints -> reducedCorners
    //final kernelSize = K * 12;
    //cv.Mat kernelReduce = cv.Mat.ones(
    //  kernelSize,
    //  kernelSize,
    //  cv.MatType.CV_8SC1,
    //);
    //cv.Mat matReduce = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);
    //matReduce.set(outerPoints[0][0], outerPoints[0][1], 255);
    //matReduce = cv.dilate(matReduce, kernelReduce);
    //cv.Mat reducedCorners1 = cv.multiply(detectedCorners1, matReduce);
    //return reducedCorners1;
    //
    //matReduce = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);
    //matReduce.set(outerPoints[1][0], outerPoints[1][1], 1);
    //matReduce = cv.dilate(matReduce, kernelReduce);
    //cv.Mat reducedCorners2 = cv.multiply(detectedCorners2, matReduce);
    //
    //matReduce = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);
    //matReduce.set(outerPoints[2][0], outerPoints[2][1], 1);
    //matReduce = cv.dilate(matReduce, kernelReduce);
    //cv.Mat reducedCorners3 = cv.multiply(detectedCorners3, matReduce);
    //
    //matReduce = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);
    //matReduce.set(outerPoints[3][0], outerPoints[3][1], 1);
    //matReduce = cv.dilate(matReduce, kernelReduce);
    //cv.Mat reducedCorners4 = cv.multiply(detectedCorners4, matReduce);
    //
    // select outer points from reducedCorners -> finalCorners
    //var finalCorners = List<List<int>>.generate(4, (_) => []);
    //xy1 = _toXYLists(reducedCorners1);
    //xy2 = _toXYLists(reducedCorners2);
    //xy3 = _toXYLists(reducedCorners3);
    //xy4 = _toXYLists(reducedCorners4);
    //finalCorners[0] = [xy1.$2.reduce(math.min), xy1.$1.reduce(math.min)];
    //finalCorners[1] = [xy2.$2.reduce(math.max), xy2.$1.reduce(math.min)];
    //finalCorners[2] = [xy3.$2.reduce(math.min), xy3.$1.reduce(math.max)];
    //finalCorners[3] = [xy4.$2.reduce(math.max), xy4.$1.reduce(math.max)];
    //dev.log("finalCorners: $finalCorners");
    //
    //return finalCorners;
  }

  (List<int>, List<int>) _toXYLists(
    cv.Mat detectedCorners, {
    int xOffset = 0,
    int yOffset = 0,
  }) {
    cv.Mat nonZero = cv.findNonZero(detectedCorners);

    // Convert to Y, X lists
    List<int> xList = [];
    List<int> yList = [];
    for (int i = 0; i < nonZero.rows; i++) {
      xList.add(nonZero.at<cv.Vec2i>(i, 0).val1 + xOffset);
      yList.add(nonZero.at<cv.Vec2i>(i, 0).val2 + yOffset);
    }

    return (xList, yList);
  }

  /// Step 4: Perspective Transformation

  // Step 4.1: Calculate Border Corrections
  int _calculateTransformation(cv.Mat shape, List<List<int>> corners) {
    // New pixel count without data loss
    height = math.max(
      (corners[1][0] - corners[0][0]).abs(),
      (corners[3][0] - corners[2][0]).abs(),
    );
    width = math.max(
      (corners[2][1] - corners[0][1]).abs(),
      (corners[3][1] - corners[1][1]).abs(),
    );
    // Estimate aspect ratio
    double ratio = _calculateAspectRatio(corners); //math.sqrt(2)
    final matchedRatio = _matchAspectRatio(ratio);
    ratio = matchedRatio.$1;
    final ratioIndex = matchedRatio.$2;
    if (width < (height / ratio).round()) {
      width = (height / ratio).round();
    } else {
      height = (width * ratio).round();
    }

    cv.Mat warpedShape = _transformImage(shape, corners);

    final int maxBorderSize = (K ~/ 2);

    // Top border
    int calculatedBoderSize = 0;
    var depths = List<int>.generate(width, (_) => 0);
    for (int j = 0; j < width; j++) {
      for (int i = 1; i < maxBorderSize; i++) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = i;
          depths[j] = val;
          if (calculatedBoderSize < val) {
            calculatedBoderSize = val;
          }
        } else {
          break;
        }
      }
    }
    _setTransformation(0, calculatedBoderSize, depths);

    // Bottom border
    calculatedBoderSize = 0;
    depths = List<int>.generate(width, (_) => 0);
    for (int j = 0; j < width; j++) {
      for (int i = height - 1; i > height - maxBorderSize; i--) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = height - i;
          depths[j] = val;
          if (calculatedBoderSize < val) {
            calculatedBoderSize = val;
          }
        } else {
          break;
        }
      }
    }
    _setTransformation(1, calculatedBoderSize, depths);

    // Left border
    calculatedBoderSize = 0;
    depths = List<int>.generate(height, (_) => 0);
    for (int i = 0; i < height; i++) {
      for (int j = 1; j < maxBorderSize; j++) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = j;
          depths[i] = val;
          if (calculatedBoderSize < val) {
            calculatedBoderSize = val;
          }
        } else {
          break;
        }
      }
    }
    _setTransformation(2, calculatedBoderSize, depths);

    // Right border
    calculatedBoderSize = 0;
    depths = List<int>.generate(height, (_) => 0);
    for (int i = 0; i < height; i++) {
      for (int j = width - 1; j > width - maxBorderSize; j--) {
        if (warpedShape.at<int>(i, j) == 0) {
          int val = width - j;
          depths[i] = val;
          if (calculatedBoderSize < val) {
            calculatedBoderSize = val;
          }
        } else {
          break;
        }
      }
    }
    _setTransformation(3, calculatedBoderSize, depths);

    //dev.log("borderCutIn: $borderCutIn");
    //dev.log("borderCorrectionDepth: $borderCorrectionDepth");
    return ratioIndex;
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
    widthDistortion =
        widthDistortion > 1 ? widthDistortion : 1 / widthDistortion;
    heightDistortion =
        heightDistortion > 1 ? heightDistortion : 1 / heightDistortion;

    // Correct for foreshortening
    double correctedHeight = avgHeight * math.sqrt(widthDistortion);
    double correctedWidth = avgWidth * math.sqrt(heightDistortion);

    // Return corrected aspect ratio
    // (assume portrait for now, fixed in _matchAspectRatio)
    double ratio = correctedHeight / correctedWidth;
    return ratio;
  }

  (double, int) _matchAspectRatio(double inputAspectRatio) {
    bool portrait = true;
    if (inputAspectRatio < 1.0) {
      portrait = false;
      inputAspectRatio = 1.0 / inputAspectRatio;
    }
    // find closest match
    int matchIndex = 0;
    double smallestDifference = double.infinity;
    for (var (index, ratioInfo) in commonAspectRatios.indexed) {
      double difference = (ratioInfo.value - inputAspectRatio).abs();
      if (difference < smallestDifference) {
        smallestDifference = difference;
        matchIndex = index;
      }
    }
    dev.log(
      "Aspect Ratio: ${commonAspectRatios[matchIndex].name} ${commonAspectRatios[matchIndex].value} (calculated: $inputAspectRatio, ${portrait ? "portrait" : "horizontal"})",
    );
    double matchingRatio =
        portrait
            ? commonAspectRatios[matchIndex].value
            : 1.0 / commonAspectRatios[matchIndex].value;
    return (matchingRatio, matchIndex);
  }

  // Step 4.1.1: Set Border Corrections
  void _setTransformation(
    int borderIndex,
    int calculatedBoderSize,
    List<int> depths,
  ) {
    final int borderTolerance = 5 + (K ~/ 9);
    borderCutIn[borderIndex] = _percentileValueInt(depths, 0.67);
    borderCorrectionDepth[borderIndex] =
        calculatedBoderSize - borderCutIn[borderIndex] + borderTolerance;
  }

  // Step 4.2: Apply Border Corrections and Transformation
  cv.Mat? _correctedTransformImage(cv.Mat imageMat, List<List<int>> corners) {
    //top
    corners[0][0] += borderCutIn[0];
    corners[2][0] += borderCutIn[0];
    //bottom
    corners[1][0] -= borderCutIn[1];
    corners[3][0] -= borderCutIn[1];
    //left
    corners[0][1] += borderCutIn[2];
    corners[1][1] += borderCutIn[2];
    //right
    corners[2][1] -= borderCutIn[3];
    corners[3][1] -= borderCutIn[3];

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

    //// visualize corners
    //cv.Mat? cornersImage = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC3);
    //for (var corner in corners) {
    //  cornersImage.set(corner[0], corner[1], cv.Vec3b(255, 255, 255));
    //}
    //
    //cv.Mat? possibleCornersImage = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC3);
    //for (var (cornerIndex, corner) in possibleCorners.indexed) {
    //  for (var point in corner) {
    //    cv.Vec3b color = cv.Vec3b(255, 255, 255);
    //    switch (cornerIndex) {
    //      case 0:
    //        color = cv.Vec3b(255, 0, 0);
    //        break;
    //      case 1:
    //        color = cv.Vec3b(0, 255, 0);
    //        break;
    //      case 2:
    //        color = cv.Vec3b(0, 0, 255);
    //        break;
    //      case 3:
    //        color = cv.Vec3b(255, 0, 255);
    //        break;
    //    }
    //    possibleCornersImage.set(point[0], point[1], color);
    //  }
    //}
    //
    //shape = cv.subtract(
    //  imageMat,
    //  cv.cvtColor(shape.divide(2), cv.COLOR_GRAY2BGR),
    //);
    //cv.Mat kernelp = cv.getStructuringElement(cv.MORPH_RECT, (K, K));
    //shape = cv.subtract(shape, cv.dilate(possibleCornersImage, kernelp));
    //cv.Mat kernelc = cv.getStructuringElement(cv.MORPH_RECT, (
    //  K ~/ 2,
    //  K ~/ 2,
    //));
    //cornersImage = cv.add(shape, cv.dilate(cornersImage, kernelc));
    //
    //return cornersImage;

    return warped;
  }

  /// Step 5: Background Subtraction 1
  cv.Mat _isolateAndSubtractBGSimple(cv.Mat warped) {
    cv.Mat? bg = _warpedBgSimple(warped);
    //return bg;

    cv.Mat subtracted = cv.addWeighted(warped, 1, bg, -1, 255);
    //return subtracted;

    subtracted = _stretchMat(subtracted, highValue: 255, lowPercentile: 0.005);
    return subtracted;
  }

  ///// Step 6: BW Correction
  //cv.Mat _bwCorrection(cv.Mat mat, cv.Mat bg) {
  //  //cv.Mat ref = cv.resize(mat, (height ~/ 4, width ~/ 4));
  //
  // Extract saturation channel
  //cv.Mat refHSV = cv.cvtColor(ref, cv.COLOR_BGR2HSV);
  //cv.VecMat hsvChannels = cv.split(refHSV);
  //cv.Mat saturation = hsvChannels[1]; // S channel (Hue, Saturation, Value)
  //
  // Mask for low-saturation pixels
  //cv.Mat lowSatMask =
  //    cv
  //        .threshold(
  //          saturation,
  //          saturation.mean().val1,
  //          1,
  //          cv.THRESH_BINARY_INV,
  //        )
  //        .$2;
  // Average low-saturation pixels
  //cv.Scalar meanGrayColor = cv.mean(mat /*, mask: lowSatMask*/);
  //
  // divide by meanGrayColor
  //cv.Mat meanMat = cv.Mat.create(
  //  rows: mat.rows,
  //  cols: mat.cols,
  //  type: cv.MatType.CV_8UC3,
  //  r: meanGrayColor.val1.toInt(),
  //  g: meanGrayColor.val2.toInt(),
  //  b: meanGrayColor.val3.toInt(),
  //);
  //double averageGrayBrightness =
  //    (meanGrayColor.val1.toInt() +
  //            meanGrayColor.val2.toInt() +
  //            meanGrayColor.val3.toInt())
  //        .toDouble() /
  //    3;
  //meanMat = meanMat.convertTo(
  //  cv.MatType.CV_32FC3,
  //  alpha: 1.0 / averageGrayBrightness,
  //);
  //
  //  //cv.Mat bgHSV = cv.cvtColor(bg, cv.COLOR_BGR2HSV);
  //cv.VecMat hsvChannels = cv.split(bgHSV);
  //cv.Mat value1C = hsvChannels[2]; // V channel
  //  bg = bg.convertTo(cv.MatType.CV_32FC3);
  //  cv.Mat value1C = cv.cvtColor(bg, cv.COLOR_BGR2GRAY);
  //  cv.Mat value3C = cv.merge([value1C, value1C, value1C].asVec());
  //  cv.Mat normBg = bg.divideMat(value3C);
  //
  //  mat = mat.convertTo(cv.MatType.CV_32FC3, alpha: 1.0 / 255.0);
  //  cv.Mat correctedMat = mat.divideMat(normBg);
  //  correctedMat = correctedMat.convertTo(cv.MatType.CV_8UC3, alpha: 255.0);
  //
  //  return correctedMat;
  //}

  /// Step 7: Background Subtraction 2
  cv.Mat _isolateAndSubtractBG(cv.Mat warped) {
    cv.Mat? bg = _warpedBg(warped);
    //return bg;

    cv.Mat subtracted = cv.addWeighted(warped, 1, bg, -1, 255);
    //return subtracted;

    subtracted = _stretchMat(subtracted, gamma: 0.8);
    return subtracted;
  }

  cv.Mat _warpedBg(cv.Mat warped) {
    // 1. Remove Glow (Opening)
    int k1 = (K ~/ 18) + 1;
    cv.Mat kernel1 = cv.getStructuringElement(cv.MORPH_RECT, (k1, k1));
    cv.Mat bg = cv.morphologyEx(
      warped,
      cv.MORPH_OPEN,
      kernel1,
      borderType: cv.BORDER_REPLICATE,
    );
    // 2. Median filter hue + saturation
    bg = cv.medianBlur(bg, (K * 2) + 1);
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
    cv.VecMat wpHsvChannels = cv.split(cv.cvtColor(warped, cv.COLOR_BGR2HSV));
    bgHsvChannels[2] = cv.max(bgHsvChannels[2], wpHsvChannels[2]);
    bg = cv.cvtColor(cv.merge(bgHsvChannels), cv.COLOR_HSV2BGR);

    return bg;
  }

  cv.Mat _warpedBgSimple(cv.Mat warped) {
    // 1. Remove Glow (Opening)
    int k1 = (K ~/ 18) + 1;
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
      for (int i = borderCorrectionDepth[0]; i > 0; i--) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        } else if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    // Bottom border
    for (int j = 0; j < width; j++) {
      wasWhite = false;
      for (int i = height - borderCorrectionDepth[1]; i < height; i++) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        } else if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    // Left border
    for (int i = 0; i < height; i++) {
      wasWhite = false;
      for (int j = borderCorrectionDepth[2]; j > 0; j--) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        } else if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    // Right border
    for (int i = 0; i < height; i++) {
      wasWhite = false;
      for (int j = width - borderCorrectionDepth[3]; j < width; j++) {
        if (warped.at<int>(i, j) >= whiteThreshold) {
          wasWhite = true;
        } else if (wasWhite) {
          borderCorrect.set<cv.Vec3b>(i, j, cv.Vec3b(255, 255, 255));
        }
      }
    }

    return borderCorrect;
  }

  /// Step 9: Sharpen
  cv.Mat _sharpenImage(cv.Mat warped, {final double sharpeningStrength = 0.8}) {
    // Define the sharpening kernel
    //[
    //  -0.155,
    //  -0.346,
    //  -0.155,
    //  -0.346,
    //  0.0,
    //  -0.346,
    //  -0.155,
    //  -0.346,
    //  -0.155,
    //]
    cv.Mat sharpenKernel = cv.Mat.fromList(5, 5, cv.MatType.CV_32FC1, [
      0.0,
      -0.1,
      -0.2,
      -0.1,
      0.0,
      -0.1,
      -0.1,
      -0.2,
      -0.1,
      -0.1,
      -0.2,
      -0.2,
      0.0,
      -0.2,
      -0.2,
      -0.1,
      -0.1,
      -0.2,
      -0.1,
      -0.1,
      0.0,
      -0.1,
      -0.2,
      -0.1,
      0.0,
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
    int k = math.max((K ~/ textFineness) ~/ 2 * 2 + 1, 3);
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
    a.sort();
    int index = (a.length.toDouble() * percentile).toInt();
    return a[index];
  }

  //double _percentileValueDouble(List<double> a, double percentile) {
  //  a.sort();
  //  int index = (a.length.toDouble() * percentile).toInt();
  //  return a[index];
  //}

  cv.Mat _stretchMat(
    cv.Mat mat, {
    final double lowPercentile = 0.02,
    final double highValue = 230,
    final double? gamma,
  }) {
    cv.Mat ref = cv.resize(mat, (height ~/ 4, width ~/ 4));
    ref = cv.cvtColor(ref, cv.COLOR_BGR2GRAY);
    List<int> a = ref.data.toList();
    a.removeWhere((value) => value == 255);
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
