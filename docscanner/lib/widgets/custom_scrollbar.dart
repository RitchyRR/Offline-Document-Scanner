import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_shadows.dart';

class CustomScrollController extends ScrollController {
  VoidCallback? resetCallback;

  void reset() {
    resetCallback?.call();
  }
}

class CustomScrollbar extends StatefulWidget {
  final Widget child;
  final CustomScrollController controller;
  final List<double> pageAspectRatios;
  final Color? backgroundColor;
  final Color? textColor;
  final Duration thumbVisibilityDuration;
  final Duration thumbVisibilityFadeDuration;
  final double scrollRangeStart; // 0.0 to 1.0
  final double scrollRangeEnd; // 0.0 to 1.0
  final bool noTumb;
  final TransformationController? transformationController;
  final GlobalKey? canvasKey;

  const CustomScrollbar({
    super.key,
    required this.child,
    required this.controller,
    required this.pageAspectRatios,
    this.backgroundColor,
    this.textColor,
    this.thumbVisibilityDuration = const Duration(milliseconds: 1000),
    this.thumbVisibilityFadeDuration = const Duration(milliseconds: 200),
    this.scrollRangeStart = 0.0,
    this.scrollRangeEnd = 1.0,
    this.noTumb = false,
    this.transformationController,
    this.canvasKey,
  });

  @override
  State<CustomScrollbar> createState() => _CustomScrollbarState();
}

class _CustomScrollbarState extends State<CustomScrollbar>
    with TickerProviderStateMixin {
  double _thumbTop = 0.0;
  bool _isThumbVisible = false;
  bool _isDragging = false;
  Timer? _hideTimer;
  int _lastPage = 0;
  static const double _thumbSize = 56;
  double _viewportHeight = 0;

  bool get _usesCanvas =>
      widget.transformationController != null && widget.canvasKey != null;

  bool get _hasScrollableContent => _usesCanvas
      ? _canvasHeight * _canvasScale > _viewportHeight
      : widget.controller.hasClients;

  double get _canvasHeight {
    final renderObject = widget.canvasKey?.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject.size.height : 0;
  }

  double get _canvasScale =>
      widget.transformationController!.value.getMaxScaleOnAxis();

  double get _scrollOffset => _usesCanvas
      ? (-widget.transformationController!.value.getTranslation().y).clamp(
          0.0,
          _maxScroll,
        )
      : widget.controller.offset;

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
    widget.controller.addListener(_scrollListener);
    widget.transformationController?.addListener(_scrollListener);
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.thumbVisibilityFadeDuration,
    );
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_fadeController);
    _railSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _railSlideAnimation =
        Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(1.5, 0), // slide off to the right
        ).animate(
          CurvedAnimation(
            parent: _railSlideController,
            curve: Curves.easeInOut,
          ),
        );
    _setRatios();
    widget.controller.resetCallback = () {
      if (mounted) {
        if (_usesCanvas) {
          widget.transformationController!.value = Matrix4.identity();
        } else {
          widget.controller.jumpTo(0);
        }
      }
    };
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollListener);
    widget.transformationController?.removeListener(_scrollListener);
    _hideTimer?.cancel();
    _fadeController.dispose();
    _railSlideController.dispose();
    super.dispose();
  }

  double _maxScroll = 0.0;
  Future<void> _setMaxScroll({bool jump = false}) async {
    if (_usesCanvas) {
      _maxScroll = math.max(0, _canvasHeight * _canvasScale - _viewportHeight);
      return;
    }
    if (!widget.controller.hasClients ||
        !widget.controller.position.hasContentDimensions) {
      return;
    }
    double newMaxScroll = widget.controller.position.maxScrollExtent;
    double curretnPos = widget.controller.offset;

    if (newMaxScroll != 0.0) {
      if (jump) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          _maxScroll = newMaxScroll;
        });
      } else if (_maxScroll == 0) {
        // Instantly set initially
        _maxScroll = newMaxScroll;
      } else if (curretnPos >= newMaxScroll) {
        // Instantly scroll to end
        _maxScroll = newMaxScroll;
      } else if (newMaxScroll != _maxScroll) {
        double diffRatio = newMaxScroll / _maxScroll;
        diffRatio = diffRatio < 1 ? 1 / diffRatio : diffRatio;
        if (diffRatio > 2.0) {
          // Instantly set if very different
          _maxScroll = newMaxScroll;
        } else {
          // Slowly update _maxScroll
          double diff = newMaxScroll - _maxScroll;
          _maxScroll += diff.isNegative ? -1.0 : 1.0;
        }
      }
    }
  }

  List<double> _ratios = [];
  void _setRatios() {
    final List<double> priorRatios = List<double>.from(_ratios);
    if (widget.pageAspectRatios.isEmpty) return;
    _ratios = List<double>.generate(
      widget.pageAspectRatios.length,
      (index) => 1.0 / widget.pageAspectRatios[index],
    );
    _ratios[0] /= 2;
    _ratios[_ratios.length - 1] /= 2;
    setState(() {});
    if (_ratios.sum != priorRatios.sum) {
      _setMaxScroll(jump: true);
    }
  }

  void _scrollListener() {
    if (_isDragging) {
      return;
    }

    _setMaxScroll();

    _showThumbTemporarily();
    _updateThumbPosition();
    _maybeTriggerHaptics();
  }

  void _updateThumbPosition() {
    if (!_usesCanvas &&
        (!widget.controller.hasClients ||
            !widget.controller.position.hasContentDimensions)) {
      return;
    }

    final viewportHeight = _usesCanvas
        ? _viewportHeight
        : widget.controller.position.viewportDimension;

    final scrollFraction = _maxScroll == 0
        ? 0
        : (_scrollOffset / _maxScroll).clamp(0.0, 1.0);
    final thumbTravelHeight =
        viewportHeight * (widget.scrollRangeEnd - widget.scrollRangeStart);

    setState(() {
      _thumbTop =
          viewportHeight * widget.scrollRangeStart +
          (thumbTravelHeight - _thumbSize) * scrollFraction;
    });
  }

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _railSlideController;
  late Animation<Offset> _railSlideAnimation;
  void _showThumbTemporarily() {
    if (widget.noTumb) return;
    _hideTimer?.cancel();

    if (!_isThumbVisible) {
      setState(() {
        _isThumbVisible = true;
      });
    }

    _railSlideController.reset(); // Bring rail back into view
    _fadeController.reset(); // Make thumb is fully visible before fade

    _hideTimer = Timer(widget.thumbVisibilityDuration, () async {
      if (!_isDragging && mounted) {
        List<Future> animations = [];
        animations.add(_fadeController.forward());
        animations.add(_railSlideController.forward());
        await Future.wait(animations);
        if (mounted) {
          setState(() {
            _isThumbVisible = false;
            _isDragging = false;
          });
          _fadeController.reset();
        }
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    _hideTimer?.cancel();

    setState(() {
      _isDragging = true;
      _isThumbVisible = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double containerHeight) {
    _setMaxScroll();

    // move thumb
    final minTop = containerHeight * widget.scrollRangeStart;
    final maxTop = containerHeight * widget.scrollRangeEnd - _thumbSize;
    _thumbTop = (details.globalPosition.dy - minTop - _thumbSize).clamp(
      minTop,
      maxTop,
    );
    setState(() {});

    // move page
    final scrollAreaHeight = maxTop - minTop;
    final scrollFraction = (_thumbTop - minTop) / scrollAreaHeight;

    final newScrollOffset = scrollFraction * _maxScroll;
    if (_isDragging) {
      if (_usesCanvas) {
        widget.transformationController!.value = Matrix4.copy(
          widget.transformationController!.value,
        )..setEntry(1, 3, -newScrollOffset);
      } else {
        widget.controller.jumpTo(newScrollOffset);
      }
    }

    _maybeTriggerHaptics();
  }

  void _onDragEnd(DragEndDetails? details) {
    // details null if drag was cancelled
    setState(() {
      _isDragging = false;
    });
    _showThumbTemporarily();
  }

  int _getCurrentPage() {
    if ((!_usesCanvas && !widget.controller.hasClients) || _ratios.isEmpty) {
      return 0;
    }

    final offset = _scrollOffset;

    final total = _ratios.fold<double>(0.0, (a, b) => a + b);
    final cumulative = <double>[];
    double sum = 0.0;
    for (var ratio in _ratios) {
      sum += ratio;
      cumulative.add(sum);
    }

    final scrolledFraction = _maxScroll == 0 ? 0 : offset / _maxScroll;
    final scrollPosition = total * scrolledFraction;

    for (int i = 0; i < cumulative.length; i++) {
      if (scrollPosition < cumulative[i]) {
        return i;
      }
    }

    return _ratios.length - 1;
  }

  bool _atTopOrBottom = true;
  static const double _edgeHapticRearmDistance = 24;
  void _maybeTriggerHaptics() {
    final page = _getCurrentPage();
    if (!widget.noTumb && _isDragging && page != _lastPage) {
      HapticFeedback.selectionClick();
      _lastPage = page;
    }

    final atTopOrBottom = _scrollOffset <= 0 || _scrollOffset >= _maxScroll;
    if (atTopOrBottom) {
      if (!_atTopOrBottom) {
        if (_isDragging) {
          HapticFeedback.lightImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }
      _atTopOrBottom = true;
    } else if (_scrollOffset > _edgeHapticRearmDistance &&
        _scrollOffset < _maxScroll - _edgeHapticRearmDistance) {
      _atTopOrBottom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        widget.backgroundColor ??
        Theme.of(context).colorScheme.secondaryContainer;
    final textColor =
        widget.textColor ?? Theme.of(context).colorScheme.onSecondaryContainer;

    final railWidth = 12.0;
    final railColor = Theme.of(context).colorScheme.onPrimaryContainer;

    _setRatios();

    return LayoutBuilder(
      builder: (_, constraints) {
        _viewportHeight = constraints.maxHeight;
        _setMaxScroll();
        return Stack(
          children: [
            widget.child,
            if (_isThumbVisible && _hasScrollableContent)
              Positioned(
                right: -railWidth / 2,
                top:
                    constraints.maxHeight * widget.scrollRangeStart +
                    railWidth / 2,
                bottom:
                    constraints.maxHeight * (1.0 - widget.scrollRangeEnd) +
                    railWidth / 2,
                child: SlideTransition(
                  position: _railSlideAnimation,
                  child: Container(
                    width: railWidth,
                    decoration: BoxDecoration(
                      color: railColor,
                      borderRadius: BorderRadius.circular(railWidth / 2),
                      boxShadow: [tinyBoxShadow(context)],
                    ),
                  ),
                ),
              ),
            // Thumb
            if (_isThumbVisible && _hasScrollableContent)
              Positioned(
                right: -16,
                top: _thumbTop.clamp(
                  constraints.maxHeight * widget.scrollRangeStart,
                  constraints.maxHeight * widget.scrollRangeEnd - _thumbSize,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: GestureDetector(
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: (d) =>
                        _onDragUpdate(d, constraints.maxHeight),
                    onVerticalDragEnd: (details) => _onDragEnd(details),
                    onVerticalDragCancel: () => _onDragEnd(null),
                    // Thumb Design
                    child: Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [tinyBoxShadow(context)],
                          ),
                          child: Text(
                            "${_getCurrentPage() + 1}/${_ratios.length}",
                            style: TextStyle(fontSize: 12, color: textColor),
                          ),
                        ),
                        Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            shape: BoxShape.circle,
                            boxShadow: [tinyBoxShadow(context)],
                          ),
                          child: Icon(Icons.drag_indicator, color: textColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
