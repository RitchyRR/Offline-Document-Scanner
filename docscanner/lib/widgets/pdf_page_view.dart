import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPageView extends StatelessWidget {
  const PdfPageView({
    super.key,
    required this.path,
    this.interactive = false,
    this.backgroundColor = Colors.transparent,
  });

  final String path;
  final bool interactive;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: ValueKey("pdf-page-pointer-$path"),
      ignoring: !interactive,
      child: PdfViewer.file(
        path,
        key: ValueKey(path),
        useProgressiveLoading: false,
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
