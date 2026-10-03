import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

double pdfRenderScaleForZoom(double scale) {
  if (scale <= 1) return 1;
  if (scale <= 2) return 2;
  if (scale <= 4) return 4;
  var renderScale = 8.0;
  while (renderScale < scale) {
    renderScale *= 2;
  }
  return renderScale;
}

class PdfPageView extends StatelessWidget {
  const PdfPageView({
    super.key,
    required this.path,
    this.backgroundColor = Colors.transparent,
    this.cacheRevision,
    this.externalRenderScale = 1,
    this.onPageSizeChanged,
  });

  final String path;
  final Color backgroundColor;
  final Object? cacheRevision;
  final double externalRenderScale;
  final ValueChanged<Size>? onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final revision = file.existsSync()
        ? "${file.lastModifiedSync().microsecondsSinceEpoch}-${file.lengthSync()}"
        : "missing";
    final effectiveRevision = cacheRevision ?? revision;
    final renderScale = pdfRenderScaleForZoom(externalRenderScale);
    return IgnorePointer(
      key: ValueKey("pdf-page-pointer-$path"),
      child: PdfViewer(
        PdfDocumentRefFile(
          path,
          key: PdfDocumentRefKey(path, [effectiveRevision]),
          useProgressiveLoading: false,
        ),
        key: ValueKey("$path-$effectiveRevision"),
        params: PdfViewerParams(
          margin: 0,
          backgroundColor: backgroundColor,
          pageDropShadow: const BoxShadow(color: Colors.transparent),
          panEnabled: false,
          scaleEnabled: false,
          enableKeyboardNavigation: false,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          getPageRenderingScale: (context, page, controller, _) {
            final pixelRatio = MediaQuery.devicePixelRatioOf(context);
            final requestedScale =
                controller.currentZoom * renderScale * pixelRatio;
            final viewportDimension = math.max(
              controller.viewSize.width,
              controller.viewSize.height,
            );
            final maxRenderDimension =
                viewportDimension * renderScale * pixelRatio;
            return math.min(
              requestedScale,
              maxRenderDimension / math.max(page.width, page.height),
            );
          },
          onViewerReady: onPageSizeChanged == null
              ? null
              : (document, controller) {
                  if (document.pages.isNotEmpty) {
                    final page = document.pages.first;
                    onPageSizeChanged?.call(Size(page.width, page.height));
                  }
                },
        ),
      ),
    );
  }
}
