import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app/app_globals.dart';
import 'cyclic_double_tap_zoom.dart';

class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.path,
    this.interactive = false,
    this.backgroundColor = Colors.transparent,
    this.cacheRevision,
    this.externalRenderScale = 1,
  });

  final String path;
  final bool interactive;
  final Color backgroundColor;
  final Object? cacheRevision;
  final double externalRenderScale;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  double? _baseZoom;

  @override
  void didUpdateWidget(covariant PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheRevision != widget.cacheRevision) {
      _baseZoom = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.path);
    final revision = file.existsSync()
        ? "${file.lastModifiedSync().microsecondsSinceEpoch}-${file.lengthSync()}"
        : "missing";
    final effectiveRevision = widget.cacheRevision ?? revision;
    final renderScale = _quantizedRenderScale(widget.externalRenderScale);
    return IgnorePointer(
      key: ValueKey("pdf-page-pointer-${widget.path}"),
      ignoring: !widget.interactive,
      child: PdfViewer(
        PdfDocumentRefFile(
          widget.path,
          key: PdfDocumentRefKey(widget.path, [effectiveRevision]),
          useProgressiveLoading: false,
        ),
        key: ValueKey("${widget.path}-$effectiveRevision"),
        params: PdfViewerParams(
          margin: 0,
          backgroundColor: widget.backgroundColor,
          pageDropShadow: const BoxShadow(color: Colors.transparent),
          getPageRenderingScale: (context, page, controller, estimatedScale) {
            final requestedScale = estimatedScale * renderScale;
            final maximumScale =
                AppGlobals.maxPhotoSize / math.max(page.width, page.height);
            return math.min(requestedScale, maximumScale);
          },
          panEnabled: widget.interactive,
          scaleEnabled: widget.interactive,
          enableKeyboardNavigation: widget.interactive,
          onGeneralTap: widget.interactive
              ? (context, controller, details) {
                  if (details.type != PdfViewerGeneralTapType.doubleTap ||
                      !controller.isReady) {
                    return false;
                  }
                  _baseZoom ??= controller.currentZoom;
                  final targetZoom = nextDoubleTapZoom(
                    currentZoom: controller.currentZoom,
                    baseZoom: _baseZoom!,
                    maxZoom: controller.maxScale,
                  );
                  controller.zoomOnLocalPosition(
                    localPosition: details.localPosition,
                    newZoom: targetZoom,
                  );
                  return true;
                }
              : null,
          scrollPhysics: widget.interactive
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
        ),
      ),
    );
  }

  double _quantizedRenderScale(double scale) {
    if (scale <= 1) return 1;
    if (scale <= 2) return 2;
    if (scale <= 4) return 4;
    return 8;
  }
}
