import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_globals.dart';
import '../../app/feedback_helper.dart';
import '../../app/filter_names.dart';
import '../../app/global_notifier.dart';
import '../../app/image_prosessing_manager.dart';
import '../../app/isolates_manager.dart' show IsolatePriority;
import '../../app/metadata_helper.dart';
import '../../widgets/app_shadows.dart';
import '../../widgets/custom_icon_button.dart';
import '../../widgets/indicator_processing_image.dart';
import '../pages/pages_popup.dart';
import '../pro/ads_helper.dart';
import '../pro/pro_purchase.dart';
import '../settings/aspect_ratio_settings.dart';
import '../warp/warp_page_preview_controller.dart';
import 'painters/preview_frame_painters.dart';
import 'widgets/custom_photo_viewer.dart';
import 'widgets/no_stretch_scroll_behavior.dart';

class PagePreview extends StatefulWidget {
  const PagePreview({
    super.key,
    required this.docIndex,
    required this.pageIndex,
  });
  final int docIndex;
  final int pageIndex;

  @override
  State<PagePreview> createState() => PagePreviewState();
}

class PagePreviewState extends State<PagePreview>
    implements WarpPagePreviewController {
  // Widget
  int _selectedVersion = 0;
  int _selectedThumbnail = g.defaultIndex;
  final List<String> _versionPaths = List.generate(
    versionNames.length,
    (_) => "",
  );
  final List<bool> _versionLoading = List.generate(
    versionNames.length,
    (_) => true,
  );
  List<String> _rotatedPhotoPaths = [];
  String _photoPath = "";
  // Reprocessing Parameters
  double? _ratioValue;
  double? _guiRatioValue;
  int? _orientationIndex;
  int? _guiOrientationIndex;
  int _totalRotation = 0;
  // Corner Points
  List<List<int>>? _cornerPoints;
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  bool _hideOverlayReprocessing = false;
  bool _overlayZoomed = false;
  double? _initialPhotoScale;
  // Status
  bool _rotateBlocked = true;
  bool _metadataBlocked = true;
  // PageView
  final PageController _pageController = PageController();
  final TransformationController _previewTransformationController =
      TransformationController();
  double _currentPhotoScale = 0.0;
  bool _previewImageMultiTouch = false;
  bool _previewImageZoomed = false;
  bool _preserveTransformOnNextPageChange = false;
  int? _previewPageDragIndex;
  double _previewPageDragOffset = 0;
  // Thumbnail Bar
  final ScrollController _thumbnailScrollController = ScrollController();
  final double _thumbnailBarSize = 50;
  final double _thumbnailBarSizeSelected = 70;
  final double _thumbnailBarBoder = 3;
  final double _thumbnailBarBoderThumbnail = 5;
  final double _thumbnailBarPadding = 12;
  double _barWidth = 0.0;
  // Unlock page
  bool _pageUnlocked = false;
  // Imported PDF Mode
  bool _importedPdfMode = false;

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
    _initAsync();
  }

  Future<void> _initAsync() async {
    // Lower Page Isolates Priority
    imageProcessingManager.changePrioForIsolatesOfPage(
      widget.docIndex,
      widget.pageIndex,
      IsolatePriority.immediate,
    );
    // PDF Mode
    _importedPdfMode = await MetadataHelper.readPageImportedPdf(
      widget.docIndex,
      widget.pageIndex,
    );
    if (_importedPdfMode && mounted) setState(() {});
    // Generate the remaining filter versions (only essential ones were kept)
    if (!_importedPdfMode) {
      imageProcessingManager.generateOtherVersions(
        widget.docIndex,
        widget.pageIndex,
      );
    }
    // Images
    _pageUnlocked = await g.metadataHelper.readPageUnlocked(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: true,
    );
    await _loadOldVersionFileNames(supressWarnings: true);
    _pollImagesAndMetadata();
    if (_versionPaths.any((element) => element.isEmpty)) {
      // if processing on init
      bool showRatingPopupWhileProcessing = feedbackHelper
          .canShowProcessingPopup();
      if (showRatingPopupWhileProcessing) {
        // ignore: use_build_context_synchronously
        feedbackHelper.showRatingDialog(context);
      }
    }
  }

  Future<void> _loadOldVersionFileNames({bool supressWarnings = false}) async {
    // set _versionPaths to old names, so that polling realizes that they are old
    List<String>? oldVersionFileNames =
        await MetadataHelper.readOldPageFileNames(
          widget.docIndex,
          widget.pageIndex,
          supressWarnings: supressWarnings,
        );
    if (oldVersionFileNames == null) return;
    if (oldVersionFileNames.every((element) => element.isEmpty)) return;
    List<String> versionPaths;
    (versionPaths, _) = await g.filesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    );
    for (var (i, oldName) in oldVersionFileNames.indexed) {
      if (oldName.isNotEmpty && versionPaths[i].contains(oldName)) {
        _versionPaths[i] = versionPaths[i];
      }
    }
    _photoPath = _versionPaths.first;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _previewTransformationController.dispose();
    _thumbnailScrollController.dispose();
    _eventSubscription.cancel();
    super.dispose();
  }

  late final StreamSubscription<NotifierEvent> _eventSubscription;
  Future<void> _handleGlobalEvent(NotifierEvent event) async {
    if (!mounted) return;
    switch (event) {
      case NotifierEvent.setState:
        _pageUnlocked = await g.metadataHelper.readPageUnlocked(
          widget.docIndex,
          widget.pageIndex,
        );
        setState(() {});
        break;
      case NotifierEvent.imagesDeleted:
        if (!File(_photoPath).existsSync() && Navigator.canPop(context)) {
          _allowPop = true;
          Navigator.pop(context);
        }
        break;
      default:
    }
  }

  void _pollImagesAndMetadata() {
    _pollMetadata();
    _pollImages();
  }

  void _pollMetadata() {
    // Poll Metadtata
    _pollWhile(
      pollWhileCondition: () {
        return _ratioValue == null ||
            (!_importedPdfMode && _cornerPoints == null);
      },
      onTick: () async {
        await _loadPageMetadata(supressWarnings: true);
      },
      onComplete: () async {
        await _loadPageMetadata(supressWarnings: true);
      },
    );
  }

  int _processingIndex = 0;
  void _pollImages({Future<void>? processingFuture}) {
    // Poll Images
    final int thisProcessingIndex = _processingIndex;
    int completedCount = 0;
    bool photoWasRotated = _totalRotation != 0;
    for (int i = 0; i < _versionPaths.length; i++) {
      final String previousPath = _versionPaths[i];
      final bool waitForReplacement = processingFuture != null;
      String polledPath = "";
      _versionLoading[i] = true;
      _pollWhile(
        pollWhileCondition: () {
          return thisProcessingIndex == _processingIndex &&
              !((polledPath.isNotEmpty &&
                      _versionPaths[i].isEmpty &&
                      !polledPath.contains("_uncompressed")) ||
                  (polledPath.isNotEmpty &&
                      File(polledPath).existsSync() &&
                      (i == 0
                          ? polledPath != _photoPath && _totalRotation == 0 ||
                                !photoWasRotated
                          : !polledPath.contains("_uncompressed") &&
                                (!waitForReplacement ||
                                    polledPath != previousPath))));
        },
        onTick: () async {
          polledPath = await g.filesHelper.getVersionPath(
            widget.docIndex,
            widget.pageIndex,
            i,
            supressWarnings: true,
          );
          if (i != 0 &&
              polledPath.isNotEmpty &&
              File(polledPath).existsSync() &&
              _versionPaths[i] != polledPath) {
            _versionPaths[i] = polledPath;
            _versionLoading[i] = false;
            if (mounted) setState(() {});
          }
        },
        onComplete: () async {
          if (thisProcessingIndex != _processingIndex || !mounted) return;
          if (!mounted) return;
          if (i == 0) {
            _versionPaths[i] = _photoPath = polledPath;
            _refreshCornersOverlay(supressWarnings: true);

            if (processingFuture != null) {
              await processingFuture;
              if (thisProcessingIndex != _processingIndex || !mounted) {
                return;
              }
            }
            await _preloadRotatedPhotos(thisProcessingIndex);
            if (thisProcessingIndex != _processingIndex || !mounted) return;
          } else {
            _versionPaths[i] = polledPath;
          }
          _versionLoading[i] = false;
          if (++completedCount >= _versionPaths.length) {
            _processingIndex = 0;
          }
          if (mounted) setState(() {});
        },
      );
    }
    setState(() {
      _versionLoading;
    });
  }

  Future<void> _preloadRotatedPhotos(int processingIndex) async {
    _rotateBlocked = true;
    if (mounted) setState(() {});

    await imageProcessingManager.deleteRotatedPhotos();
    final rotatedPhotoPaths = await imageProcessingManager.rotatePhotoInTmpDir(
      _photoPath,
      widget.docIndex,
      widget.pageIndex,
    );

    while (mounted &&
        processingIndex == _processingIndex &&
        !rotatedPhotoPaths.every((path) => File(path).existsSync())) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted || processingIndex != _processingIndex) return;
    _rotatedPhotoPaths = rotatedPhotoPaths;
    _rotateBlocked = false;
    setState(() {});
  }

  void _pollWhile({
    required bool Function() pollWhileCondition,
    required FutureOr<void> Function() onTick,
    FutureOr<void> Function()? onComplete,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    do {
      await onTick();
      await Future.delayed(delay);
    } while (mounted && pollWhileCondition());
    if (onComplete != null) {
      await onComplete();
    }
  }

  Future<void> _loadPageMetadata({bool supressWarnings = false}) async {
    _selectedThumbnail =
        await MetadataHelper.readPageThumbnailIndex(
          widget.docIndex,
          widget.pageIndex,
          supressWarnings: supressWarnings,
        ) ??
        _selectedThumbnail;
    _ratioValue = await MetadataHelper.readPageRatioValue(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: supressWarnings,
    );
    _guiRatioValue = (_ratioValue ?? _guiRatioValue);
    _importedPdfMode = await MetadataHelper.readPageImportedPdf(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: supressWarnings,
    );
    if (_ratioValue != null) {
      _guiOrientationIndex = _orientationIndex = (_ratioValue! > 1.0) ? 0 : 1;
    }
    if (mounted) {
      setState(() {});
    }
    await _refreshCornersOverlay(supressWarnings: supressWarnings);
    if (mounted) {
      if ((_cornerPoints != null || _importedPdfMode) &&
          _guiRatioValue != null) {
        _hideOverlayReprocessing = false;
        _initialPhotoScale = null;
        _metadataBlocked = false;
      }
      setState(() {});
    }
  }

  Future<void> _refreshCornersOverlay({bool supressWarnings = false}) async {
    // Corners
    _cornerPoints = await MetadataHelper.readPageCornerPoints(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: supressWarnings || _importedPdfMode,
    );
    // Image pixel size
    final imageFile = File(_versionPaths[0]);
    if (_versionPaths[0].isEmpty || !imageFile.existsSync()) return;
    final ui.Image image = await decodeImageFromList(
      imageFile.readAsBytesSync(),
    );
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    if (mounted) setState(() {});
  }

  void _reprocessingSetup() async {
    _processingIndex++;
    _hideOverlayReprocessing = true;
    _metadataBlocked = true;
    _rotateBlocked = true;
    _ratioValue = null; // don't reset _new values, for uninterrupted display
    _orientationIndex = null;
    setState(() {});
  }

  void _reprocessingCleanup(Future<void> processingFuture) {
    _refreshCornersOverlay();
    _pollMetadata();
    _pollImages(processingFuture: processingFuture);
    _totalRotation = 0;
    setState(() {});
  }

  Future<void> _openWarpManuallyPage() async {
    Navigator.pushNamed(
      context,
      "/warp",
      arguments: {
        "pagePreviewController": this,
        "docIndex": widget.docIndex,
        "pageIndex": widget.pageIndex,
        "imagePath": _versionPaths.first,
        "cornerPoints": _cornerPoints,
        "rotation": _totalRotation,
      },
    );
  }

  Future<void> _popOnProFilterPopup(BuildContext context) async {
    //final bool? selectedUnlock = await
    showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock,
                color: Theme.of(context).colorScheme.onSurface,
                size: 30,
              ),
              SizedBox(width: 12),
              Flexible(child: Text(tr("pagePreview.backPopup.title"))),
            ],
          ),
          content: Text(tr("pagePreview.backPopup.text")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final bool purchased = await proPopup(context);
                if (context.mounted && purchased) {
                  Navigator.pop(context, purchased);
                }
              },
              icon: Icon(Icons.lock),
              label: Text(tr("popup.unlock")),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final bool adWatched = await unlockPageWithAd(context);
                if (adWatched) {
                  _pageUnlocked = true;
                  g.metadataHelper.writePageUnlocked(
                    widget.docIndex,
                    widget.pageIndex,
                    true,
                  );
                  if (context.mounted) {
                    setState(() {});
                    Navigator.pop(context, true);
                  }
                }
              },
              icon: Icon(Icons.play_arrow),
              label: Text(tr("popup.watchAd")),
            ),
          ],
        );
      },
    );
    // Pop after Ad watched:
    //if (selectedUnlock == true) {
    //  // PostFrameCallback necessary for allowPop to register
    //  WidgetsBinding.instance.addPostFrameCallback((_) async {
    //    if (context.mounted) Navigator.maybePop(context);
    //  });
    //}
  }

  void _scrollToThumbnail(int index) {
    final int itemCount = _versionPaths.length;
    final double itemWidth =
        (_barWidth - MediaQuery.of(context).size.width) / (itemCount - 1);
    final double targetScrollOffset = (itemWidth * index);

    _thumbnailScrollController.animateTo(
      targetScrollOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onPreviewImageScaleChanged(double displayScale, bool isZoomed) {
    if ((_currentPhotoScale - displayScale).abs() < 0.0001 &&
        _overlayZoomed == isZoomed) {
      return;
    }
    setState(() {
      _currentPhotoScale = displayScale;
      _initialPhotoScale ??= displayScale;
      _overlayZoomed = isZoomed;
    });
  }

  void _setPreviewImageMultiTouch(bool multiTouch) {
    if (_previewImageMultiTouch == multiTouch) return;
    setState(() => _previewImageMultiTouch = multiTouch);
  }

  void _setPreviewImageZoomed(bool zoomed) {
    if (_previewImageZoomed == zoomed && _overlayZoomed == zoomed) return;
    setState(() {
      _previewImageZoomed = zoomed;
      _overlayZoomed = zoomed;
    });
  }

  bool get _isPreviewTransformZoomed =>
      (_previewTransformationController.value.getMaxScaleOnAxis() - 1).abs() >
      0.01;

  void _resetPreviewTransform() {
    _previewTransformationController.value = Matrix4.identity();
    _previewImageZoomed = false;
    _overlayZoomed = false;
  }

  void _updatePreviewPageDrag(double progress) {
    if (_previewPageDragIndex == null) {
      _previewPageDragIndex = _selectedVersion;
      _previewPageDragOffset = _pageController.offset;
    }
    final viewportWidth = _pageController.position.viewportDimension;
    final targetOffset = _previewPageDragOffset + progress * viewportWidth;
    _pageController.jumpTo(
      targetOffset.clamp(0.0, _pageController.position.maxScrollExtent),
    );
  }

  void _endPreviewPageDrag(double progress, double velocity) {
    final initialIndex = _previewPageDragIndex;
    if (initialIndex == null) return;
    final direction = progress.sign.toInt();
    final shouldChange =
        direction != 0 &&
        (progress.abs() >= 0.5 || velocity.abs() > 700) &&
        initialIndex + direction >= 0 &&
        initialIndex + direction < _versionPaths.length;
    final targetIndex = shouldChange ? initialIndex + direction : initialIndex;
    if (shouldChange) {
      _resetPreviewTransform();
    }
    _pageController
        .animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          _previewPageDragIndex = null;
          if (_selectedVersion == targetIndex) return;
          if (targetIndex != 0) _selectedThumbnail = targetIndex;
          _selectedVersion = targetIndex;
          _previewImageZoomed = _isPreviewTransformZoomed;
          _overlayZoomed = _previewImageZoomed;
          setState(() {});
          _scrollToThumbnail(targetIndex);
        });
  }

  Widget _buildPreviewImage(
    int index,
    bool enableFAB0,
    bool enableVersionPaging,
  ) {
    if (_versionPaths[index].isEmpty) {
      return IndicatorProcessingImage();
    }

    final image = Image.file(
      File(_versionPaths[index]),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.broken_image, color: Theme.of(context).disabledColor),
    );
    final child = index == 0
        ? GestureDetector(
            onLongPress:
                !_importedPdfMode &&
                    !_overlayZoomed &&
                    !_hideOverlayReprocessing &&
                    enableFAB0 &&
                    !_metadataBlocked
                ? _openWarpManuallyPage
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [image, _displayCornersOverlay(context)],
            ),
          )
        : image;

    return CustomPhotoViewer(
      imagePath: _versionPaths[index],
      transformationController: _previewTransformationController,
      imageSize: index == 0 && _imagePixelWidth > 0 && _imagePixelHeight > 0
          ? Size(
              _totalRotation ~/ 90 % 2 == 0
                  ? _imagePixelWidth.toDouble()
                  : _imagePixelHeight.toDouble(),
              _totalRotation ~/ 90 % 2 == 0
                  ? _imagePixelHeight.toDouble()
                  : _imagePixelWidth.toDouble(),
            )
          : null,
      onScaleChanged: index == 0 ? _onPreviewImageScaleChanged : null,
      onMultiTouchChanged: _setPreviewImageMultiTouch,
      onZoomChanged: (zoomed) {
        if (index == _selectedVersion) _setPreviewImageZoomed(zoomed);
      },
      onPageDragUpdate: enableVersionPaging
          ? (progress) {
              if (index == _selectedVersion) {
                _updatePreviewPageDrag(progress);
              }
            }
          : null,
      onPageDragEnd: enableVersionPaging
          ? (progress, velocity) {
              if (index == _selectedVersion) {
                _endPreviewPageDrag(progress, velocity);
              }
            }
          : null,
      child: child,
    );
  }

  // Page Preview
  bool _allowPop = true;
  @override
  Widget build(BuildContext context) {
    _barWidth =
        (_thumbnailBarPadding * 2) * _versionPaths.length +
        (_thumbnailBarSize + _thumbnailBarBoder * 2) *
            (_versionPaths.length - 1) +
        (_thumbnailBarSizeSelected + _thumbnailBarBoderThumbnail * 2);
    // Flags
    bool noReprocessingChanges =
        ((_guiRatioValue == null ||
            _ratioValue == null ||
            (_ratioValue == _guiRatioValue)) &&
        (_orientationIndex == null ||
            (_orientationIndex == _guiOrientationIndex)) &&
        _totalRotation == 0);
    bool enableFAB0 =
        _versionPaths.first.isNotEmpty && !_versionLoading[_selectedVersion];
    bool enableFABs = _selectedVersion == 0
        ? (enableFAB0 && noReprocessingChanges)
        : _versionPaths[_selectedVersion].isNotEmpty &&
              !_versionLoading[_selectedVersion];
    _allowPop =
        g.proUnlocked ||
        !g.proFilterIndexes.contains(_selectedThumbnail) ||
        _pageUnlocked;

    return PopScope(
      canPop: _allowPop && noReprocessingChanges,
      onPopInvokedWithResult: (didPop, _) async {
        // Exit edit mode
        if (!noReprocessingChanges) {
          if (!_metadataBlocked) {
            _guiRatioValue = _ratioValue;
            _guiOrientationIndex = _orientationIndex;
            _totalRotation = 0;
            _versionPaths[0] = _photoPath;
            setState(() {});
          }
        }
        // Prevent pop when PRO filter is selected
        else if (!_allowPop) {
          HapticFeedback.heavyImpact();
          _popOnProFilterPopup(context);
        }
        // Regular pop
        else {
          // Lower Page Isolates Priority
          imageProcessingManager.changePrioForIsolatesOfPage(
            widget.docIndex,
            widget.pageIndex,
            IsolatePriority.regular,
          );
          // New thumbnail
          // If done processing
          if (_processingIndex == 0) {
            imageProcessingManager.setNewThumbnail(
              widget.docIndex,
              widget.pageIndex,
              _selectedThumbnail,
              tmpPro: _pageUnlocked,
            );
          }
          // While still processing
          else {
            await MetadataHelper.writePageThumbnailIndex(
              widget.docIndex,
              widget.pageIndex,
              _selectedThumbnail,
              tmpPro: _pageUnlocked,
              supressWarnings: true,
            );
            globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
          }
          //if (await g.filesHelper.getPagesCount(widget.docIndex) == 1) {
          //  navigatorKey.currentState?.popUntil((route) => route.isFirst);
          //}
          if (!didPop && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // Top Bar
        appBar: AppBar(
          leading: noReprocessingChanges
              ? null
              : IconButton(
                  tooltip: tr("popup.cancel"),
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: !_metadataBlocked
                      ? () => Navigator.maybePop(context)
                      : null,
                ),
          title: Text(
            tr(
              "pagePreview.pageIndex",
              namedArgs: {"pageIndex": "${widget.pageIndex + 1}"},
            ),
          ),
        ),
        body: Stack(
          children: [
            // Bg Shadow
            Align(
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: 1.0 / (_ratioValue ?? math.sqrt2),
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withAlpha(25),
                        blurRadius: 50,
                        spreadRadius: -20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Images (Page Versions)
            PageView.builder(
              controller: _pageController,
              physics: _previewImageMultiTouch || _previewImageZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: _importedPdfMode || !noReprocessingChanges
                  ? 1
                  : _versionPaths.length,
              itemBuilder: (context, index) => _buildPreviewImage(
                index,
                enableFAB0,
                !_importedPdfMode && noReprocessingChanges,
              ),
              onPageChanged: (index) {
                if (_previewPageDragIndex != null) return;
                final preserveTransform = _preserveTransformOnNextPageChange;
                _preserveTransformOnNextPageChange = false;
                if (!preserveTransform) {
                  _resetPreviewTransform();
                }
                if (index != 0) _selectedThumbnail = index;
                _selectedVersion = index;
                _previewImageZoomed = _isPreviewTransformZoomed;
                _overlayZoomed = _previewImageZoomed;
                setState(() {});
                _scrollToThumbnail(index);
              },
            ),
            // Reprocessing Bar
            _reprocessingBar(context, noReprocessingChanges),
          ],
        ),
        // Floating Action Buttons
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _selectedVersion == 0 && !_importedPdfMode
                ? Padding(
                    padding: EdgeInsets.only(
                      bottom: noReprocessingChanges ? 18 : 140,
                    ),
                    child: SizedBox(
                      width: noReprocessingChanges ? 40 : null,
                      height: noReprocessingChanges ? 40 : null,
                      child: FloatingActionButton(
                        heroTag: "adjustCorners",
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            noReprocessingChanges ? 12 : 16,
                          ),
                        ),
                        onPressed: enableFAB0 && !_metadataBlocked
                            ? () => _openWarpManuallyPage()
                            : null,
                        tooltip: enableFAB0 && !_metadataBlocked
                            ? tr("fabs.warp")
                            : tr("loading.waitingImage"),
                        backgroundColor: enableFAB0 && !_metadataBlocked
                            ? null
                            : Theme.of(context).disabledColor,
                        elevation: enableFAB0 && !_metadataBlocked ? null : 0.0,
                        child: Transform.scale(
                          scaleY: 0.8,
                          scaleX: 0.85,
                          filterQuality: FilterQuality.high,
                          child: Transform.translate(
                            offset: Offset(0, -1.8),
                            filterQuality: FilterQuality.high,
                            child: Transform(
                              alignment: Alignment.topCenter,
                              transform:
                                  (Matrix4.identity()..setEntry(3, 2, 0.0256)) *
                                  Matrix4.rotationX(-0.7),
                              filterQuality: FilterQuality.high,
                              child: Icon(
                                Icons.crop_free,
                                color: enableFAB0 && !_metadataBlocked
                                    ? null
                                    : Theme.of(context).disabledColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : SizedBox(),
            if (noReprocessingChanges)
              Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: FloatingActionButton(
                    heroTag: "savePageVersion",
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onPressed: enableFABs
                        ? () => showPagesPopup(
                            context,
                            [widget.pageIndex],
                            PopUpType.save,
                            widget.docIndex,
                            versionIndex: _selectedVersion,
                          )
                        : null,
                    tooltip: enableFABs
                        ? tr("fabs.save")
                        : tr("loading.waitingImage"),
                    backgroundColor: enableFABs
                        ? null
                        : Theme.of(context).disabledColor,
                    elevation: enableFABs ? null : 0.0,
                    child: Icon(
                      Icons.save,
                      color: enableFABs
                          ? null
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
              ),
            if (noReprocessingChanges)
              Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: FloatingActionButton(
                  heroTag: "sharePageVersion",
                  onPressed: enableFABs
                      ? () => showPagesPopup(
                          context,
                          [widget.pageIndex],
                          PopUpType.share,
                          widget.docIndex,
                          versionIndex: _selectedVersion,
                        )
                      : null,
                  tooltip: enableFABs
                      ? tr("fabs.share")
                      : tr("loading.waitingImage"),
                  backgroundColor: enableFABs
                      ? null
                      : Theme.of(context).disabledColor,
                  elevation: enableFABs ? null : 0.0,
                  child: Icon(
                    Icons.share,
                    color: enableFABs ? null : Theme.of(context).disabledColor,
                  ),
                ),
              ),
          ],
        ),
        // Thumbnail Bar
        bottomNavigationBar: _importedPdfMode || !noReprocessingChanges
            ? null
            : SafeArea(
                child: Container(
                  height: 120,
                  alignment: Alignment.topCenter,
                  child: ScrollConfiguration(
                    behavior: NoStretchScrollBehavior(),
                    child: ListView.builder(
                      controller: _thumbnailScrollController,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      shrinkWrap: true,
                      itemCount: _versionPaths.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            final changesPage = index != _selectedVersion;
                            _preserveTransformOnNextPageChange = changesPage;
                            if (index != 0) _selectedThumbnail = index;
                            _selectedVersion = index;
                            setState(() {});
                            _pageController.jumpToPage(index);
                          },
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        _selectedThumbnail == index
                                            ? 13.75
                                            : 11.5,
                                      ),
                                      border: Border.all(
                                        color:
                                            _selectedThumbnail == index ||
                                                _selectedVersion == index
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.secondaryFixed
                                            : Colors.white54,
                                        width: _selectedThumbnail == index
                                            ? _thumbnailBarBoderThumbnail
                                            : _thumbnailBarBoder,
                                      ),
                                      boxShadow: [bigBoxShadow(context)],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8.5),
                                      child: SizedBox(
                                        width: _selectedVersion == index
                                            ? _thumbnailBarSizeSelected
                                            : _thumbnailBarSize,
                                        height: _selectedVersion == index
                                            ? _thumbnailBarSizeSelected
                                            : _thumbnailBarSize,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            _versionPaths[index].isNotEmpty
                                                ? Image.file(
                                                    File(_versionPaths[index]),
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return Padding(
                                                            padding: EdgeInsets.all(
                                                              _thumbnailBarPadding,
                                                            ),
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image,
                                                              color: Theme.of(
                                                                context,
                                                              ).disabledColor,
                                                            ),
                                                          );
                                                        },
                                                  )
                                                : SizedBox(),
                                            if (_versionLoading[index])
                                              Container(
                                                alignment: Alignment.center,
                                                color: Theme.of(
                                                  context,
                                                ).disabledColor,
                                                child: Padding(
                                                  padding: EdgeInsets.all(
                                                    _thumbnailBarPadding,
                                                  ),
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Locked Badge
                                  (g.proUnlocked ||
                                          !g.proFilterIndexes.contains(index) ||
                                          _pageUnlocked)
                                      ? SizedBox()
                                      : Positioned(
                                          top: 0,
                                          right: 0,
                                          child: CustomIconButton(
                                            tooltip: "",
                                            onTap: null,
                                            icon: Icons.lock,
                                          ),
                                        ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                versionNames[index],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.visible,
                                ),
                                softWrap: false,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _reprocessingBar(BuildContext context, bool noReprocessingChanges) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: _selectedVersion == 0
            ? Alignment.topCenter
            : Alignment.topLeft,

        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [smallBoxShadow(context)],
          ),
          child: _selectedVersion == 0
              ? Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Row(
                    spacing: 4,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        spacing: 6,
                        children: [
                          if (_importedPdfMode) _pdfBadge(context),
                          if (!_importedPdfMode) _aspectRatioDropDown(context),
                          if (!_importedPdfMode)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: _orientationDropDown(context),
                            ),
                          _rotateButton(
                            context,
                            -90,
                            Icons.rotate_left,
                            tr("pagePreview.editBar.rotateL"),
                          ),
                          _rotateButton(
                            context,
                            90,
                            Icons.rotate_right,
                            tr("pagePreview.editBar.rotateR"),
                          ),
                        ],
                      ),
                      _confirmReProcessingButton(
                        context,
                        noReprocessingChanges,
                      ),
                    ],
                  ),
                )
              : _toEditingButton(context),
        ),
      ),
    );
  }

  CustomIconButton _toEditingButton(BuildContext context) {
    return CustomIconButton(
      tooltip: tr("pagePreview.editBar.redirect"),
      onTap: () {
        setState(() => _selectedVersion = 0);
        _pageController.jumpToPage(0);
      },
      isFlat: true,
      icon: Icons.keyboard_arrow_left,
      iconColor: Theme.of(context).colorScheme.onSurface,
      buttonColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      width: 80,
      height: 48,
      child: Icon(Icons.edit, color: Theme.of(context).colorScheme.onSurface),
    );
  }

  CustomIconButton _rotateButton(
    BuildContext context,
    int rotation,
    IconData icon,
    String tooltip,
  ) {
    return CustomIconButton(
      width: 42,
      height: 42,
      isDisabled:
          _versionPaths.first.isEmpty || _metadataBlocked || _rotateBlocked,
      onTap: () {
        _totalRotation = (_totalRotation + rotation) % 360;
        int quarterTurns = _totalRotation ~/ 90;
        _currentPhotoScale = 0.0;
        _initialPhotoScale = null;
        _guiOrientationIndex = // toggle
            ((_guiOrientationIndex ?? 0) - 1) * (-1);
        _guiRatioValue = 1.0 / _guiRatioValue!;
        if (_totalRotation == 0) {
          _versionPaths[0] = _photoPath;
        } else {
          _versionPaths[0] = _rotatedPhotoPaths[quarterTurns - 1];
        }
        setState(() {});
      },
      isFlat: true,
      //isDisabled: _rotationOngoing,
      icon: icon,
      iconColor: Theme.of(context).colorScheme.onSurface,
      buttonColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      tooltip: tooltip,
    );
  }

  Padding _confirmReProcessingButton(
    BuildContext context,
    bool noReprocessingChanges,
  ) {
    final double size = 48;
    return Padding(
      padding: EdgeInsets.all((48 - size) / 2),
      child: CustomIconButton(
        width: size,
        height: size,
        buttonColor: Theme.of(context).colorScheme.primaryContainer,
        icon: Icons.check,
        iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
        isDisabled:
            _metadataBlocked ||
            _versionPaths.isEmpty ||
            _versionPaths.first.isEmpty ||
            !File(_versionPaths.first).existsSync(),
        isHidden: noReprocessingChanges,
        tooltip: tr("pagePreview.editBar.confirm"),
        onTap: () {
          reprocessPhoto();
        },
      ),
    );
  }

  @override
  Future<void> reprocessPhoto({List<List<int>>? newCornerPointsIn}) async {
    _reprocessingSetup();

    bool onlyRotation = true;
    bool customCorners = false;

    await MetadataHelper.writePageThumbnailIndex(
      widget.docIndex,
      widget.pageIndex,
      _selectedThumbnail,
      supressWarnings: true,
    );

    // Read Matadata
    var processingMetadata = await g.metadataHelper.readPageProcessingMetadata(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: _importedPdfMode,
    );
    double? ratioValue = processingMetadata.$1;

    await imageProcessingManager.killIsolatesOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
    // Get all current paths after killing for correct polling
    final currentPaths = (await g.filesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    )).$1;
    _photoPath = currentPaths[0];
    if (_totalRotation == 0) _versionPaths[0] = _photoPath;
    _versionPaths.setRange(
      1,
      _versionPaths.length,
      (await g.filesHelper.getImagePathsForPage(
        widget.docIndex,
        widget.pageIndex,
      )).$1.getRange(1, _versionPaths.length),
    );

    // Use new / rotate old corner points
    List<List<int>>? newCornerPoints;
    if (newCornerPointsIn == null) {
      newCornerPoints = processingMetadata.$2;
      if (newCornerPoints != null) {
        newCornerPoints = rotateCornerPoints(newCornerPoints);
      }
    } else {
      newCornerPoints = List.from(newCornerPointsIn);
      onlyRotation = false;
      customCorners = true;
    }

    await MetadataHelper.writePageProcessingMetadata(
      widget.docIndex,
      widget.pageIndex,
      customCorners ? null : _guiRatioValue,
      newCornerPoints,
    );

    // Compare old and new metadata -> only rotation?
    if (onlyRotation &&
        _guiRatioValue != null &&
        ratioValue != _guiRatioValue &&
        ratioValue != 1.0 / _guiRatioValue!) {
      onlyRotation = false;
    }
    int quarterTurns = (_totalRotation ~/ 90) % 4;
    if (onlyRotation &&
            quarterTurns.isEven &&
            _orientationIndex != _guiOrientationIndex ||
        quarterTurns.isOdd && _orientationIndex == _guiOrientationIndex) {
      onlyRotation = false;
    }
    // Can't rotate if during processing, because rotatePage needas all images of the page
    // > 1, because _processingIndex is increased in _reprocessingSetup() at start of this function
    if (onlyRotation && _processingIndex > 1) {
      onlyRotation = false;
    }

    late Future<void> processingFuture;
    if (_importedPdfMode ||
        onlyRotation &&
            _versionPaths.every((path) => File(path).existsSync())) {
      if (newCornerPoints != null) {
        await MetadataHelper.writePageCornerPoints(
          widget.docIndex,
          widget.pageIndex,
          newCornerPoints,
        );
      }
      processingFuture = imageProcessingManager.rotatePage(
        widget.docIndex,
        widget.pageIndex,
        _versionPaths[0], // rotated photo
        _totalRotation,
      );
    } else {
      processingFuture = imageProcessingManager.reprocessPage(
        widget.docIndex,
        widget.pageIndex,
        _versionPaths[0], // potentially rotated photo
        customCorners ? null : _guiRatioValue,
        newCornerPoints,
        _totalRotation,
      );
    }
    _reprocessingCleanup(processingFuture);
  }

  @override
  List<List<int>> rotateCornerPoints(List<List<int>> cornerPoints) {
    if (_totalRotation == 0) return cornerPoints;
    int quarterTurns = (_totalRotation ~/ 90) % 4;

    // Apply rotation logic to each point
    List<List<int>> rotated = cornerPoints.map((p) {
      int row = p[0];
      int col = p[1];

      switch (quarterTurns) {
        case 1: // 90°
          return [col, _imagePixelHeight - row];
        case 2: // 180°
          return [_imagePixelHeight - row, _imagePixelWidth - col];
        case 3: // 270°
          return [_imagePixelWidth - col, row];
        default: // 0°
          return [row, col];
      }
    }).toList();

    // Rotate the list order to keep top-left point first
    for (var i = 0; i < quarterTurns; i++) {
      rotated = [rotated[1], rotated[3], rotated[0], rotated[2]];
    }

    return rotated;
  }

  Container _pdfBadge(BuildContext context) {
    const double height = 30;
    const double radius = 20;

    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: Tooltip(
        message: tr("pagePreview.editBar.pdf"),
        waitDuration: Duration(milliseconds: 400),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: () => _enableEditingForImportedPdfPagePopup(context),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "PDF",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enableEditingForImportedPdfPagePopup(
    BuildContext context,
  ) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
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
              Flexible(child: Text(tr("pagePreview.editBar.pdfPopup.title"))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text(tr("pagePreview.editBar.pdfPopup.text"))],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(tr("pagePreview.editBar.pdfPopup.confirm")),
            ),
          ],
        );
      },
    );

    // Handle Results after Dialog closes
    if (confirmed == true) {
      await MetadataHelper.writePageImportedPdf(
        widget.docIndex,
        widget.pageIndex,
        false,
      );
      _importedPdfMode = false;
      setState(() {});
      await MetadataHelper.writePageThumbnailIndex(
        widget.docIndex,
        widget.pageIndex,
        g.defaultIndex,
      );
      reprocessPhoto();
    }
  }

  Widget _aspectRatioDropDown(BuildContext context) {
    const double height = 30;
    int? initialIndex = g.availableAspectRatios.indexWhere(
      (element) =>
          _guiRatioValue != null &&
          (element.value == _guiRatioValue ||
              element.value == 1.0 / _guiRatioValue!),
    );
    initialIndex = initialIndex != -1 ? initialIndex : null;
    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.center,
          icon:
              SizedBox.shrink(), //Icon(Icons.arrow_drop_down, color: Colors.black),
          value: initialIndex,
          items: List.generate(
            g.availableAspectRatios.length + 1,
            (i) => DropdownMenuItem(
              alignment: Alignment.center,
              value: i,
              child: Text(
                i == g.availableAspectRatios.length
                    ? "+"
                    : g.availableAspectRatios[i].name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          onChanged: _versionPaths.first.isEmpty || _metadataBlocked
              ? null
              : (int? newValue) async {
                  if (newValue == g.availableAspectRatios.length) {
                    await selectAspectRatiosDialog(context);
                    setState(() {});
                  } else if (newValue != null && newValue != _guiRatioValue) {
                    setState(() {
                      final newPortraitValue =
                          g.availableAspectRatios[newValue].value;
                      _guiRatioValue = (_guiOrientationIndex ?? 0) == 0
                          ? newPortraitValue
                          : 1 / newPortraitValue;
                    });
                  }
                },
        ),
      ),
    );
  }

  Widget _orientationDropDown(BuildContext context) {
    const double height = 30;
    List<String> orientationsList = [
      tr("pagePreview.editBar.portrait"),
      tr("pagePreview.editBar.landscape"),
    ];
    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.center,
          icon:
              SizedBox.shrink(), //Icon((_orientation ?? 0 == 0)? Icons.crop_portrait: Icons.crop_landscape,),
          value: _guiOrientationIndex,
          items: List.generate(
            orientationsList.length,
            (i) => DropdownMenuItem(
              alignment: Alignment.center,
              value: i,
              child: Text(
                orientationsList[i],
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          onChanged: _versionPaths.first.isEmpty || _metadataBlocked
              ? null
              : (int? newValue) {
                  if (newValue != null && newValue != _guiOrientationIndex) {
                    _guiOrientationIndex = newValue;
                    if (_guiRatioValue! > 1.0 && _guiOrientationIndex != 0 ||
                        _guiRatioValue! < 1.0 && _guiOrientationIndex != 1) {
                      _guiRatioValue = 1.0 / _guiRatioValue!;
                    }
                    setState(() {});
                  }
                },
        ),
      ),
    );
  }

  Widget _displayCornersOverlay(BuildContext context) {
    if (_importedPdfMode ||
        (_cornerPoints == null || _cornerPoints!.isEmpty) ||
        _currentPhotoScale == 0.0 ||
        _hideOverlayReprocessing ||
        _overlayZoomed ||
        _imagePixelHeight == 0 ||
        _imagePixelWidth == 0) {
      return SizedBox();
    }
    int quarterTurns = _totalRotation ~/ 90;

    final double displayHeight = _imagePixelHeight * _currentPhotoScale;
    final double displayWidth = _imagePixelWidth * _currentPhotoScale;

    List<Offset> scaledPoints = _cornerPoints!
        .map(
          (point) => Offset(
            point[1] * _currentPhotoScale,
            point[0] * _currentPhotoScale,
          ),
        )
        .toList();

    return IgnorePointer(
      child: Center(
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              children: [
                /// Corners
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 6.0,
                    color: Colors.black.withAlpha(70),
                    offset: 0.1025,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 8.0,
                    color: Colors.black.withAlpha(20),
                    offset: 0.105,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 10.0,
                    color: Colors.black.withAlpha(10),
                    offset: 0.1075,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 4.0,
                    color: Theme.of(context).colorScheme.primaryFixed,
                    offset: 0.1,
                    normalizedOffset: false,
                  ),
                ),
                // Middle Sections
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 3.0,
                    color: Colors.black.withAlpha(70),
                    offset: 0.605,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 4.5,
                    color: Colors.black.withAlpha(20),
                    offset: 0.61,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 6.0,
                    color: Colors.black.withAlpha(10),
                    offset: 0.615,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 1.5,
                    color: Theme.of(context).colorScheme.primaryFixed,
                    offset: 0.6,
                    normalizedOffset: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
