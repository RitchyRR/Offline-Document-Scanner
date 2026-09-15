import 'dart:developer' as dev;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:docscanner/ffi/opencv_bindings.dart' as cvb;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../widgets/custom_icon_button.dart';
import '../preview/widgets/custom_photo_viewer.dart';
import 'painters/crosshair_painter.dart';
import 'widgets/thumbnail_with_badge.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isFlashOn = false;
  final List<XFile> _capturedImages = [];
  double _cameraAspectRatio = 3 / 4;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

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
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _permissionStatus = await Permission.camera.request();

    if (_permissionStatus.isGranted) {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();

      final size = _controller!.value.previewSize!;
      _cameraAspectRatio = size.height / size.width;

      if (mounted) setState(() {});
    } else if (_permissionStatus.isPermanentlyDenied) {
      await showSettingsRedirectDialog();
    }
  }

  Future<void> showSettingsRedirectDialog() async {
    final bool? settingsOpened = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            SizedBox(width: 12),
            Flexible(child: Text(tr("camera.permissionsPopup.title"))),
          ],
        ),
        content: Text(tr("camera.permissionsPopup.text")),
        actions: [
          TextButton(
            child: Text(tr("popup.cancel")),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context, false);
              }
            },
          ),
          ElevatedButton(
            child: Text(tr("camera.permissionsPopup.openSettings")),
            onPressed: () {
              openAppSettings();
              if (Navigator.canPop(context)) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
    if (settingsOpened != true &&
        mounted &&
        context.mounted &&
        Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() async {
    super.dispose();
    await _controller?.setFlashMode(FlashMode.off);
    _controller?.dispose();
    _controller = null;
  }

  Future<void> _toggleFlash() async {
    _isFlashOn = !_isFlashOn;
    await _controller?.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
    if (mounted && context.mounted) setState(() {});
  }

  Future<void> _setFlash(bool setFlash) async {
    _isFlashOn = setFlash;
    await _controller?.setFlashMode(setFlash ? FlashMode.torch : FlashMode.off);
    if (mounted && context.mounted) setState(() {});
  }

  bool _cameraFlash = false;
  bool _isPressingFlashButton = false;
  bool _isPressingGalleryButton = false;
  Future<void> _takePhoto() async {
    if (_permissionStatus != PermissionStatus.granted) {
      if (mounted) _initializeCamera();
    }

    if (_controller == null || _controller!.value.isTakingPicture) {
      return;
    }
    bool previewPaused = false;
    try {
      setState(() {
        _cameraFlash = true;
      });
      final XFile xFile = await _controller!.takePicture();
      await _controller!.pausePreview();
      previewPaused = true;
      // Scale down if too large
      final cvb.ImageProcessor imageProcessor = cvb.ImageProcessor();
      imageProcessor.scaleImageToMaxSize(xFile.path, xFile.path);
      imageProcessor.dispose();
      _capturedImages.add(xFile);
      if (previewPaused) {
        await _controller!.resumePreview();
      }
      setState(() {
        _cameraFlash = false;
      });
    } catch (e) {
      if (previewPaused) {
        try {
          await _controller?.resumePreview();
        } catch (resumeError) {
          dev.log("Warning resuming camera preview: $resumeError");
        }
      }
      if (mounted) {
        setState(() {
          _cameraFlash = false;
        });
      }
      dev.log("Warning taking photo: $e");
    }
  }

  void _openPhotosGrid(BuildContext context) {
    _setFlash(false);
    final Set<int> selectedIndices = <int>{};
    bool selectionMode = false;
    showModalBottomSheet(
      backgroundColor: ColorScheme.dark().surface,
      showDragHandle: true,
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final bool hasSelection = selectedIndices.isNotEmpty;
          return PopScope(
            canPop: !selectionMode,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && selectionMode) {
                selectedIndices.clear();
                setStateDialog(() {
                  selectionMode = false;
                });
              }
            },
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: GridView.builder(
                  scrollCacheExtent: ScrollCacheExtent.viewport(2),
                  addRepaintBoundaries: false,
                  itemCount: _capturedImages.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemBuilder: (context, index) {
                    final bool isSelected = selectedIndices.contains(index);
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.file(
                            File(_capturedImages[index].path),
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (isSelected)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.black38,
                              child: Center(
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor: Colors.white30,
                              highlightColor: Colors.white10,
                              onTap: () {
                                if (!selectionMode) {
                                  _openFullscreenViewer(
                                    index,
                                    setStateDialog,
                                    () => Navigator.pop(context),
                                  );
                                  return;
                                }
                                setStateDialog(() {
                                  if (isSelected) {
                                    selectedIndices.remove(index);
                                    if (selectedIndices.isEmpty) {
                                      selectionMode = false;
                                    }
                                  } else {
                                    selectedIndices.add(index);
                                  }
                                });
                              },
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                setStateDialog(() {
                                  selectionMode = true;
                                  selectedIndices.add(index);
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              floatingActionButton: selectionMode && hasSelection
                  ? FloatingActionButton(
                      heroTag: "deleteSelectedCameraPhotos",
                      tooltip: tr("camera.viewer.deleteSelected"),
                      onPressed: () => _confirmDeleteSelectedPhotos(
                        context,
                        selectedIndices,
                        setStateDialog,
                      ),
                      child: const Icon(Icons.delete),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteSelectedPhotos(
    BuildContext context,
    Set<int> selectedIndices,
    StateSetter setStateDialog,
  ) async {
    final int selectedCount = selectedIndices.length;
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(tr("camera.viewer.deleteSelectedPopup.title")),
            ),
          ],
        ),
        content: Text(
          tr(
            "camera.viewer.deleteSelectedPopup.text",
            namedArgs: {"count": "$selectedCount"},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr("popup.cancel")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tr("camera.viewer.deleteSelectedPopup.delete"),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    final indicesToDelete = selectedIndices.toList()..sort((a, b) => b - a);
    setState(() {
      for (final index in indicesToDelete) {
        if (index < _capturedImages.length) {
          _capturedImages.removeAt(index);
        }
      }
    });
    selectedIndices.clear();
    setStateDialog(() {});
    if (_capturedImages.isEmpty && context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<bool> _leaveConfirmationDialog() async {
    bool? confirmLeave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.onSurface,
                size: 30,
              ),
              SizedBox(width: 12),
              Flexible(child: Text(tr("camera.discardPopup.title"))),
            ],
          ),
          content: Text(tr("camera.discardPopup.text")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                tr("camera.discardPopup.discard"),
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    return confirmLeave == true;
  }

  bool _isPressingCaptureButton = false;
  @override
  Widget build(BuildContext context) {
    bool allowPop = _capturedImages.isEmpty;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!allowPop) {
          HapticFeedback.heavyImpact();
          if (await _leaveConfirmationDialog() &&
              mounted &&
              context.mounted &&
              Navigator.canPop(context)) {
            allowPop = true;
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            tooltip: tr("camera.close"),
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            CustomIconButton(
              tooltip: tr("camera.confirm"),
              isDisabled: _capturedImages.isEmpty,
              onTap: () {
                allowPop = true;
                if (Navigator.canPop(context)) {
                  List<String> photoPaths = [];
                  for (var xFile in _capturedImages) {
                    photoPaths.add(xFile.path);
                  }
                  Navigator.pop(context, photoPaths);
                }
              },
              icon: Icons.check,
            ),
            SizedBox(width: 12),
          ],
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Camera Preview
            AspectRatio(
              aspectRatio: _cameraAspectRatio,
              child: Stack(
                children: [
                  _controller != null
                      ? CameraPreview(_controller!)
                      : Positioned.fill(
                          child: Container(
                            color: ColorScheme.dark().surface,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                  Stack(
                    children: [
                      _cameraFlash
                          ? Positioned.fill(
                              child: Container(color: Colors.black38),
                            )
                          : SizedBox(),
                      Center(child: CustomPaint(painter: CrosshairPainter())),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Listener(
                  onPointerDown: (_) {
                    setState(() {
                      _isPressingFlashButton = true;
                    });
                  },
                  onPointerUp: (_) {
                    setState(() {
                      _isPressingFlashButton = false;
                    });
                  },
                  onPointerCancel: (_) {
                    setState(() {
                      _isPressingFlashButton = false;
                    });
                  },
                  child: Center(
                    child: AnimatedScale(
                      scale: _isPressingFlashButton ? 1.18 : 1,
                      duration: const Duration(milliseconds: 60),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        width: 55,
                        height: 55,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: IconButton(
                          tooltip: _isFlashOn
                              ? tr("camera.flash.disable")
                              : tr("camera.flash.enable"),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _toggleFlash();
                          },
                          icon: Icon(
                            _isFlashOn ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Listener(
                  onPointerDown: (_) {
                    if (_cameraFlash) return;
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _isPressingCaptureButton = true;
                    });
                  },
                  onPointerUp: (_) {
                    setState(() {
                      _isPressingCaptureButton = false;
                    });
                  },
                  onPointerCancel: (_) {
                    setState(() {
                      _isPressingCaptureButton = false;
                    });
                  },
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 60),
                          curve: Curves.easeOutCubic,
                          width: _isPressingCaptureButton || _cameraFlash
                              ? 80
                              : 60,
                          height: _isPressingCaptureButton || _cameraFlash
                              ? 80
                              : 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isPressingCaptureButton || _cameraFlash
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.white,
                          ),
                          child: IconButton(
                            onPressed: _cameraFlash
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    _takePhoto();
                                  },
                            icon: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Listener(
                  onPointerDown: _capturedImages.isEmpty
                      ? null
                      : (_) {
                          setState(() {
                            _isPressingGalleryButton = true;
                          });
                        },
                  onPointerUp: _capturedImages.isEmpty
                      ? null
                      : (_) {
                          setState(() {
                            _isPressingGalleryButton = false;
                          });
                        },
                  onPointerCancel: _capturedImages.isEmpty
                      ? null
                      : (_) {
                          setState(() {
                            _isPressingGalleryButton = false;
                          });
                        },
                  child: Center(
                    child: Tooltip(
                      message: tr("camera.viewer.preview"),
                      child: AnimatedScale(
                        scale: _isPressingGalleryButton ? 1.18 : 1,
                        duration: const Duration(milliseconds: 60),
                        curve: Curves.easeOutCubic,
                        child: ThumbnailWithBadge(
                          image: _capturedImages.isNotEmpty
                              ? _capturedImages.first
                              : null,
                          count: _capturedImages.length,
                          onTap: _capturedImages.isEmpty
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  _openPhotosGrid(context);
                                },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _openFullscreenViewer(
    int initialIndex,
    Function(void Function()) setStateGallery,
    VoidCallback closeGallery,
  ) async {
    PageController controller = PageController(initialPage: initialIndex);
    int galleryIndex = initialIndex;
    bool galleryImageZoomed = false;
    bool galleryImageMultiTouch = false;

    await showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.black,
                leading: IconButton(
                  tooltip: tr("camera.viewer.back"),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    tooltip: tr("camera.viewer.delete"),
                    icon: Icon(Icons.delete, color: Colors.white),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _confirmDeletePhoto(
                        context,
                        controller,
                        setStateDialog,
                        setStateGallery,
                        closeGallery,
                      );
                    },
                  ),
                ],
              ),
              body: PageView.builder(
                controller: controller,
                physics: galleryImageZoomed || galleryImageMultiTouch
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: _capturedImages.length,
                onPageChanged: (index) {
                  galleryIndex = index;
                  galleryImageZoomed = false;
                  setStateDialog(() {});
                },
                itemBuilder: (context, index) => CustomPhotoViewer(
                  imagePath: _capturedImages[index].path,
                  onZoomChanged: (zoomed) {
                    if (index != galleryIndex) return;
                    if (galleryImageZoomed == zoomed) return;
                    setStateDialog(() => galleryImageZoomed = zoomed);
                  },
                  onMultiTouchChanged: (multiTouch) {
                    if (index != galleryIndex) return;
                    if (galleryImageMultiTouch == multiTouch) return;
                    setStateDialog(() => galleryImageMultiTouch = multiTouch);
                  },
                  child: Image.file(
                    File(_capturedImages[index].path),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              //floatingActionButton: Padding(
              //  padding: const EdgeInsets.fromLTRB(0, 0, 20, 100),
              //  child: Column(
              //    mainAxisAlignment: MainAxisAlignment.end,
              //    children: <Widget>[
              //      FloatingActionButton(
              //        heroTag: "deletePhoto",
              //        tooltip: "Delete Photo",
              //        onPressed: () {
              //          HapticFeedback.lightImpact();
              //          int index = controller.page!.round();
              //          setState(() {
              //            _capturedImages.removeAt(index);
              //          });
              //          setStateGallery(() {});
              //          if (_capturedImages.isEmpty) {
              //            Navigator.pop(context);
              //          } else {
              //            setStateDialog(() {});
              //          }
              //        },
              //        child: const Icon(Icons.delete, color: Colors.white),
              //      ),
              //    ],
              //  ),
              //),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeletePhoto(
    BuildContext context,
    PageController controller,
    StateSetter setStateDialog,
    Function(void Function()) setStateGallery,
    VoidCallback closeGallery,
  ) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(tr("camera.viewer.deletePopup.title"))),
          ],
        ),
        content: Text(tr("camera.viewer.deletePopup.text")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr("popup.cancel")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tr("camera.viewer.deletePopup.delete"),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    final int index = controller.page?.round() ?? 0;
    if (index >= _capturedImages.length) return;
    setState(() {
      _capturedImages.removeAt(index);
    });
    setStateGallery(() {});
    if (_capturedImages.isEmpty) {
      Navigator.pop(context);
      closeGallery();
    } else {
      setStateDialog(() {});
    }
  }
}
