import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPageView extends StatelessWidget {
  const PdfPageView({
    super.key,
    required this.path,
    this.interactive = false,
    this.backgroundColor = Colors.transparent,
    this.cacheRevision,
  });

  final String path;
  final bool interactive;
  final Color backgroundColor;
  final Object? cacheRevision;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final revision = file.existsSync()
        ? "${file.lastModifiedSync().microsecondsSinceEpoch}-${file.lengthSync()}"
        : "missing";
    final effectiveRevision = cacheRevision ?? revision;
    return IgnorePointer(
      key: ValueKey("pdf-page-pointer-$path"),
      ignoring: !interactive,
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
          panEnabled: interactive,
          scaleEnabled: interactive,
          enableKeyboardNavigation: interactive,
          scrollPhysics: interactive
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
        ),
      ),
    );
  }
}
