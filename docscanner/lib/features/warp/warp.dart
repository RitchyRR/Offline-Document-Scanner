import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/app_shadows.dart';
import '../../widgets/custom_icon_button.dart';
import '../preview/painters/preview_frame_painters.dart';
import 'warp_page_preview_controller.dart';
import 'warp_painters.dart';

class Warp extends StatefulWidget {
  final WarpPagePreviewController pagePreviewController;
  final int docIndex;
  final int pageIndex;
  final String imagePath;
  final List<List<int>> cornerPoints;
  final int rotation;

  const Warp({
    super.key,
    required this.pagePreviewController,
    required this.docIndex,
    required this.pageIndex,
    required this.imagePath,
    required this.cornerPoints,
    required this.rotation,
  });

  @override
  State<Warp> createState() => _WarpState();
}

class _WarpState extends State<Warp> {
  List<Offset> _initialScreenSpaceCorners = [];
  List<Offset> _screenSpaceCorners = [];
  List<List<int>> _corners = [];
  double _screenWidth = 0;
  double _screenHeight = 0;
  double _displayHeigth = 0;
  double _screenSpaceScale = 1.0;
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  int? _currentCorner;
  (int, int)? _currentEdge;
  Offset _touchOffset = Offset(0, 0);
  bool _cornerDragging = false;
  double _imageScale = 0;

  ui.Image? _magnifierImage;
  static const double _magnifierSize = 200;
  double _sideMagnifierSize = 0;

  @override
  void setState(ui.VoidCallback fn) {
    if (!mounted) {
      dev.log("Warning, setStateMounted not mounted at: ${StackTrace.current}");
      return;
    }
    super.setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _initAsync();
    _initMagnifier();
  }

  void _initAsync() async {
    ui.Image image = await decodeImageFromList(
      File(widget.imagePath).readAsBytesSync(),
    );
    if (!mounted) return;
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    _screenWidth = MediaQuery.of(context).size.width;
    _screenHeight = MediaQuery.of(context).size.height - 430;

    _screenSpaceScale = _screenWidth / _imagePixelWidth;
    _displayHeigth = _imagePixelHeight * _screenSpaceScale;
    _sideMagnifierSize = ((_screenWidth - _magnifierSize) / 2) - 8;

    _corners = widget.pagePreviewController.rotateCornerPoints(
      widget.cornerPoints,
    );

    _screenSpaceCorners = _corners
        .map(
          (point) => Offset(
            point[1] * _screenSpaceScale,
            point[0] * _screenSpaceScale,
          ),
        )
        .toList();
    _initialScreenSpaceCorners = List.from(_screenSpaceCorners);
    _cornersHistory.add(List.of(_screenSpaceCorners));

    _scaleImage(init: true);
  }

  void _scaleImage({bool init = false}) {
    double scaleDownY = 0.0;
    for (var point in _screenSpaceCorners) {
      double pointScaleDownY = point.dy - _screenHeight;
      if (pointScaleDownY > scaleDownY) {
        scaleDownY = pointScaleDownY;
      }
    }
    double scaleDownX = 0.0;
    for (var point in _screenSpaceCorners) {
      double pointScaleDownX1 = point.dx - (_screenWidth - _magnifierSize / 4);
      double pointScaleDownX2 = (_magnifierSize / 4) - point.dx;
      double pointScaleDownX = math.max(pointScaleDownX1, pointScaleDownX2);
      if (pointScaleDownX > scaleDownX) {
        scaleDownX = pointScaleDownX;
      }
    }
    double imageScaleY = (_displayHeigth - scaleDownY) / _displayHeigth;
    double imageScaleX = (_screenWidth - scaleDownX) / _screenWidth;
    double newImageScale = math.min(imageScaleY, imageScaleX);
    if (init) {
      _imageScale = newImageScale;
    } else {
      if (mounted) {
        double scaleDiff = newImageScale - _imageScale;
        if (!scaleDiff.isNegative || scaleDiff < 0.1) {
          _imageScale += scaleDiff / 40.0;
          setState(() {});
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initMagnifier() async {
    final file = File(widget.imagePath);
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    if (mounted) {
      _magnifierImage = frameInfo.image;
      setState(() {});
    }
  }

  Future<bool> _leaveConfirmationDialog() async {
    if (_initialScreenSpaceCorners[0] == _screenSpaceCorners[0] &&
        _initialScreenSpaceCorners[1] == _screenSpaceCorners[1] &&
        _initialScreenSpaceCorners[2] == _screenSpaceCorners[2] &&
        _initialScreenSpaceCorners[3] == _screenSpaceCorners[3] &&
        !_panningDelayed) {
      return true;
    }
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel,
                color: Theme.of(context).colorScheme.onSurface,
                size: 30,
              ),
              SizedBox(width: 12),
              Flexible(child: Text(tr("warp.discardPopup.title"))),
            ],
          ),
          content: Text(tr("warp.discardPopup.text")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                tr("warp.discardPopup.discard"),
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    return confirmDelete == true;
  }

  final GlobalKey _imageAreaKey = GlobalKey();
  bool _allowPop = true;
  bool _panningDelayed = false;
  final double _circleSize = 40;

  // Warp
  @override
  Widget build(BuildContext context) {
    bool switchSideMagnifiers = _currentEdge != null && _currentEdge!.$1 != 0;
    (int, int)? sideMagnifiers = _currentEdge != null
        ? _currentEdge!.$1 == 0
              ? (_currentEdge!.$1, _currentEdge!.$2)
              : (_currentEdge!.$2, _currentEdge!.$1)
        : _currentCorner != null
        ? _currentCorner! == 0
              ? (1, 2)
              : _currentCorner! == 1
              ? (0, 3)
              : _currentCorner! == 2
              ? (0, 3)
              : _currentCorner! == 3
              ? (1, 2)
              : null
        : null;
    double cropSize =
        _circleSize / _imageScale / _screenWidth * _imagePixelWidth;
    Rect magnifierCrop =
        _screenSpaceCorners.isNotEmpty &&
            _imageScale != 0 &&
            _screenWidth != 0 &&
            _imagePixelWidth != 0
        ? _currentCorner != null
              ? Rect.fromCenter(
                  center: Offset(
                    _screenSpaceCorners[_currentCorner!].dx / _screenSpaceScale,
                    _screenSpaceCorners[_currentCorner!].dy / _screenSpaceScale,
                  ),
                  width: cropSize,
                  height: cropSize,
                )
              : _currentEdge != null
              ? Rect.fromCenter(
                  center: Offset(
                    Offset.lerp(
                          _screenSpaceCorners[_currentEdge!.$1],
                          _screenSpaceCorners[_currentEdge!.$2],
                          0.5,
                        )!.dx /
                        _screenSpaceScale,
                    Offset.lerp(
                          _screenSpaceCorners[_currentEdge!.$1],
                          _screenSpaceCorners[_currentEdge!.$2],
                          0.5,
                        )!.dy /
                        _screenSpaceScale,
                  ),
                  width: cropSize,
                  height: cropSize,
                )
              : Rect.zero
        : Rect.zero;
    (Rect, Rect) sideMagnifierCrops =
        _screenSpaceCorners.isNotEmpty &&
            _imageScale != 0 &&
            _screenWidth != 0 &&
            _imagePixelWidth != 0
        ? _currentEdge != null
              ? (
                  Rect.fromCenter(
                    center:
                        _screenSpaceCorners[_currentEdge!.$1] /
                        _screenSpaceScale,
                    width: cropSize,
                    height: cropSize,
                  ),
                  Rect.fromCenter(
                    center:
                        _screenSpaceCorners[_currentEdge!.$2] /
                        _screenSpaceScale,
                    width: cropSize,
                    height: cropSize,
                  ),
                )
              : _currentCorner != null
              ? (
                  Rect.fromCenter(
                    center:
                        Offset(
                          Offset.lerp(
                            _screenSpaceCorners[_currentCorner!],
                            _screenSpaceCorners[sideMagnifiers!.$1],
                            0.5,
                          )!.dx,
                          Offset.lerp(
                            _screenSpaceCorners[_currentCorner!],
                            _screenSpaceCorners[sideMagnifiers.$1],
                            0.5,
                          )!.dy,
                        ) /
                        _screenSpaceScale,
                    width: cropSize,
                    height: cropSize,
                  ),
                  Rect.fromCenter(
                    center:
                        Offset(
                          Offset.lerp(
                            _screenSpaceCorners[_currentCorner!],
                            _screenSpaceCorners[sideMagnifiers.$2],
                            0.5,
                          )!.dx,
                          Offset.lerp(
                            _screenSpaceCorners[_currentCorner!],
                            _screenSpaceCorners[sideMagnifiers.$2],
                            0.5,
                          )!.dy,
                        ) /
                        _screenSpaceScale,
                    width: cropSize,
                    height: cropSize,
                  ),
                )
              : (Rect.zero, Rect.zero)
        : (Rect.zero, Rect.zero);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_allowPop) {
          HapticFeedback.heavyImpact();
          if (await _leaveConfirmationDialog()) {
            if (mounted && context.mounted) {
              Navigator.pop(context);
            }
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(tr("warp.title")),
          actions: [
            CustomIconButton(
              onTap: () => _saveCorners(),
              icon: Icons.check,
              tooltip: tr("warp.confirm"),
            ),
            SizedBox(width: 12),
          ],
        ),
        body: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 1.0,
          maxHeight: double.infinity,
          child: Stack(
            children: [
              // Buttons
              _warpButtons(context),

              Column(
                children: [
                  // Magnifier
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (_sideMagnifierSize > 0)
                        SizedBox(
                          width: _sideMagnifierSize,
                          height: _sideMagnifierSize,
                          child:
                              _magnifierImage != null &&
                                  (_currentCorner != null ||
                                      _currentEdge != null)
                              ? Stack(
                                  children: [
                                    SizedBox(
                                      width: _sideMagnifierSize,
                                      height: _sideMagnifierSize,
                                      child: CustomPaint(
                                        painter: CircularCropPainter(
                                          image: _magnifierImage!,
                                          cropRect: switchSideMagnifiers
                                              ? sideMagnifierCrops.$2
                                              : sideMagnifierCrops.$1,
                                        ),
                                      ),
                                    ),
                                    if (_screenWidth != 0 &&
                                        _currentCorner != null)
                                      CustomPaint(
                                        size: Size(
                                          _screenWidth,
                                          _displayHeigth,
                                        ),
                                        painter: ZoomEdgePainter(
                                          cornerPoints: _screenSpaceCorners,
                                          color: Colors.white,
                                          strokeWidth: 1.0,
                                          colorBg: Colors.black45,
                                          strokeWidthBg: 3.0,
                                          currentEdge: (
                                            _currentCorner!,
                                            sideMagnifiers!.$1,
                                          ),
                                          zoomSize: _sideMagnifierSize,
                                        ),
                                      ),
                                    if (_screenWidth != 0 &&
                                        _currentEdge != null)
                                      CustomPaint(
                                        size: Size(
                                          _screenWidth,
                                          _displayHeigth,
                                        ),
                                        painter: ZoomCornerPainter(
                                          cornerPoints: _screenSpaceCorners,
                                          color: Colors.white,
                                          strokeWidth: 1.0,
                                          colorBg: Colors.black45,
                                          strokeWidthBg: 3.0,
                                          currentCorner: sideMagnifiers!.$1,
                                          zoomSize: _sideMagnifierSize,
                                        ),
                                      ),
                                  ],
                                )
                              : SizedBox(),
                        ),
                      SizedBox(
                        width: _magnifierSize,
                        height: _magnifierSize,
                        child:
                            _magnifierImage != null &&
                                (_currentCorner != null || _currentEdge != null)
                            ? Stack(
                                children: [
                                  SizedBox(
                                    width: _magnifierSize,
                                    height: _magnifierSize,
                                    child: CustomPaint(
                                      painter: CircularCropPainter(
                                        image: _magnifierImage!,
                                        cropRect: magnifierCrop,
                                      ),
                                    ),
                                  ),
                                  if (_screenWidth != 0 &&
                                      _currentCorner != null)
                                    CustomPaint(
                                      size: Size(_screenWidth, _displayHeigth),
                                      painter: ZoomCornerPainter(
                                        cornerPoints: _screenSpaceCorners,
                                        color: Colors.white,
                                        strokeWidth: 1.0,
                                        colorBg: Colors.black45,
                                        strokeWidthBg: 3.0,
                                        currentCorner: _currentCorner!,
                                        zoomSize: _magnifierSize,
                                      ),
                                    ),
                                  if (_screenWidth != 0 && _currentEdge != null)
                                    CustomPaint(
                                      size: Size(_screenWidth, _displayHeigth),
                                      painter: ZoomEdgePainter(
                                        cornerPoints: _screenSpaceCorners,
                                        color: Colors.white,
                                        strokeWidth: 1.0,
                                        colorBg: Colors.black45,
                                        strokeWidthBg: 3.0,
                                        currentEdge: _currentEdge!,
                                        zoomSize: _magnifierSize,
                                      ),
                                    ),
                                ],
                              )
                            : SizedBox(),
                      ),
                      if (_sideMagnifierSize > 0)
                        SizedBox(
                          width: _sideMagnifierSize,
                          height: _sideMagnifierSize,
                          child:
                              _magnifierImage != null &&
                                  (_currentCorner != null ||
                                      _currentEdge != null)
                              ? Stack(
                                  children: [
                                    SizedBox(
                                      width: _sideMagnifierSize,
                                      height: _sideMagnifierSize,
                                      child: CustomPaint(
                                        painter: CircularCropPainter(
                                          image: _magnifierImage!,
                                          cropRect: switchSideMagnifiers
                                              ? sideMagnifierCrops.$1
                                              : sideMagnifierCrops.$2,
                                        ),
                                      ),
                                    ),
                                    if (_screenWidth != 0 &&
                                        _currentCorner != null)
                                      CustomPaint(
                                        size: Size(
                                          _screenWidth,
                                          _displayHeigth,
                                        ),
                                        painter: ZoomEdgePainter(
                                          cornerPoints: _screenSpaceCorners,
                                          color: Colors.white,
                                          strokeWidth: 1.0,
                                          colorBg: Colors.black45,
                                          strokeWidthBg: 3.0,
                                          currentEdge: (
                                            _currentCorner!,
                                            sideMagnifiers!.$2,
                                          ),
                                          zoomSize: _sideMagnifierSize,
                                        ),
                                      ),
                                    if (_screenWidth != 0 &&
                                        _currentEdge != null)
                                      CustomPaint(
                                        size: Size(
                                          _screenWidth,
                                          _displayHeigth,
                                        ),
                                        painter: ZoomCornerPainter(
                                          cornerPoints: _screenSpaceCorners,
                                          color: Colors.white,
                                          strokeWidth: 1.0,
                                          colorBg: Colors.black45,
                                          strokeWidthBg: 3.0,
                                          currentCorner: sideMagnifiers!.$2,
                                          zoomSize: _sideMagnifierSize,
                                        ),
                                      ),
                                  ],
                                )
                              : SizedBox(),
                        ),
                    ],
                  ),

                  // Image + CornersOverlay
                  _displayHeigth != 0 && _imageScale != 0
                      ? Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  ((_imageScale * _displayHeigth -
                                          _displayHeigth) /
                                      2),
                                ),
                                child: Transform.scale(
                                  scale: _imageScale,
                                  child: Center(
                                    child: Image.file(File(widget.imagePath)),
                                  ),
                                ),
                              ),
                            ),
                            _draggableCornersOverlay(verticalPadding: 24),
                          ],
                        )
                      : SizedBox(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  final List<List<Offset>> _cornersHistory = [];
  int _cornersHistoryIndex = 0;
  SizedBox _warpButtons(BuildContext context) {
    // Buttons
    const double buttonSize = 36;
    const double buttonSpacing = 10;
    const double buttonPadding = 4;
    return SizedBox(
      width: _screenWidth,
      //margin: EdgeInsets.only(top: _magnifierSize - buttonSize),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              buttonSpacing,
              buttonPadding,
              buttonPadding,
              buttonPadding,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
              boxShadow: [smallBoxShadow(context)],
            ),
            child: Row(
              spacing: buttonSpacing,
              children: [
                CustomIconButton(
                  onTap: () {
                    _screenSpaceCorners = [
                      Offset(0, 0),
                      Offset(0, _displayHeigth - 1),
                      Offset(_screenWidth - 1, 0),
                      Offset(_screenWidth - 1, _displayHeigth - 1),
                    ];
                    _addCurrentToCornersHistory();
                    _scaleImage(init: true);
                  },
                  isDisabled: listEquals(_screenSpaceCorners, [
                    Offset(0, 0),
                    Offset(0, _displayHeigth - 1),
                    Offset(_screenWidth - 1, 0),
                    Offset(_screenWidth - 1, _displayHeigth - 1),
                  ]),
                  icon: Icons.fullscreen,
                  tooltip: tr("warp.buttons.fullscreen"),
                  buttonColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  width: buttonSize,
                  height: buttonSize,
                ),
                CustomIconButton(
                  onTap: () {
                    _screenSpaceCorners = _initialScreenSpaceCorners;
                    _addCurrentToCornersHistory();
                    _scaleImage(init: true);
                  },
                  isDisabled: listEquals(
                    _screenSpaceCorners,
                    _initialScreenSpaceCorners,
                  ),
                  icon: Icons.restart_alt,
                  tooltip: tr("warp.buttons.reset"),
                  buttonColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  width: buttonSize,
                  height: buttonSize,
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              buttonPadding,
              buttonPadding,
              buttonSpacing,
              buttonPadding,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
              boxShadow: [smallBoxShadow(context)],
            ),
            child: Row(
              spacing: buttonSpacing,
              children: [
                CustomIconButton(
                  onTap: () {
                    _screenSpaceCorners = List.of(
                      _cornersHistory[++_cornersHistoryIndex],
                    );
                    _scaleImage(init: true);
                  },
                  isDisabled:
                      _cornersHistoryIndex + 1 >= _cornersHistory.length,
                  icon: Icons.undo,
                  tooltip: tr("warp.buttons.undo"),
                  buttonColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  width: buttonSize,
                  height: buttonSize,
                ),
                CustomIconButton(
                  onTap: () {
                    _screenSpaceCorners = List.of(
                      _cornersHistory[--_cornersHistoryIndex],
                    );
                    _scaleImage(init: true);
                  },
                  isDisabled: (_cornersHistoryIndex <= 0),
                  icon: Icons.redo,
                  tooltip: tr("warp.buttons.redo"),
                  buttonColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  width: buttonSize,
                  height: buttonSize,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addCurrentToCornersHistory() {
    if (listEquals(_screenSpaceCorners, _cornersHistory.first)) return;
    final int maxSize = (_cornersHistory.length).clamp(0, 100);
    final subList = _cornersHistory.sublist(_cornersHistoryIndex, maxSize);
    _cornersHistory.clear();
    _cornersHistory.addAll(subList);
    _cornersHistory.insert(0, List.of(_screenSpaceCorners));
    _cornersHistoryIndex = 0;
  }

  void _saveCorners() {
    for (var (i, scaledPoint) in _screenSpaceCorners.indexed) {
      widget.cornerPoints[i] = [
        (scaledPoint.dy / _screenSpaceScale).toInt(),
        (scaledPoint.dx / _screenSpaceScale).toInt(),
      ];
    }
    widget.pagePreviewController.reprocessPhoto(
      newCornerPointsIn: widget.cornerPoints,
    );
    _allowPop = true;
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  void didUpdateWidget(Warp oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only reload the image if the imagePath changed
    if (widget.imagePath != oldWidget.imagePath) {
      setState(() {
        _magnifierImage = null;
      });
      _initMagnifier();
    }
  }

  Widget _draggableCornersOverlay({final double verticalPadding = 24.0}) {
    if (_screenWidth == 0 || _imageScale == 0) {
      return SizedBox();
    }

    double scaledWidth = _screenWidth * _imageScale;
    double scaledHeight = _displayHeigth * _imageScale;

    double xOffset = (_screenWidth - scaledWidth) / 2;
    double yOffset = (_displayHeigth - scaledHeight) / 2;

    List<Offset> scaledPoints = _screenSpaceCorners
        .map(
          (e) => Offset(
            e.dx * _imageScale + xOffset,
            e.dy * _imageScale + verticalPadding,
          ),
        )
        .toList();

    return Center(
      child: SizedBox(
        key: _imageAreaKey,
        width: _screenWidth,
        height: _displayHeigth + verticalPadding * 2,
        child: Stack(
          children: [
            // Sharp corners reaching outside circle
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: CornerLinePainter(
                  points: scaledPoints,
                  color: Theme.of(context).colorScheme.primaryFixed,
                  strokeWidth: 1.0,
                  offset: 0.25,
                  normalizedOffset: false,
                ),
              ),
            ),

            // Draggable edges
            ...[
              [0, 2, 1, 3], // top
              [2, 3, 0, 1], // right
              [3, 1, 2, 0], // bottom
              [1, 0, 3, 2], // left
            ].map((points) {
              final a = scaledPoints[points[0]];
              final b = scaledPoints[points[1]];
              final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
              final length = (b - a).distance;
              final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
              final edgeThickness = 20.0;
              final lengthUsed = 0.5;

              bool isCurrent = _currentEdge == (points[0], points[1]);

              return Positioned(
                left: center.dx - length * lengthUsed / 2,
                top: center.dy - edgeThickness / 2,

                child: Transform.rotate(
                  angle: angle,
                  child: Container(
                    width: length * lengthUsed,
                    height: edgeThickness,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(edgeThickness / 2),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primaryFixed,
                        width: isCurrent ? 4.0 : 2.0,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      color: Colors.black12,
                    ),
                    child: GestureDetector(
                      onPanStart: (details) {
                        _currentEdge = (points[0], points[1]);
                        _currentCorner = null;
                      },
                      onPanUpdate: (details) => _handleEdgePan(
                        indexA: points[0],
                        indexB: points[1],
                        neighborA: points[2],
                        neighborB: points[3],
                        details: details,
                      ),
                      onPanEnd: (details) => _handleEdgePanEnd(
                        indexA: points[0],
                        indexB: points[1],
                        neighborA: points[2],
                        neighborB: points[3],
                      ),
                    ),
                  ),
                ),
              );
            }),

            // Draggable corner points
            ...scaledPoints.asMap().entries.map((entry) {
              final index = entry.key;
              final offset = entry.value;
              final isCurrent = index == _currentCorner;

              return Positioned(
                left: offset.dx - _circleSize / 2,
                top: offset.dy - _circleSize / 2,
                child: GestureDetector(
                  onPanStart: (details) {
                    if (_cornerDragging) return;
                    _allowPop = false;
                    _currentCorner = index;
                    _currentEdge = null;
                    final box =
                        _imageAreaKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box == null) return;

                    Offset localPosition =
                        (box.globalToLocal(details.globalPosition) -
                            Offset(xOffset, yOffset)) /
                        _imageScale;
                    _touchOffset = localPosition - _screenSpaceCorners[index];

                    _recentCornerPositions.clear();
                    _recentCornerPositions.add(
                      PositionTimestamp(
                        position: _screenSpaceCorners[index],
                        timestamp: DateTime.now(),
                      ),
                    );
                    _cornerDragging = true;
                    _panningDelayed = true;
                  },
                  onPanUpdate: (details) {
                    final box =
                        _imageAreaKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box == null) return;

                    Offset localPosition =
                        (box.globalToLocal(details.globalPosition) -
                            Offset(xOffset, yOffset)) /
                        _imageScale;
                    Offset newPos = localPosition - _touchOffset;

                    newPos = Offset(
                      newPos.dx.clamp(0.0, _screenWidth),
                      newPos.dy.clamp(0.0, _displayHeigth),
                    );

                    // Limit relative corner positions
                    newPos = _limitCornerPointPos(index, newPos);

                    DateTime now = DateTime.now();
                    // Haptic Feedback
                    if (_recentCornerPositions.isNotEmpty &&
                        now.difference(_recentCornerPositions.last.timestamp) >
                            Duration(milliseconds: 25)) {
                      HapticFeedback.selectionClick();
                    }
                    // Average position over time -> new pos
                    Offset avgPos = Offset(0, 0);
                    int avgCount = 0;
                    for (var timePos in _recentCornerPositions) {
                      if ((newPos - timePos.position).distance < 30.0) {
                        avgPos += timePos.position;
                        avgCount++;
                      }
                    }
                    if (avgCount != 0) {
                      avgPos /= avgCount.toDouble();
                      avgPos += newPos * 0.5;
                      avgPos /= 1.5;
                    } else {
                      avgPos = newPos;
                    }
                    setState(() {
                      _screenSpaceCorners[index] = avgPos;
                    });
                    _scaleImage();

                    // Add current position to history
                    _recentCornerPositions.add(
                      PositionTimestamp(
                        position: _screenSpaceCorners[index],
                        timestamp: now,
                      ),
                    );
                    // Remove oldest position if older than _historyDurationMs
                    if (now
                            .difference(_recentCornerPositions.first.timestamp)
                            .inMilliseconds >
                        _historyDelayMs) {
                      _recentCornerPositions.removeAt(0);
                    }
                  },
                  onPanEnd: (details) => _handleCornerPanEnd(index),
                  onPanCancel: () => _handleCornerPanEnd(index),
                  // Circle
                  child: Container(
                    width: _circleSize,
                    height: _circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black26,
                      border: isCurrent
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primaryFixed,
                              width: 4,
                              strokeAlign: BorderSide.strokeAlignOutside,
                            )
                          : Border.all(
                              color: Theme.of(context).colorScheme.primaryFixed,
                              width: 2,
                              strokeAlign: BorderSide.strokeAlignOutside,
                            ),
                    ),
                  ),
                ),
              );
            }),

            // Sharp edge in middle section
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: MiddleLinePainter(
                  points: scaledPoints,
                  color: Colors.white,
                  strokeWidth: 1.0,
                  offset: 0.55,
                  normalizedOffset: false,
                ),
              ),
            ),
            // Sharp corners inside circle
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: CornerLinePainter(
                  points: scaledPoints,
                  color: Colors.white,
                  strokeWidth: 1.0,
                  offset: (_circleSize + 2) / 2,
                  normalizedOffset: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Offset _limitCornerPointPos(int cornerIndex, Offset newPos) {
    switch (cornerIndex) {
      case 0: // top left
        double maxX = [
          _screenSpaceCorners[2].dx,
          _screenSpaceCorners[3].dx,
        ].reduce(math.min);
        double maxY = [
          _screenSpaceCorners[1].dy,
          _screenSpaceCorners[3].dy,
        ].reduce(math.min);
        if (newPos.dx > maxX) {
          newPos = Offset(maxX, newPos.dy);
        }
        if (newPos.dy > maxY) {
          newPos = Offset(newPos.dx, maxY);
        }
        break;
      case 1: // bottom left
        double maxX = [
          _screenSpaceCorners[2].dx,
          _screenSpaceCorners[3].dx,
        ].reduce(math.min);
        double minY = [
          _screenSpaceCorners[0].dy,
          _screenSpaceCorners[2].dy,
        ].reduce(math.max);
        if (newPos.dx > maxX) {
          newPos = Offset(maxX, newPos.dy);
        }
        if (newPos.dy < minY) {
          newPos = Offset(newPos.dx, minY);
        }
        break;
      case 2: // top right
        double minX = [
          _screenSpaceCorners[0].dx,
          _screenSpaceCorners[1].dx,
        ].reduce(math.max);
        double maxY = [
          _screenSpaceCorners[1].dy,
          _screenSpaceCorners[3].dy,
        ].reduce(math.min);
        if (newPos.dx < minX) {
          newPos = Offset(minX, newPos.dy);
        }
        if (newPos.dy > maxY) {
          newPos = Offset(newPos.dx, maxY);
        }
        break;
      case 3: // bottom right
        double minX = [
          _screenSpaceCorners[0].dx,
          _screenSpaceCorners[1].dx,
        ].reduce(math.max);
        double minY = [
          _screenSpaceCorners[0].dy,
          _screenSpaceCorners[2].dy,
        ].reduce(math.max);
        if (newPos.dx < minX) {
          newPos = Offset(minX, newPos.dy);
        }
        if (newPos.dy < minY) {
          newPos = Offset(newPos.dx, minY);
        }
        break;
      default:
    }
    return newPos;
  }

  void _handleEdgePan({
    required int indexA,
    required int indexB,
    required int neighborA,
    required int neighborB,
    required DragUpdateDetails details,
  }) {
    _allowPop = false;

    final Offset a = _screenSpaceCorners[indexA];
    final Offset b = _screenSpaceCorners[indexB];
    final Offset na = _screenSpaceCorners[neighborA];
    final Offset nb = _screenSpaceCorners[neighborB];

    final double dragAmount =
        -details.delta.dy; // fixed vertical axis + flipped

    Offset dirA = a - na;
    Offset dirB = b - nb;
    Offset dirNewA;
    Offset dirNewB;
    Offset newA;
    Offset newB;
    do {
      final Offset normA = dirA / dirA.distance;
      final Offset normB = dirB / dirB.distance;

      final Offset moveA = normA * dragAmount;
      final Offset moveB = normB * dragAmount;

      newA = a + moveA;
      newB = b + moveB;

      newA = Offset(
        newA.dx.clamp(0.0, _screenWidth),
        newA.dy.clamp(0.0, _displayHeigth),
      );
      newB = Offset(
        newB.dx.clamp(0.0, _screenWidth),
        newB.dy.clamp(0.0, _displayHeigth),
      );

      dirNewA = newA - na;
      dirNewB = newB - nb;

      dirA *= -1;
      dirB *= -1;
    } while ((dirNewA.distance < 5 || dirNewB.distance < 5) &&
        (dirNewA.distance < dirA.distance ||
            dirNewB.distance < dirNewB.distance));

    DateTime now = DateTime.now();
    // Haptic Feedback
    if (_recentEdgePositions.isNotEmpty &&
        now.difference(_recentEdgePositions.last.$1.timestamp) >
            Duration(milliseconds: 25)) {
      HapticFeedback.selectionClick();
    }
    // Average position over time -> new pos
    Offset avgPosA = Offset(0, 0);
    Offset avgPosB = Offset(0, 0);
    int avgCount = 0;
    for (var edgeTimePos in _recentEdgePositions) {
      if ((newA - edgeTimePos.$1.position).distance < 0.9) {
        avgPosA += edgeTimePos.$1.position;
        avgPosB += edgeTimePos.$2.position;
        avgCount++;
      }
    }
    if (avgCount != 0) {
      avgPosA /= avgCount.toDouble();
      avgPosB /= avgCount.toDouble();
      avgPosA += newA * 2;
      avgPosB += newB * 2;
      avgPosA /= 3;
      avgPosB /= 3;
    } else {
      avgPosA = newA;
      avgPosB = newB;
    }
    setState(() {
      _screenSpaceCorners[indexA] = avgPosA;
      _screenSpaceCorners[indexB] = avgPosB;
    });
    _scaleImage();

    // Add current position to history
    _recentEdgePositions.add((
      PositionTimestamp(position: _screenSpaceCorners[indexA], timestamp: now),
      PositionTimestamp(position: _screenSpaceCorners[indexB], timestamp: now),
    ));
    // Remove oldest position if older than _historyDurationMs
    if (now.difference(_recentEdgePositions.first.$1.timestamp).inMilliseconds >
        _historyDelayMs) {
      _recentEdgePositions.removeAt(0);
    }
  }

  final List<(PositionTimestamp, PositionTimestamp)> _recentEdgePositions = [];
  void _handleEdgePanEnd({
    required int indexA,
    required int indexB,
    required int neighborA,
    required int neighborB,
  }) {
    // Remove positions older than _historyDurationMs
    DateTime now = DateTime.now();
    while (_recentEdgePositions.isNotEmpty &&
        now.difference(_recentEdgePositions.first.$1.timestamp).inMilliseconds >
            _historyDelayMs) {
      _recentEdgePositions.removeAt(0);
    }
    // Use oldest position in history
    if (_recentEdgePositions.isNotEmpty) {
      if ((_recentEdgePositions.first.$1.position - _screenSpaceCorners[indexA])
              .distance <
          50) {
        setState(() {
          _screenSpaceCorners[indexA] = _recentEdgePositions.first.$1.position;
          _screenSpaceCorners[indexB] = _recentEdgePositions.first.$2.position;
        });
      }
    }
    _recentEdgePositions.clear();
    _addCurrentToCornersHistory();
  }

  final List<PositionTimestamp> _recentCornerPositions = [];
  static const int _historyDelayMs = 300;
  void _handleCornerPanEnd(int index) {
    if (!_cornerDragging) return;
    // Remove positions older than _historyDurationMs
    DateTime now = DateTime.now();
    while (_recentCornerPositions.isNotEmpty &&
        now.difference(_recentCornerPositions.first.timestamp).inMilliseconds >
            _historyDelayMs) {
      _recentCornerPositions.removeAt(0);
    }
    // Use oldest position in history
    if (_recentCornerPositions.isNotEmpty) {
      if ((_recentCornerPositions.first.position - _screenSpaceCorners[index])
              .distance <
          50) {
        setState(() {
          _screenSpaceCorners[index] = _recentCornerPositions.first.position;
        });
      }
    }
    _recentCornerPositions.clear();
    _cornerDragging = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 600));
      _panningDelayed = false;
    });
    _addCurrentToCornersHistory();
  }
}

class PositionTimestamp {
  final Offset position;
  final DateTime timestamp;

  PositionTimestamp({required this.position, required this.timestamp});
}
