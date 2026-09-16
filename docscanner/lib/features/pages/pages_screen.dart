import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'
    show MasonryGridView;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_globals.dart';
import '../../app/app_navigation.dart';
import '../../app/filter_names.dart';
import '../../app/global_notifier.dart';
import '../../app/image_prosessing_manager.dart';
import '../../app/metadata_helper.dart';
import '../../widgets/app_shadows.dart';
import '../../widgets/custom_expanding_button.dart';
import '../../widgets/custom_scrollbar.dart';
import '../../widgets/icon_badges.dart';
import '../../widgets/indicator_processing_image.dart';
import '../pro/pro_purchase.dart';
import 'pages_popup.dart';

class Pages extends StatefulWidget {
  const Pages({super.key, required this.docIndex, this.initialPageIndex});

  final int docIndex;
  final int? initialPageIndex;

  @override
  State<Pages> createState() => _PagesState();
}

class _PagesState extends State<Pages>
    with RouteAware, SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  List<String> _pageThumbnails = [];
  List<String> _fullSizedPages = [];
  List<double> _thumbnailRatios = [];
  int _pagesCount = 0;
  int _displayPagesCount = 0;
  int _thumbnailLoadGeneration = 0;
  int _fullSizeLoadGeneration = 0;
  int? _lastFullSizeLoadCenter;
  Timer? _fullSizeLoadTimer;
  final TransformationController _zoomTransformationController =
      TransformationController();
  double? _zoomCanvasWidth;
  double _pagesCanvasViewportHeight = 0;
  double _zoomCanvasScale = 1;
  bool _normalizingZoomTransform = false;
  final GlobalKey _pagesCanvasKey = GlobalKey();
  Offset? _lastDoubleTapPosition;
  late final AnimationController _canvasTransitionController;
  late Animation<Matrix4> _canvasTransitionAnimation;

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
    _eventSubscription = globalNotifier.stream.listen(_handleGlobalEvent);
    _loadPagesThumbnails(onInit: true, supressWarnings: true);
    _initPushToPreview();
    _initAsync();
    _loadGridView();
    _scrollController.addListener(_scheduleFullSizeLoad);
    _zoomTransformationController.addListener(_keepZoomCanvasCentered);
    _canvasTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _canvasTransitionAnimation = AlwaysStoppedAnimation(Matrix4.identity());
    _canvasTransitionController.addListener(() {
      _zoomTransformationController.value = _canvasTransitionAnimation.value;
    });
  }

  bool selectAllButtonUsed = true;
  String? _docName;
  Future<void> _initAsync() async {
    // Set Title to Doc Name
    _docName = await g.metadataHelper.readDocName(widget.docIndex);
    _checkEditHints();
    _checkSelectAllButtonUsed();
  }

  Future<void> _checkEditHints() async {
    await _enableEditHintsAfterWeek();
    _disableEditHintsAfterShownSomeTimes();
  }

  Future<void> _checkSelectAllButtonUsed() async {
    final prefs = await SharedPreferences.getInstance();
    selectAllButtonUsed = prefs.getBool("selectAllButtonUsed") ?? false;
    // Reset if long ago
    if (selectAllButtonUsed) {
      final String? dateString = prefs.getString("selectAllButtonUsedDate");
      if (dateString != null) {
        final now = DateTime.now();
        final date = DateTime.tryParse(dateString);
        if (date != null && now.difference(date).inDays > 45) {
          dev.log("_getSelectAllButtonUsed: reset to CustomExpandingButton");
          _setSelectAllButtonUsed(false);
        }
      }
    }
  }

  @override
  void dispose() {
    imageProcessingManager.deleteNonEssentialVersionsOfDocument(
      widget.docIndex,
    );
    _eventSubscription.cancel();
    _fullSizeLoadTimer?.cancel();
    _scrollController.removeListener(_scheduleFullSizeLoad);
    _scrollController.dispose();
    _zoomTransformationController.removeListener(_keepZoomCanvasCentered);
    _zoomTransformationController.dispose();
    _canvasTransitionController.dispose();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  List<int> _deletedPages = [];
  late final StreamSubscription<NotifierEvent> _eventSubscription;
  Future<void> _handleGlobalEvent(NotifierEvent event) async {
    if (!mounted) return;
    switch (event) {
      case NotifierEvent.loadPagesThumbnails:
        _loadPagesThumbnails();
        break;
      case NotifierEvent.imagesDeleted:
        _deletedPages = await g.filesHelper.getMarkedDeletedPages(
          widget.docIndex,
        );
        setState(() {});
        break;
      case NotifierEvent.setState:
        setState(() {});
        break;
      default:
    }
  }

  void _initPushToPreview() {
    if (widget.initialPageIndex != null) {
      Future.microtask(() {
        _openPagePreview(widget.initialPageIndex!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPopNext() {
    _loadPagesThumbnails();
  }

  Future<void> _loadPagesThumbnails({
    bool onInit = false,
    bool supressWarnings = false,
  }) async {
    final int loadGeneration = ++_thumbnailLoadGeneration;
    var thumbs = await g.filesHelper.getPagesThumbnails(widget.docIndex);
    if (!mounted || loadGeneration != _thumbnailLoadGeneration) return;
    _pagesCount = thumbs.$2;
    List<String> thumbnailPaths = thumbs.$1;
    List<double> newRatios = List.generate(_pagesCount, (_) => math.sqrt1_2);

    for (var pageIndex = 0; pageIndex < _pagesCount; pageIndex++) {
      double? ratioValue = await MetadataHelper.readPageRatioValue(
        widget.docIndex,
        pageIndex,
        supressWarnings: thumbnailPaths[pageIndex].isEmpty,
      );
      if (ratioValue != null) newRatios[pageIndex] = 1.0 / ratioValue;
    }
    _thumbnailRatios = newRatios;
    _deletedPages = await g.filesHelper.getMarkedDeletedPages(widget.docIndex);
    _loadingPages = await _loadLoadingPages(
      widget.docIndex,
      thumbnailPaths,
      supressWarnings: supressWarnings,
    );
    if (!mounted || loadGeneration != _thumbnailLoadGeneration) return;
    _displayPagesCount = _pagesCount - _deletedPages.length;

    if (_displayPagesCount <= 0) {
      if (!onInit && mounted && context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      return;
    } else {
      if (mounted) {
        setState(() {
          _pageThumbnails = thumbnailPaths;
          _fullSizedPages = List.filled(_pagesCount, "");
        });
        if (_zoomMode) {
          _lastFullSizeLoadCenter = null;
          _scheduleFullSizeLoad();
        }
      }
    }
  }

  List<bool> _loadingPages = [];
  Future<List<bool>> _loadLoadingPages(
    int docIndex,
    List<String> thumbnailPaths, {
    bool supressWarnings = false,
  }) async {
    List<bool> thumbnailsLoading = [];
    for (int pageIndex = 0; pageIndex < thumbnailPaths.length; pageIndex++) {
      bool thumbnailLoading = false;
      if (thumbnailPaths[pageIndex].isEmpty) {
        thumbnailLoading = true;
      } else {
        final oldNames = await MetadataHelper.readOldPageFileNames(
          docIndex,
          pageIndex,
          supressWarnings: true,
        );
        if (oldNames != null) {
          for (var oldName in oldNames) {
            if (oldName.isNotEmpty &&
                thumbnailPaths[pageIndex].contains(oldName)) {
              thumbnailLoading = true;
              break;
            }
          }
        }
      }
      thumbnailsLoading.add(thumbnailLoading);
    }
    return thumbnailsLoading;
  }

  Future<void> _openPagePreview(int pageIndex) async {
    Navigator.pushNamed(
      context,
      "/preview",
      arguments: {"docIndex": widget.docIndex, "pageIndex": pageIndex},
    );
  }

  Future<void> _openImagePicker(ImageSource source) async {
    List<String> photoPaths;
    ScaffoldMessengerState? messenger;
    if (g.filesHelper.pickingImage) return;
    if (source == ImageSource.camera) {
      photoPaths = await _openCamera();
    } else {
      final picked = await g.filesHelper.pickImage(context, source);
      photoPaths = picked.$1;
      messenger = picked.$2;
    }
    if (photoPaths.isEmpty) {
      messenger?.hideCurrentSnackBar();
      return;
    }

    int firstPageIndex = await _processNewPages(
      photoPaths,
      photosAlreadyInPages: false,
    );

    // Only open PagePreview for first page
    messenger?.hideCurrentSnackBar();
    _openPagePreview(firstPageIndex);
  }

  Future<int> _processNewPages(
    List<String> photoPaths, {
    required bool photosAlreadyInPages,
  }) async {
    int firstPageIndex = await g.filesHelper.reserveNewPagesInDocment(
      widget.docIndex,
      photoPaths.length,
    );
    Future.microtask(() async {
      await g.metadataHelper.writeDocUnlocked(widget.docIndex, false);
      await imageProcessingManager.processPages(
        widget.docIndex,
        firstPageIndex,
        photoPaths,
        photosAlreadyInPages,
      );
    });

    return firstPageIndex;
  }

  Future<List<String>> _openCamera() async {
    g.filesHelper.pickingImage = true;
    final result = await Navigator.pushNamed(context, "/camera");
    List<String> photoPaths = [];
    if (result is List<XFile>) {
      for (var xfile in result) {
        photoPaths.add(xfile.path);
      }
    }
    g.filesHelper.pickingImage = false;
    return photoPaths;
  }

  bool _selectMode = false;
  List<int> _selectedPages = [];
  bool _zoomMode = false;
  static const double _zoomCanvasHorizontalInset = 15;
  static const double _pinchZoomActivationThreshold = 0.08;
  static const double _frictionAtDefaultScale = 0.15;
  static const double _frictionAtMaximumScale = 0.001;
  static const double _frictionAtMinimumScale = 0.3;

  void _activateZoomFromPinch(ScaleUpdateDetails details) {
    if (_zoomMode ||
        _selectMode ||
        (details.scale - 1).abs() < _pinchZoomActivationThreshold) {
      return;
    }
    _startZoomMode();
  }

  double _interactionEndFrictionCoefficient() {
    if (!_zoomMode) return _frictionAtDefaultScale;

    final scale = _zoomTransformationController.value.getMaxScaleOnAxis();
    if (scale <= 1) {
      return _frictionAtDefaultScale +
          (1 - scale).clamp(0.0, 0.5) *
              2 *
              (_frictionAtMinimumScale - _frictionAtDefaultScale);
    }

    final maxScale = _gridView == true ? 16.0 : 8.0;
    final zoomProgress = ((scale - 1) / (maxScale - 1)).clamp(0.0, 1.0);
    return _frictionAtDefaultScale *
        math.pow(
          _frictionAtMaximumScale / _frictionAtDefaultScale,
          zoomProgress,
        );
  }

  Future<void> _startZoomMode({
    double? initialScale,
    Offset? focalPoint,
  }) async {
    if (_selectMode || _zoomMode) return;
    setState(() {
      _zoomMode = true;
      _fullSizedPages = List.filled(_pagesCount, "");
    });
    if (initialScale != null) {
      _animateCanvasToScale(initialScale, focalPoint: focalPoint);
    }
    _loadFullSizedPages(_currentDisplayPageIndex());
  }

  void _animateCanvasToScale(double targetScale, {Offset? focalPoint}) {
    final currentTransform = Matrix4.copy(_zoomTransformationController.value);
    final currentScale = currentTransform.getMaxScaleOnAxis();
    if (currentScale == targetScale) return;

    final translation = currentTransform.getTranslation();
    final zoomFocalPoint =
        focalPoint ??
        Offset((_zoomCanvasWidth ?? 0) / 2, _pagesCanvasViewportHeight / 2);
    final targetTranslation =
        zoomFocalPoint -
        (zoomFocalPoint - Offset(translation.x, translation.y)) *
            targetScale /
            currentScale;
    final targetTransform = Matrix4.identity()
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
      ..setEntry(2, 2, targetScale)
      ..setEntry(0, 3, targetTranslation.dx)
      ..setEntry(1, 3, targetTranslation.dy);
    _canvasTransitionAnimation =
        Matrix4Tween(begin: currentTransform, end: targetTransform).animate(
          CurvedAnimation(
            parent: _canvasTransitionController,
            curve: Curves.easeOutCubic,
          ),
        );
    _canvasTransitionController.forward(from: 0);
  }

  void _handleCanvasDoubleTap() {
    if (_selectMode) return;
    final scale = _zoomTransformationController.value.getMaxScaleOnAxis();
    if (!_zoomMode) {
      _startZoomMode(initialScale: 2, focalPoint: _lastDoubleTapPosition);
    } else if (scale >= 1 && scale <= 2) {
      _animateCanvasToScale(
        _gridView == true ? 16 : 8,
        focalPoint: _lastDoubleTapPosition,
      );
    } else {
      _endZoomMode();
    }
  }

  void _endZoomMode() {
    if (!_zoomMode) return;
    _canvasTransitionController.stop();
    final fullSizedPages = List<String>.from(_fullSizedPages);
    final currentTransform = Matrix4.copy(_zoomTransformationController.value);
    final canvasRenderObject = _pagesCanvasKey.currentContext
        ?.findRenderObject();
    final canvasHeight = canvasRenderObject is RenderBox
        ? canvasRenderObject.size.height
        : 0.0;
    final scale = currentTransform.getMaxScaleOnAxis();
    final viewportCenterY = _pagesCanvasViewportHeight / 2;
    final contentCenterY =
        (viewportCenterY - currentTransform.getTranslation().y) / scale;
    final normalMaxScroll = math.max(
      0.0,
      canvasHeight - _pagesCanvasViewportHeight,
    );
    final normalScroll = (contentCenterY - viewportCenterY).clamp(
      0.0,
      normalMaxScroll,
    );
    final normalTransform = Matrix4.identity()..setEntry(1, 3, -normalScroll);
    _fullSizeLoadGeneration++;
    _fullSizeLoadTimer?.cancel();
    _lastFullSizeLoadCenter = null;
    setState(() {
      _zoomMode = false;
      _fullSizedPages = List.filled(_pagesCount, "");
    });
    _canvasTransitionAnimation =
        Matrix4Tween(begin: currentTransform, end: normalTransform).animate(
          CurvedAnimation(
            parent: _canvasTransitionController,
            curve: Curves.easeOutCubic,
          ),
        );
    _canvasTransitionController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || _zoomMode) return;
      for (final path in fullSizedPages) {
        if (path.isNotEmpty) {
          imageCache.evict(FileImage(File(path)), includeLive: false);
        }
      }
    });
  }

  void _scheduleFullSizeLoad() {
    if (!_zoomMode) return;
    _fullSizeLoadTimer?.cancel();
    _fullSizeLoadTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _zoomMode) {
        _loadFullSizedPages(_currentDisplayPageIndex());
      }
    });
  }

  void _keepZoomCanvasCentered() {
    final canvasWidth = _zoomCanvasWidth;
    if (!_zoomMode || canvasWidth == null || _normalizingZoomTransform) {
      return;
    }
    final transform = _zoomTransformationController.value;
    final scale = transform.getMaxScaleOnAxis();
    if ((scale - _zoomCanvasScale).abs() > 0.001) {
      setState(() => _zoomCanvasScale = scale);
    }
    final contentWidth = canvasWidth - 2 * _zoomCanvasHorizontalInset;
    if (contentWidth <= 0 || contentWidth * scale > canvasWidth) return;

    final centeredX = canvasWidth * (1 - scale) / 2;
    if ((transform.getTranslation().x - centeredX).abs() < 0.01) return;

    _normalizingZoomTransform = true;
    _zoomTransformationController.value = Matrix4.copy(transform)
      ..setEntry(0, 3, centeredX);
    _normalizingZoomTransform = false;
  }

  int _currentDisplayPageIndex() {
    if (!_scrollController.hasClients || _displayPagesCount <= 1) return 0;
    final position = _scrollController.position;
    final fraction = position.maxScrollExtent == 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final ratios = _thumbnailRatios
        .whereIndexed((index, _) => !_deletedPages.contains(index))
        .map((ratio) => 1.0 / ratio)
        .toList();
    final target = ratios.sum * fraction;
    double cumulative = 0;
    for (var index = 0; index < ratios.length; index++) {
      cumulative += ratios[index];
      if (target < cumulative) return index;
    }
    return ratios.length - 1;
  }

  Future<void> _loadFullSizedPages(int centerDisplayIndex) async {
    if (!_zoomMode || centerDisplayIndex == _lastFullSizeLoadCenter) return;
    _lastFullSizeLoadCenter = centerDisplayIndex;
    final loadGeneration = ++_fullSizeLoadGeneration;
    final displayedPageIndexes = List<int>.generate(
      _pagesCount,
      (index) => index,
    ).where((index) => !_deletedPages.contains(index)).toList();

    for (var offset = 0; offset < displayedPageIndexes.length; offset++) {
      for (final displayIndex in [
        centerDisplayIndex + offset,
        if (offset != 0) centerDisplayIndex - offset,
      ]) {
        if (displayIndex < 0 || displayIndex >= displayedPageIndexes.length) {
          continue;
        }
        final pageIndex = displayedPageIndexes[displayIndex];
        final path = (await g.filesHelper.getPagesThumbnails(
          widget.docIndex,
          pageIndexes: [pageIndex],
          fullSized: true,
          supressWarnings: true,
        )).$1.first;
        if (!mounted ||
            !_zoomMode ||
            loadGeneration != _fullSizeLoadGeneration) {
          return;
        }
        if (path.isNotEmpty && _fullSizedPages[pageIndex] != path) {
          setState(() => _fullSizedPages[pageIndex] = path);
        }
      }
    }
  }

  String _imagePathForPage(int pageIndex, String thumbnailPath) {
    if (_zoomMode &&
        pageIndex < _fullSizedPages.length &&
        _fullSizedPages[pageIndex].isNotEmpty) {
      return _fullSizedPages[pageIndex];
    }
    return thumbnailPath;
  }

  Widget _pageImage(File imageFile) {
    return SizedBox.expand(
      child: Image.file(
        imageFile,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Material(
            color: Theme.of(context).colorScheme.surfaceBright,
            child: const Icon(Icons.broken_image),
          );
        },
      ),
    );
  }

  void _selectPage(int index) {
    if (_zoomMode) return;
    if (_selectedPages.contains(index)) {
      _selectedPages.remove(index);
    } else {
      _selectedPages.add(index);
    }
    if (_selectedPages.isEmpty) {
      _selectMode = false;
    } else {
      _selectedPages.sort();
      _selectMode = true;
    }
    Future.microtask(() {
      setState(() {});
    });
  }

  bool _hintEditPage = false;

  Future<void> _disableEditHintsAfterShownSomeTimes() async {
    if (!_hintEditPage) return;
    final prefs = await SharedPreferences.getInstance();
    final editHintsCount = prefs.getInt("editHintsCount") ?? 0;
    // if shown 4 times already -> disable
    if (editHintsCount >= 4) {
      final now = DateTime.now();
      prefs.setString("disableEdithHintsDate", now.toIso8601String());
      _hintEditPage = false;
      setState(() {});
      prefs.setInt("editHintsCount", 0);
    }
    prefs.setInt("editHintsCount", editHintsCount + 1);
  }

  Future<void> _enableEditHintsAfterWeek() async {
    if (_hintEditPage) return;
    final prefs = await SharedPreferences.getInstance();
    final String? savedDateString = prefs.getString("disableEdithHintsDate");
    // if disabled less than a week ago -> keep edit hints hidden
    if (savedDateString != null) {
      final now = DateTime.now();
      final savedDate = DateTime.tryParse(savedDateString);
      if (savedDate != null && now.difference(savedDate).inDays < 7) {
        return;
      }
    }
    // if never disabled or disabled more than a week ago -> show edit hints
    _hintEditPage = true;
    setState(() {});
  }

  Future<void> _setSelectAllButtonUsed(bool set) async {
    if (set == selectAllButtonUsed) return;
    selectAllButtonUsed = set;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("selectAllButtonUsed", set);
    if (set) {
      String now = DateTime.now().toIso8601String();
      prefs.setString("selectAllButtonUsedDate", now);
    }
  }

  bool? _gridView;
  Future<void> _loadGridView() async {
    if (_gridView != null) return;
    final prefs = await SharedPreferences.getInstance();
    _gridView = prefs.getBool("gridView") ?? false;
    setState(() {});
  }

  Future<void> _toggleGridView() async {
    if (_gridView == null) return;
    final canvasRenderObject = _pagesCanvasKey.currentContext
        ?.findRenderObject();
    final canvasHeight = canvasRenderObject is RenderBox
        ? canvasRenderObject.size.height
        : 0.0;
    final maxScroll = math.max(0.0, canvasHeight - _pagesCanvasViewportHeight);
    final scrollFraction = maxScroll == 0
        ? 0.0
        : (-_zoomTransformationController.value.getTranslation().y / maxScroll)
              .clamp(0.0, 1.0);

    _gridView = !_gridView!;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final newCanvasRenderObject = _pagesCanvasKey.currentContext
          ?.findRenderObject();
      final newCanvasHeight = newCanvasRenderObject is RenderBox
          ? newCanvasRenderObject.size.height
          : 0.0;
      final newMaxScroll = math.max(
        0.0,
        newCanvasHeight - _pagesCanvasViewportHeight,
      );
      _zoomTransformationController.value = Matrix4.identity()
        ..setEntry(1, 3, -newMaxScroll * scrollFraction);
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("gridView", _gridView!);
  }

  Future<void> _selectAll() async {
    if (_zoomMode) return;
    _setSelectAllButtonUsed(true);

    final lengthBefore = _selectedPages.length;

    _selectedPages = List.generate(
      _pageThumbnails.length,
      (int index) => index,
      growable: true,
    );
    _selectedPages.removeWhere((element) => _deletedPages.contains(element));

    if (lengthBefore != _selectedPages.length && _selectedPages.isNotEmpty) {
      HapticFeedback.lightImpact();
      _selectMode = true;
      Future.microtask(() {
        if (mounted) setState(() {});
      });
    }
  }

  void _cancelSelectMode() {
    HapticFeedback.lightImpact();
    _selectedPages.clear();
    _selectMode = false;
    Future.microtask(() {
      if (mounted) setState(() {});
    });
  }

  List<int> get _displayedPageIndexes => List<int>.generate(
    _pagesCount,
    (index) => index,
  ).where((index) => !_deletedPages.contains(index)).toList();

  Widget _zoomPage(int pageIndex) {
    final imagePath = _imagePathForPage(pageIndex, _pageThumbnails[pageIndex]);
    final isLoading =
        _loadingPages.length <= pageIndex || _loadingPages[pageIndex];
    final displayPageIndex = _displayedPageIndexes.indexOf(pageIndex) + 1;
    return AspectRatio(
      aspectRatio: _thumbnailRatios[pageIndex],
      child: Container(
        decoration: BoxDecoration(boxShadow: [bigBoxShadow(context)]),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Material(color: Theme.of(context).colorScheme.surfaceBright),
            if (imagePath.isNotEmpty) _pageImage(File(imagePath)),
            if (isLoading)
              Material(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh.withAlpha(150),
              ),
            if (imagePath.isEmpty || isLoading) IndicatorProcessingImage(),
            if (!_zoomMode) ...[
              if (_hintEditPage) _FlashHint(text: tr("pages.editHint")),
              Positioned.fill(
                child: Material(
                  color: _selectMode && _selectedPages.contains(pageIndex)
                      ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withAlpha(150)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: !_selectMode
                        ? () => _openPagePreview(pageIndex)
                        : () {
                            HapticFeedback.lightImpact();
                            _selectPage(pageIndex);
                          },
                    onLongPress: () => _selectPage(pageIndex),
                    splashColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withAlpha(150),
                    highlightColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withAlpha(150),
                  ),
                ),
              ),
              Positioned(
                top: _gridView == true ? 9 : 18,
                left: _gridView == true ? 6 : 12,
                child: GestureDetector(
                  onTap: _selectMode
                      ? () => _selectPage(pageIndex)
                      : () => _openPageEditDialog(
                          context,
                          pageIndex,
                          displayPageIndex,
                        ),
                  onLongPress: () => _selectPage(pageIndex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceBright,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [smallBoxShadow(context)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$displayPageIndex/$_displayPagesCount",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_selectMode && _selectedPages.contains(pageIndex))
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildZoomCanvas(BuildContext context) {
    final pageIndexes = _displayedPageIndexes;
    return LayoutBuilder(
      builder: (context, constraints) {
        _zoomCanvasWidth = constraints.maxWidth;
        _pagesCanvasViewportHeight = constraints.maxHeight;
        final gridColumns = [<int>[], <int>[]];
        final gridColumnHeights = [0.0, 0.0];
        final gridPageWidth =
            (constraints.maxWidth - 2 * _zoomCanvasHorizontalInset - 10) / 2;
        if (_gridView == true) {
          for (final pageIndex in pageIndexes) {
            final column = gridColumnHeights[0] <= gridColumnHeights[1] ? 0 : 1;
            gridColumns[column].add(pageIndex);
            gridColumnHeights[column] +=
                gridPageWidth / _thumbnailRatios[pageIndex] + 10;
          }
        }
        final canvas = _gridView == true
            ? Padding(
                padding: EdgeInsets.fromLTRB(
                  _zoomCanvasHorizontalInset,
                  _gridView == true ? 6 : 15,
                  _zoomCanvasHorizontalInset,
                  _gridView == true ? 36 : 15,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final column in gridColumns) ...[
                      Expanded(
                        child: Column(
                          children: [
                            for (final (index, pageIndex)
                                in column.indexed) ...[
                              _zoomPage(pageIndex),
                              if (index < column.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                      if (column != gridColumns.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(
                  _zoomCanvasHorizontalInset,
                  6,
                  _zoomCanvasHorizontalInset,
                  24,
                ),
                child: Column(
                  children: [
                    for (final pageIndex in pageIndexes) ...[
                      _zoomPage(pageIndex),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              );
        return CustomScrollbar(
          controller: _scrollController,
          pageAspectRatios: _thumbnailRatios
              .whereIndexed((index, _) => !_deletedPages.contains(index))
              .toList(),
          scrollRangeStart: 0.1,
          scrollRangeEnd: 0.675,
          transformationController: _zoomTransformationController,
          canvasKey: _pagesCanvasKey,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: (details) {
              _lastDoubleTapPosition = details.localPosition;
            },
            onDoubleTap: _handleCanvasDoubleTap,
            child: InteractiveViewer(
              transformationController: _zoomTransformationController,
              constrained: false,
              boundaryMargin: _zoomMode
                  ? EdgeInsets.symmetric(
                      horizontal:
                          constraints.maxWidth /
                          (8 * _zoomCanvasScale * _zoomCanvasScale),
                      vertical:
                          constraints.maxHeight /
                          (8 * _zoomCanvasScale * _zoomCanvasScale),
                    )
                  : EdgeInsets.zero,
              minScale: _zoomMode ? 0.5 : 1,
              maxScale: _zoomMode ? (_gridView == true ? 16 : 8) : 1,
              scaleEnabled: _zoomMode,
              interactionEndFrictionCoefficient:
                  _interactionEndFrictionCoefficient(),
              onInteractionUpdate: _activateZoomFromPinch,
              onInteractionEnd: (_) {
                if (!_zoomMode) return;
                final scale = _zoomTransformationController.value
                    .getMaxScaleOnAxis();
                if (scale < 1) {
                  final translation = _zoomTransformationController.value
                      .getTranslation();
                  _zoomTransformationController.value = Matrix4.identity()
                    ..setEntry(0, 0, scale)
                    ..setEntry(1, 1, scale)
                    ..setEntry(2, 2, scale)
                    ..setEntry(0, 3, constraints.maxWidth * (1 - scale) / 2)
                    ..setEntry(1, 3, translation.y);
                }
              },
              child: SizedBox(
                key: _pagesCanvasKey,
                width: constraints.maxWidth,
                child: canvas,
              ),
            ),
          ),
        );
      },
    );
  }

  final _scrollController = CustomScrollController();
  // Pages
  @override
  Widget build(BuildContext context) {
    //final bool isTopOfNavigationStack =
    //    ModalRoute.of(context)?.isCurrent ?? false;
    _displayPagesCount = _pagesCount - _deletedPages.length;
    return PopScope(
      canPop: !_selectMode && !_zoomMode,
      onPopInvokedWithResult: (didPop, _) async {
        if (_zoomMode) {
          _endZoomMode();
        } else if (_selectMode) {
          _cancelSelectMode();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: _zoomMode
            ? AppBar(
                title: Text(
                  _docName ??
                      tr(
                        "pages.title",
                        namedArgs: {"docIndex": "${widget.docIndex + 1}"},
                      ),
                  style: TextStyle(letterSpacing: 0.5),
                ),
                leading: IconButton(
                  onPressed: _endZoomMode,
                  icon: const Icon(Icons.close),
                  tooltip: tr("pages.zoom.close"),
                ),
              )
            : !_selectMode
            ? AppBar(
                // Title
                title: _DocNameEditor(
                  initialName: _docName,
                  emptyName: tr(
                    "pages.title",
                    namedArgs: {"docIndex": "${widget.docIndex + 1}"},
                  ),
                  docIndex: widget.docIndex,
                  onChanged: (newName) {
                    _docName = newName;
                    g.metadataHelper.writeDocName(widget.docIndex, newName);
                  },
                ),
                actions: [
                  // Grid View Toggle
                  if (_gridView != null)
                    IconButton(
                      onPressed: () => _toggleGridView(),
                      icon: _gridView!
                          ? Icon(Icons.view_agenda_sharp)
                          : Icon(Icons.dashboard_sharp),
                      tooltip: (_gridView!
                          ? tr("pages.views.listView")
                          : tr("pages.views.gridView")),
                    ),
                  // Select All Button
                  selectAllButtonUsed
                      ? IconButton(
                          onPressed: () => _selectAll(),
                          icon: Icon(Icons.select_all),
                          tooltip: tr("pages.select.selectAll"),
                        )
                      : CustomExpandingButton(
                          onPressed: () => _selectAll(),
                          icon: Icons.select_all,
                          text: tr("pages.select.selectAll"),
                          collapsedColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                ],
              )
            : AppBar(
                // Selecting
                title: Text(
                  tr(
                    "pages.select.selected",
                    namedArgs: {"selectedCount": "${_selectedPages.length}"},
                  ),
                ),
                leading: IconButton(
                  onPressed: () => _cancelSelectMode(),
                  icon: Icon(Icons.close),
                  tooltip: tr("pages.select.cancelSelection"),
                ),
                actions: [
                  IconButton(
                    onPressed: () => _selectAll(),
                    icon: Icon(Icons.select_all),
                    tooltip: tr("pages.select.selectAll"),
                  ),
                ],
              ),
        body: _zoomMode || _pageThumbnails.isNotEmpty
            ? _buildZoomCanvas(context)
            : _pageThumbnails
                  .isNotEmpty // && isTopOfNavigationStack
            // Pages
            ? CustomScrollbar(
                controller: _scrollController,
                pageAspectRatios: _thumbnailRatios
                    .whereIndexed(
                      (index, element) => !_deletedPages.contains(index),
                    )
                    .toList(),
                scrollRangeStart: 0.1,
                scrollRangeEnd: 0.675,

                child: _gridView == null
                    ? SizedBox()
                    : !_gridView!
                    ? ListView.builder(
                        padding: EdgeInsets.fromLTRB(15, 6, 15, 24),
                        controller: _scrollController,
                        scrollCacheExtent: ScrollCacheExtent.viewport(2),
                        itemCount: _displayPagesCount,
                        itemBuilder: (BuildContext context, int pageIndex) {
                          final displayPageIndex = pageIndex + 1;
                          pageIndex += _deletedPages
                              .where((e) => e <= pageIndex)
                              .length;
                          final String thumbnailPath = _imagePathForPage(
                            pageIndex,
                            _pageThumbnails[pageIndex],
                          );
                          final double thumbnailRatio =
                              _thumbnailRatios[pageIndex];
                          if (thumbnailRatio == 0.0) {
                            throw StateError("thumbnailRatio == 0.0");
                          }
                          final File pageThumbnail = File(thumbnailPath);
                          final bool isLoading =
                              _loadingPages.length <= pageIndex ||
                              _loadingPages[pageIndex];
                          return Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: AspectRatio(
                              aspectRatio: thumbnailRatio,
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: [bigBoxShadow(context)],
                                ),
                                child: Stack(
                                  fit: StackFit.passthrough,
                                  children: [
                                    // BG
                                    Material(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceBright,
                                    ),
                                    // Thumbnail
                                    if (thumbnailPath.isNotEmpty)
                                      _pageImage(pageThumbnail),
                                    // Loading Indicator
                                    if (isLoading)
                                      Positioned.fill(
                                        child: Material(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHigh
                                              .withAlpha(150),
                                        ),
                                      ),
                                    if (thumbnailPath.isEmpty || isLoading)
                                      IndicatorProcessingImage(),
                                    // Edit Page Hint
                                    if (_hintEditPage)
                                      _FlashHint(text: tr("pages.editHint")),
                                    if (!_zoomMode)
                                      Positioned.fill(
                                        child: Material(
                                          color:
                                              (_selectMode &&
                                                  _selectedPages.contains(
                                                    pageIndex,
                                                  ))
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withAlpha(150)
                                              : Colors.transparent,
                                          child: InkWell(
                                            onTap: !_selectMode
                                                ? () => _openPagePreview(
                                                    pageIndex,
                                                  )
                                                : () {
                                                    HapticFeedback.lightImpact();
                                                    _selectPage(pageIndex);
                                                  },
                                            onLongPress: () =>
                                                _selectPage(pageIndex),
                                            splashColor: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withAlpha(150),
                                            highlightColor: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withAlpha(150),
                                          ),
                                        ),
                                      ),
                                    // Page Index Indicator
                                    if (!_zoomMode)
                                      Positioned(
                                        top: 18,
                                        left: 12,
                                        child: GestureDetector(
                                          // Move Page Index Dialog
                                          onTap: _selectMode
                                              ? () => _selectPage(pageIndex)
                                              : () => _openPageEditDialog(
                                                  context,
                                                  pageIndex,
                                                  displayPageIndex,
                                                ),
                                          onLongPress: () =>
                                              _selectPage(pageIndex),
                                          child: Container(
                                            padding: EdgeInsets.fromLTRB(
                                              12,
                                              6,
                                              (_selectMode &&
                                                      _selectedPages.contains(
                                                        pageIndex,
                                                      ))
                                                  ? 6
                                                  : 12,
                                              6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surfaceBright,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                smallBoxShadow(context),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  "$displayPageIndex/$_displayPagesCount",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                SizedBox(
                                                  width:
                                                      (_selectMode &&
                                                          _selectedPages
                                                              .contains(
                                                                pageIndex,
                                                              ))
                                                      ? 8
                                                      : 0,
                                                ),
                                                (_selectMode &&
                                                        _selectedPages.contains(
                                                          pageIndex,
                                                        ))
                                                    ? Icon(
                                                        Icons.check,
                                                        size: 20,
                                                      )
                                                    : SizedBox(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    // Grid View
                    : MasonryGridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        padding: EdgeInsets.fromLTRB(15, 6, 15, 36),
                        controller: _scrollController,
                        cacheExtent: 1000,
                        itemCount: _displayPagesCount,
                        itemBuilder: (BuildContext context, int pageIndex) {
                          final displayPageIndex = pageIndex + 1;
                          pageIndex += _deletedPages
                              .where((e) => e <= pageIndex)
                              .length;
                          String thumbnailPath = _imagePathForPage(
                            pageIndex,
                            _pageThumbnails[pageIndex],
                          );
                          double thumbnailRatio = _thumbnailRatios[pageIndex];
                          if (thumbnailRatio == 0.0) {
                            throw StateError("thumbnailRatio == 0.0");
                          }
                          File pageThumbnail = File(thumbnailPath);
                          final bool isLoading =
                              _loadingPages.length <= pageIndex ||
                              _loadingPages[pageIndex];
                          return AspectRatio(
                            aspectRatio: thumbnailRatio,
                            child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [bigBoxShadow(context)],
                              ),
                              child: Stack(
                                fit: StackFit.passthrough,
                                children: [
                                  // BG
                                  Material(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceBright,
                                  ),
                                  // Thumbnail
                                  if (thumbnailPath.isNotEmpty)
                                    _pageImage(pageThumbnail),
                                  // Loading Indicator
                                  if (isLoading)
                                    Positioned.fill(
                                      child: Material(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHigh
                                            .withAlpha(150),
                                      ),
                                    ),
                                  if (thumbnailPath.isEmpty || isLoading)
                                    IndicatorProcessingImage(),
                                  // Edit Page Hint
                                  if (_hintEditPage)
                                    _FlashHint(text: tr("pages.editHint")),
                                  if (!_zoomMode)
                                    Positioned.fill(
                                      child: Material(
                                        color:
                                            (_selectMode &&
                                                _selectedPages.contains(
                                                  pageIndex,
                                                ))
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withAlpha(150)
                                            : Colors.transparent,
                                        child: InkWell(
                                          onTap: !_selectMode
                                              ? () =>
                                                    _openPagePreview(pageIndex)
                                              : () {
                                                  HapticFeedback.lightImpact();
                                                  _selectPage(pageIndex);
                                                },
                                          onLongPress: () =>
                                              _selectPage(pageIndex),
                                          splashColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withAlpha(150),
                                          highlightColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withAlpha(150),
                                        ),
                                      ),
                                    ),
                                  // Page Index Indicator
                                  if (!_zoomMode)
                                    Positioned(
                                      top: 9,
                                      left: 6,
                                      child: GestureDetector(
                                        // Move Page Index Dialog
                                        onTap: _selectMode
                                            ? () => _selectPage(pageIndex)
                                            : () => _openPageEditDialog(
                                                context,
                                                pageIndex,
                                                displayPageIndex,
                                              ),
                                        onLongPress: () =>
                                            _selectPage(pageIndex),
                                        child: Container(
                                          padding: EdgeInsets.fromLTRB(
                                            12,
                                            6,
                                            (_selectMode &&
                                                    _selectedPages.contains(
                                                      pageIndex,
                                                    ))
                                                ? 6
                                                : 12,
                                            6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surfaceBright,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            boxShadow: [
                                              smallBoxShadow(context),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                "$displayPageIndex/$_displayPagesCount",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              SizedBox(
                                                width:
                                                    (_selectMode &&
                                                        _selectedPages.contains(
                                                          pageIndex,
                                                        ))
                                                    ? 8
                                                    : 0,
                                              ),
                                              (_selectMode &&
                                                      _selectedPages.contains(
                                                        pageIndex,
                                                      ))
                                                  ? Icon(Icons.check, size: 20)
                                                  : SizedBox(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              )
            : const SizedBox(),
        // Floating Action Buttons
        floatingActionButton: _zoomMode
            ? null
            : Padding(
                padding: const EdgeInsets.all(20.0),
                child: !_selectMode
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          // Add Images
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: FloatingActionButton(
                              heroTag: "pickImagesPage",
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onPressed: () {
                                _openImagePicker(ImageSource.gallery);
                              },
                              tooltip: tr("fabs.images"),
                              child: IconWithPlusBadge(
                                icon: Icons.photo_library,
                              ),
                            ),
                          ),
                          SizedBox(height: 18.0),
                          // Add PDF
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: FloatingActionButton(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              heroTag: "pickPdfPage",
                              onPressed: () async {
                                final indexPairsList = await g.filesHelper
                                    .pickPdfToDoc(
                                      addToDocWithIndex: widget.docIndex,
                                    );
                                int pdfsCount = indexPairsList.length;
                                if (pdfsCount != 0 && context.mounted) {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final snackBar = SnackBar(
                                    content: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(tr("loading.importingPdf")),
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                          ),
                                        ),
                                      ],
                                    ),
                                    duration: const Duration(days: 1),
                                  );
                                  messenger.showSnackBar(snackBar);

                                  // Hide snackbar when page is loaded
                                  StreamSubscription<NotifierEvent>?
                                  eventSubscriptionSnackbar;
                                  hideSnackbarOnPageReload(
                                    NotifierEvent event,
                                  ) {
                                    if (event ==
                                        NotifierEvent.loadPagesThumbnails) {
                                      messenger.hideCurrentSnackBar();
                                      eventSubscriptionSnackbar?.cancel();
                                    }
                                  }

                                  eventSubscriptionSnackbar = globalNotifier
                                      .stream
                                      .listen(hideSnackbarOnPageReload);
                                }
                              },
                              tooltip: tr("fabs.pdfs"),
                              child: IconWithPlusBadge(
                                icon: Icons.picture_as_pdf,
                              ),
                            ),
                          ),
                          SizedBox(height: 18.0),
                          // Take and add Photos
                          if (_picker.supportsImageSource(ImageSource.camera))
                            FloatingActionButton(
                              heroTag: "takePhotoPage",
                              onPressed: () {
                                _openImagePicker(ImageSource.camera);
                              },
                              tooltip: tr("fabs.camera"),
                              child: const Icon(Icons.camera_alt),
                            ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: FloatingActionButton(
                              heroTag: "selectionChangeThumbnail",
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onPressed: () async {
                                //if (
                                await _changeThumbnailVersionsPopup(
                                  context,
                                  _selectedPages,
                                  widget.docIndex,
                                );
                                //) {
                                //  _cancelSelectMode();
                                //}
                              },
                              tooltip: tr("fabs.thumbnail"),
                              child: IconWithBadge(
                                icon: Icons.image,
                                badgeIcon: Icons.change_circle,
                                mainIconSize: 24,
                                iconColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                bgColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                              ),
                            ),
                          ),
                          SizedBox(height: 18.0),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: FloatingActionButton(
                              heroTag: "selectionDeletePage",
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onPressed: () async {
                                bool deletionConfirmed = await showPagesPopup(
                                  context,
                                  _selectedPages,
                                  PopUpType.delete,
                                  widget.docIndex,
                                );
                                if (deletionConfirmed) {
                                  _cancelSelectMode();
                                }
                              },
                              tooltip: tr("fabs.delete"),
                              child: const Icon(Icons.delete),
                            ),
                          ),
                          SizedBox(height: 18.0),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: FloatingActionButton(
                              heroTag: "selectionSavePage",
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onPressed: () async {
                                if (await showPagesPopup(
                                      context,
                                      _selectedPages,
                                      PopUpType.save,
                                      widget.docIndex,
                                    ) &&
                                    mounted) {
                                  _cancelSelectMode();
                                }
                              },
                              tooltip: tr("fabs.save"),
                              child: const Icon(Icons.save),
                            ),
                          ),
                          SizedBox(height: 18.0),
                          if (_picker.supportsImageSource(ImageSource.camera))
                            FloatingActionButton(
                              heroTag: "selectionSharePage",
                              onPressed: () async {
                                showPagesPopup(
                                  context,
                                  _selectedPages,
                                  PopUpType.share,
                                  widget.docIndex,
                                );
                              },
                              tooltip: tr("fabs.share"),
                              child: const Icon(Icons.share),
                            ),
                        ],
                      ),
              ),
      ),
    );
  }

  void _openPageEditDialog(
    BuildContext context,
    int pageIndex,
    displayPageIndex,
  ) async {
    bool allowChangePageIndex = false;
    Future<void> future = imageProcessingManager.awaitIsolatesOfDocument(
      widget.docIndex,
    );
    int correctedPageIndex =
        pageIndex - _deletedPages.where((e) => e < pageIndex).length;
    int? selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        int currentIndex = correctedPageIndex;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            future.whenComplete(() {
              if (!allowChangePageIndex) {
                setStateDialog(() => allowChangePageIndex = true);
                setState(() {});
              }
            });
            return AlertDialog(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 30,
                  ),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      tr(
                        'pages.pageIndex',
                        namedArgs: {'pageIndex': '$displayPageIndex'},
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Move Page to new Index - Dropdown
                  TextButton(
                    onPressed: !allowChangePageIndex
                        ? () => Fluttertoast.showToast(
                            msg: tr("loading.waitingOtherPages"),
                          )
                        : null,
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: tr("pages.popup.move"),
                      ),
                      initialValue: currentIndex,
                      isExpanded: true,
                      items: List.generate(
                        _displayPagesCount,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(
                            overflow: TextOverflow.ellipsis,
                            tr(
                              "pages.pageIndex",
                              namedArgs: {"pageIndex": "${i + 1}"},
                            ),
                          ),
                        ),
                      ),
                      onChanged: allowChangePageIndex
                          ? (int? newValue) {
                              if (newValue != null) {
                                setStateDialog(() => currentIndex = newValue);
                              }
                            }
                          : null,
                    ),
                  ),

                  SizedBox(height: 24),
                  // Reverse Order - Button
                  ElevatedButton.icon(
                    onPressed: allowChangePageIndex
                        ? () async {
                            await g.filesHelper.reversePagesOrder(
                              widget.docIndex,
                            );
                            if (context.mounted) Navigator.pop(context);
                            _loadPagesThumbnails();
                          }
                        : () => Fluttertoast.showToast(
                            msg: tr("loading.waitingPages"),
                          ),
                    label: Text(
                      tr("pages.popup.reverseOrder"),
                      style: TextStyle(
                        color: allowChangePageIndex
                            ? null
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                    icon: Icon(
                      Icons.swap_vert,
                      color: allowChangePageIndex
                          ? null
                          : Theme.of(context).disabledColor,
                    ),
                    style: ButtonStyle(
                      backgroundColor: allowChangePageIndex
                          ? null
                          : WidgetStateProperty.all(
                              Theme.of(context).disabledColor,
                            ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(tr("popup.cancel")),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, currentIndex);
                  },
                  child: Text(tr("popup.ok")),
                ),
              ],
            );
          },
        );
      },
    );

    // Handle Results after Dialog closes
    if (selectedIndex != null && selectedIndex != pageIndex) {
      await g.filesHelper.movePageIndex(
        widget.docIndex,
        correctedPageIndex,
        selectedIndex,
      );
      _loadPagesThumbnails();
    }
  }

  Future<bool> _changeThumbnailVersionsPopup(
    BuildContext context,
    List<int> pageIndexes,
    int docIndex,
  ) async {
    int? selectedIndex;
    bool allowed = true;
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void preselect() async {
              // if all have same thumbnailIndex -> selectedIndex
              int? thumbnailIndex;
              for (int pageIndex in pageIndexes) {
                final int? currentThumbnailIndex =
                    await MetadataHelper.readPageThumbnailIndex(
                      docIndex,
                      pageIndex,
                    );
                thumbnailIndex ??= currentThumbnailIndex;
                if (thumbnailIndex != currentThumbnailIndex) return;
              }
              selectedIndex = thumbnailIndex;
              if (mounted) setStateDialog(() {});
            }

            if (selectedIndex == null) preselect();

            return AlertDialog(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconWithBadge(
                    icon: Icons.image,
                    badgeIcon: Icons.change_circle,
                    mainIconSize: 30,
                    iconColor: Theme.of(context).colorScheme.onSurface,
                    bgColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                  SizedBox(width: 12),
                  Flexible(child: Text(tr("popup.changeThumbnails.title"))),
                ],
              ),
              content: RadioGroup<int>(
                groupValue: selectedIndex,
                onChanged: (int? value) {
                  if (value != null) {
                    if (!g.proUnlocked && g.proFilterIndexes.contains(value)) {
                      allowed = false;
                    } else {
                      allowed = true;
                    }
                    setStateDialog(() {
                      selectedIndex = value;
                    });
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(
                    versionNames.length - 1,
                    (index) => RadioListTile<int>(
                      title: Row(
                        children: [
                          Text(versionNames[index + 1]),
                          !g.proUnlocked &&
                                  g.proFilterIndexes.contains(index + 1)
                              ? const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.lock),
                                )
                              : const SizedBox(),
                        ],
                      ),
                      value: index + 1,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false), // Cancel
                  child: Text(tr("popup.cancel")),
                ),
                allowed
                    ? ElevatedButton(
                        onPressed: selectedIndex != null
                            ? () {
                                Navigator.pop(context, true);
                              }
                            : null,
                        child: Text(tr("popup.ok")),
                      )
                    : ElevatedButton.icon(
                        icon: Icon(Icons.lock),
                        onPressed: () async {
                          await proPopup(context);
                          setStateDialog(() {});
                        },
                        label: Text(tr("popup.unlock")),
                      ),
              ],
            );
          },
        );
      },
    );

    List<Future> changeThumbnailFutures = [];
    if (confirmed == true && allowed && selectedIndex != null) {
      for (var pageIndex in pageIndexes) {
        final bool pageUnlocked = await g.metadataHelper.readPageUnlocked(
          docIndex,
          pageIndex,
          supressWarnings: true,
        );
        changeThumbnailFutures.add(
          !_loadingPages[pageIndex]
              // set new Thumbnail
              ? imageProcessingManager.setNewThumbnail(
                  docIndex,
                  pageIndex,
                  selectedIndex!,
                  tmpPro: pageUnlocked,
                )
              // still processing -> just set thumbnailIndex
              : MetadataHelper.writePageThumbnailIndex(
                  docIndex,
                  pageIndex,
                  selectedIndex!,
                  tmpPro: pageUnlocked,
                  supressWarnings: true,
                ),
        );
      }
      if (context.mounted) {
        showChangingThumbnailsSnackbar(context, changeThumbnailFutures);
      }
      return true;
    }
    return false;
  }
}

class _FlashHint extends StatefulWidget {
  final String text;

  const _FlashHint({required this.text});

  @override
  State<_FlashHint> createState() => _FlashHintState();
}

class _FlashHintState extends State<_FlashHint>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), // fade in/out duration
    );

    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Repeat 3 cycles of fade in/out
    _controller.repeat(reverse: true);

    // Stop after ~4 seconds (2 cycles * 2s per cycle)
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.stop();
        _controller.value = 0; // reset to hidden
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: Theme.of(context).colorScheme.primaryContainer.withAlpha(150),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                widget.text,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocNameEditor extends StatefulWidget {
  final String? initialName;
  final String emptyName;
  final int docIndex;
  final ValueChanged<String?> onChanged;

  const _DocNameEditor({
    required this.initialName,
    required this.emptyName,
    required this.docIndex,
    required this.onChanged,
  });

  @override
  State<_DocNameEditor> createState() => _DocNameEditorState();
}

class _DocNameEditorState extends State<_DocNameEditor>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TextEditingController(
      text: widget.initialName ?? widget.emptyName,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Use MediaQuery via View.of(context)
    if (!mounted) return;

    final viewInsets = View.of(context).viewInsets.bottom;

    if (_lastBottomInset > 0 && viewInsets == 0 && _focusNode.hasFocus) {
      String newName = _controller.text.trim();
      if (newName.isEmpty || newName == widget.emptyName) {
        widget.onChanged(null);
        _controller.text = widget.emptyName;
      } else if (newName != widget.initialName) {
        widget.onChanged(newName);
      }
      _focusNode.unfocus();
    }

    _lastBottomInset = viewInsets;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialName != null) {
      _controller.text = widget.initialName!;
    }
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      onSubmitted: (newName) {
        newName = newName.trim();
        if (newName.isEmpty || newName == widget.emptyName) {
          widget.onChanged(null);
          _controller.text = widget.emptyName;
        } else if (newName != widget.initialName) {
          widget.onChanged(newName);
        }
        _focusNode.unfocus();
      },
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 22,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
