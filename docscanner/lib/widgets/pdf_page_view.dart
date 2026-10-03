import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

double pdfRenderScaleForZoom(double scale) {
  if (scale <= 1) return 1;
  if (scale <= 2) return 2;
  if (scale <= 4) return 4;
  return 8;
}

class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.path,
    this.backgroundColor = Colors.transparent,
    this.cacheRevision,
    this.externalRenderScale = 1,
    this.transformationController,
    this.onPageSizeChanged,
  });

  final String path;
  final Color backgroundColor;
  final Object? cacheRevision;
  final double externalRenderScale;
  final TransformationController? transformationController;
  final ValueChanged<Size>? onPageSizeChanged;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  PdfViewerController? _pdfController;
  Matrix4? _baseTransform;
  double? _baseRenderScale;

  @override
  void initState() {
    super.initState();
    widget.transformationController?.addListener(_applyExternalTransform);
  }

  @override
  void didUpdateWidget(covariant PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheRevision != widget.cacheRevision) {
      _pdfController = null;
      _baseTransform = null;
      _baseRenderScale = null;
    }
    if (oldWidget.transformationController != widget.transformationController) {
      oldWidget.transformationController?.removeListener(
        _applyExternalTransform,
      );
      widget.transformationController?.addListener(_applyExternalTransform);
      _applyExternalTransform();
    }
  }

  @override
  void dispose() {
    widget.transformationController?.removeListener(_applyExternalTransform);
    super.dispose();
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    _pdfController = controller;
    _baseTransform = Matrix4.copy(controller.value);
    _baseRenderScale = controller.currentZoom;
    if (document.pages.isNotEmpty) {
      final page = document.pages.first;
      widget.onPageSizeChanged?.call(Size(page.width, page.height));
    }
    _applyExternalTransform();
  }

  void _applyExternalTransform() {
    final controller = _pdfController;
    final baseTransform = _baseTransform;
    final externalTransform = widget.transformationController?.value;
    if (controller == null || baseTransform == null) return;

    final transform = externalTransform == null
        ? Matrix4.copy(baseTransform)
        : (Matrix4.copy(externalTransform)..multiply(baseTransform));
    controller.value = transform;
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.path);
    final revision = file.existsSync()
        ? "${file.lastModifiedSync().microsecondsSinceEpoch}-${file.lengthSync()}"
        : "missing";
    final effectiveRevision = widget.cacheRevision ?? revision;
    final renderScale = pdfRenderScaleForZoom(widget.externalRenderScale);
    return IgnorePointer(
      key: ValueKey("pdf-page-pointer-${widget.path}"),
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
          panEnabled: false,
          scaleEnabled: false,
          enableKeyboardNavigation: false,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          getPageRenderingScale: (context, page, controller, _) {
            final pixelRatio = MediaQuery.devicePixelRatioOf(context);
            final baseScale = _baseRenderScale ?? controller.currentZoom;
            return baseScale * renderScale * pixelRatio;
          },
          onViewerReady: _onViewerReady,
        ),
      ),
    );
  }
}
