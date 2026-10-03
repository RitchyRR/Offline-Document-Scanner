import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

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
    final renderScale = externalRenderScale.clamp(1.0, 8.0);
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
          getPageRenderingScale: (context, page, controller, estimatedScale) {
            final pixelRatio = MediaQuery.devicePixelRatioOf(context);
            final requestedScale = estimatedScale * renderScale * pixelRatio;
            final maxViewportDimension = math.max(
              controller.viewSize.width,
              controller.viewSize.height,
            );
            final maxRenderDimension =
                maxViewportDimension * renderScale * pixelRatio;
            final maximumScale =
                maxRenderDimension / math.max(page.width, page.height);
            return math.min(requestedScale, maximumScale);
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
