import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class CustomPhotoViewer extends StatefulWidget {
  const CustomPhotoViewer({
    super.key,
    required this.imagePath,
    required this.child,
    this.imageSize,
    this.onScaleChanged,
    this.onMultiTouchChanged,
    this.onZoomChanged,
    this.onPageDragUpdate,
    this.onPageDragEnd,
  });

  final String imagePath;
  final Widget child;
  final Size? imageSize;
  final void Function(double displayScale, bool isZoomed)? onScaleChanged;
  final ValueChanged<bool>? onMultiTouchChanged;
  final ValueChanged<bool>? onZoomChanged;
  final ValueChanged<double>? onPageDragUpdate;
  final void Function(double progress, double velocity)? onPageDragEnd;

  @override
  State<CustomPhotoViewer> createState() => _CustomPhotoViewerState();
}

class _CustomPhotoViewerState extends State<CustomPhotoViewer>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _animationController;
  late Animation<Matrix4> _animation;
  Offset? _doubleTapPosition;
  double _containedScale = 1;
  Size? _resolvedImageSize;
  int _activePointerCount = 0;
  double _visualRotation = 0;
  double _continuousGestureRotation = 0;
  double _lastGestureRotation = 0;
  bool _isTrackingRotation = false;
  double _visualScale = 1;
  Offset _lastRotationFocalPoint = Offset.zero;
  Size _viewportSize = Size.zero;
  Timer? _settleTimer;
  bool _imageGestureActive = false;
  int _gestureGeneration = 0;
  Matrix4 _gestureStartTransform = Matrix4.identity();
  Offset _gestureStartFocalPoint = Offset.zero;
  double _pageDragProgress = 0;
  bool _pageDragStarted = false;
  late final AnimationController _rotationAnimationController;
  late Animation<double> _rotationAnimation;
  late final AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = AlwaysStoppedAnimation(Matrix4.identity());
    _animationController.addListener(() {
      _transformationController.value = _animation.value;
      _reportScale();
    });
    _rotationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _rotationAnimation = const AlwaysStoppedAnimation(0);
    _rotationAnimationController.addListener(() {
      setState(() => _visualRotation = _rotationAnimation.value);
    });
    _scaleAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = const AlwaysStoppedAnimation(1);
    _scaleAnimationController.addListener(() {
      setState(() => _visualScale = _scaleAnimation.value);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant CustomPhotoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _animationController.stop();
      _transformationController.value = Matrix4.identity();
      _resolvedImageSize = null;
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _animationController.dispose();
    _rotationAnimationController.dispose();
    _scaleAnimationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _resolveImageSize() {
    if (widget.imageSize != null) return;
    final stream = FileImage(
      File(widget.imagePath),
    ).resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((imageInfo, _) {
      stream.removeListener(listener);
      final imageSize = Size(
        imageInfo.image.width.toDouble(),
        imageInfo.image.height.toDouble(),
      );
      if (mounted && _resolvedImageSize != imageSize) {
        setState(() => _resolvedImageSize = imageSize);
      }
    }, onError: (error, stackTrace) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  void _reportScale() {
    final transform = _transformationController.value;
    final zoomScale = transform.getMaxScaleOnAxis();
    final isZoomed = (zoomScale - 1).abs() > 0.01;
    widget.onScaleChanged?.call(_containedScale * zoomScale, isZoomed);
    widget.onZoomChanged?.call(isZoomed);
  }

  void _updatePointerCount(int change) {
    _activePointerCount = math.max(0, _activePointerCount + change);
    widget.onMultiTouchChanged?.call(_activePointerCount > 1);
    if (_activePointerCount == 0 && _imageGestureActive) {
      _scheduleTransformSettle();
    }
  }

  Rect get _containedImageRect {
    final imageSize = widget.imageSize ?? _resolvedImageSize;
    if (imageSize == null || _viewportSize.isEmpty) {
      return Offset.zero & _viewportSize;
    }
    final size = Size(
      imageSize.width * _containedScale,
      imageSize.height * _containedScale,
    );
    return Offset(
          (_viewportSize.width - size.width) / 2,
          (_viewportSize.height - size.height) / 2,
        ) &
        size;
  }

  Offset _clampTranslation(Offset translation, double scale) {
    final imageRect = _containedImageRect;
    return Offset(
      translation.dx.clamp(
        imageRect.right * (1 - scale),
        imageRect.left * (1 - scale),
      ),
      translation.dy.clamp(
        imageRect.bottom * (1 - scale),
        imageRect.top * (1 - scale),
      ),
    );
  }

  Matrix4 _transformFor(double scale, Offset translation) {
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, translation.dx)
      ..setEntry(1, 3, translation.dy);
  }

  void _handleDoubleTap() {
    final current = _transformationController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final maxScale = math.max(1.0, 1 / _containedScale);
    final firstZoomScale = math.min(2.0, maxScale);
    final targetScale = currentScale <= 1.01
        ? firstZoomScale
        : currentScale <= firstZoomScale + 0.01 &&
              maxScale > firstZoomScale + 0.01
        ? maxScale
        : 1.0;
    final Matrix4 target;
    if (targetScale == 1) {
      target = Matrix4.identity();
    } else {
      final focalPoint = _doubleTapPosition ?? Offset.zero;
      final translation = current.getTranslation();
      final targetTranslation =
          focalPoint -
          (focalPoint - Offset(translation.x, translation.y)) *
              targetScale /
              currentScale;
      final boundedTranslation = _clampTranslation(
        targetTranslation,
        targetScale,
      );
      target = _transformFor(targetScale, boundedTranslation);
    }
    _animation = Matrix4Tween(begin: current, end: target).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward(from: 0);
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _settleTimer?.cancel();
    _gestureGeneration++;
    _animationController.stop();
    _rotationAnimationController.stop();
    _scaleAnimationController.stop();
    _visualRotation = 0;
    _continuousGestureRotation = 0;
    _lastGestureRotation = 0;
    _isTrackingRotation = false;
    _visualScale = 1;
    _lastRotationFocalPoint = details.localFocalPoint;
    _imageGestureActive = true;
    _gestureStartTransform = Matrix4.copy(_transformationController.value);
    _gestureStartFocalPoint = details.localFocalPoint;
    _pageDragProgress = 0;
    _pageDragStarted = false;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    final startScale = _gestureStartTransform.getMaxScaleOnAxis();
    final maxScale = math.max(1.0, 1 / _containedScale);
    final requestedScale = startScale * details.scale;
    final targetScale = requestedScale.clamp(1.0, maxScale);
    final scaleFactor = targetScale / startScale;
    final startTranslation = _gestureStartTransform.getTranslation();
    if (details.pointerCount == 1 &&
        startScale > 1.01 &&
        (details.scale - 1).abs() < 0.01) {
      final imageRect = _containedImageRect;
      final minTranslationX = imageRect.right * (1 - startScale);
      final maxTranslationX = imageRect.left * (1 - startScale);
      final horizontalDelta =
          details.localFocalPoint.dx - _gestureStartFocalPoint.dx;
      if ((horizontalDelta < 0 && startTranslation.x <= minTranslationX + 1) ||
          (horizontalDelta > 0 && startTranslation.x >= maxTranslationX - 1)) {
        _pageDragStarted = true;
        _pageDragProgress = (-horizontalDelta / _viewportSize.width).clamp(
          -1.0,
          1.0,
        );
        widget.onPageDragUpdate?.call(_pageDragProgress);
        return;
      }
    }
    if (_pageDragProgress != 0) {
      _pageDragProgress = 0;
      widget.onPageDragUpdate?.call(0);
    }
    final targetTranslation =
        details.localFocalPoint -
        (_gestureStartFocalPoint -
                Offset(startTranslation.x, startTranslation.y)) *
            scaleFactor;
    final boundedTranslation = _clampTranslation(
      targetTranslation,
      targetScale,
    );
    _transformationController.value = _transformFor(
      targetScale,
      boundedTranslation,
    );

    if (details.pointerCount > 1) {
      if (_isTrackingRotation) {
        _continuousGestureRotation += _normalizeRotationDelta(
          details.rotation - _lastGestureRotation,
        );
      } else {
        _continuousGestureRotation += _normalizeRotationDelta(details.rotation);
        _isTrackingRotation = true;
      }
      _lastGestureRotation = details.rotation;
      _visualRotation = _dampenRotation(_continuousGestureRotation);
      _lastRotationFocalPoint = details.localFocalPoint;
      setState(() {});
    } else {
      _isTrackingRotation = false;
    }
    if (requestedScale < 1) {
      setState(() => _visualScale = requestedScale.clamp(0.5, 1.0));
    } else if (_visualScale != 1) {
      setState(() => _visualScale = 1);
    }
    _reportScale();
  }

  double _normalizeRotationDelta(double delta) {
    const fullTurn = 2 * math.pi;
    while (delta > math.pi) {
      delta -= fullTurn;
    }
    while (delta < -math.pi) {
      delta += fullTurn;
    }
    return delta;
  }

  double _dampenRotation(double rotation) {
    const maxInputRotation = math.pi / 2;
    const maxVisualRotation = math.pi / 6;
    final progress = (rotation.abs() / maxInputRotation).clamp(0.0, 1.0);
    final easedProgress =
        progress * progress * progress * (progress * (progress * 6 - 15) + 10);
    return rotation.sign * maxVisualRotation * easedProgress;
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    if (_pageDragStarted) {
      widget.onPageDragEnd?.call(
        _pageDragProgress,
        -details.velocity.pixelsPerSecond.dx,
      );
      _pageDragProgress = 0;
      _pageDragStarted = false;
    }
    _scheduleTransformSettle();
    _rotationAnimation = Tween<double>(begin: _visualRotation, end: 0).animate(
      CurvedAnimation(
        parent: _rotationAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
    _rotationAnimationController.forward(from: 0);
    _scaleAnimation = Tween<double>(begin: _visualScale, end: 1).animate(
      CurvedAnimation(
        parent: _scaleAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
    _scaleAnimationController.forward(from: 0);
  }

  void _scheduleTransformSettle() {
    _settleTimer?.cancel();
    final gestureGeneration = _gestureGeneration;
    _settleTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted || gestureGeneration != _gestureGeneration) return;
      _imageGestureActive = false;
      final current = Matrix4.copy(_transformationController.value);
      final scale = current.getMaxScaleOnAxis();
      final target = scale <= 1.01
          ? Matrix4.identity()
          : _transformFor(
              scale,
              _clampTranslation(
                Offset(current.getTranslation().x, current.getTranslation().y),
                scale,
              ),
            );
      _animation = Matrix4Tween(begin: current, end: target).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutCubic,
        ),
      );
      _animationController.forward(from: 0);
      Timer(const Duration(milliseconds: 220), () {
        if (mounted && gestureGeneration == _gestureGeneration) {
          _transformationController.value = target;
          _reportScale();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        final imageSize = widget.imageSize ?? _resolvedImageSize;
        if (imageSize != null) {
          _containedScale = math.min(
            constraints.maxWidth / imageSize.width,
            constraints.maxHeight / imageSize.height,
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reportScale();
        });
        return Listener(
          onPointerDown: (_) => _updatePointerCount(1),
          onPointerUp: (_) => _updatePointerCount(-1),
          onPointerCancel: (_) => _updatePointerCount(-1),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: (details) {
              _doubleTapPosition = details.localPosition;
            },
            onDoubleTap: _handleDoubleTap,
            onScaleStart: _handleInteractionStart,
            onScaleUpdate: _handleInteractionUpdate,
            onScaleEnd: _handleInteractionEnd,
            child: Transform.scale(
              scale: _visualScale,
              alignment: Alignment(
                _viewportSize.width == 0
                    ? 0
                    : _lastRotationFocalPoint.dx / _viewportSize.width * 2 - 1,
                _viewportSize.height == 0
                    ? 0
                    : _lastRotationFocalPoint.dy / _viewportSize.height * 2 - 1,
              ),
              child: Transform.rotate(
                angle: _visualRotation,
                alignment: Alignment(
                  _viewportSize.width == 0
                      ? 0
                      : _lastRotationFocalPoint.dx / _viewportSize.width * 2 -
                            1,
                  _viewportSize.height == 0
                      ? 0
                      : _lastRotationFocalPoint.dy / _viewportSize.height * 2 -
                            1,
                ),
                child: AnimatedBuilder(
                  animation: _transformationController,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: widget.child,
                  ),
                  builder: (context, child) {
                    return Transform(
                      transform: _transformationController.value,
                      child: child,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
