import 'package:docscanner/widgets/pdf_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart' show PdfViewer;

void main() {
  testWidgets('PDF pages pass pointer events to parent gestures', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PdfPageView(path: '/missing.pdf')),
    );

    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('pdf-page-pointer-/missing.pdf')),
          )
          .ignoring,
      isTrue,
    );
  });

  testWidgets('PDF viewer gestures are disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PdfPageView(path: '/missing.pdf')),
    );

    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).params.panEnabled,
      isFalse,
    );
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).params.scaleEnabled,
      isFalse,
    );
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).params.onViewerReady,
      isNotNull,
    );
  });

  test('PDF render scale follows zoom in resolution buckets', () {
    expect(pdfRenderScaleForZoom(1), 1);
    expect(pdfRenderScaleForZoom(1.5), 2);
    expect(pdfRenderScaleForZoom(3), 4);
    expect(pdfRenderScaleForZoom(5), 8);
    expect(pdfRenderScaleForZoom(9), 8);
  });

  testWidgets('cache revision creates a new PDF document reference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PdfPageView(path: '/missing.pdf', cacheRevision: 1),
      ),
    );
    final firstKey = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .documentRef
        .key;

    await tester.pumpWidget(
      const MaterialApp(
        home: PdfPageView(path: '/missing.pdf', cacheRevision: 2),
      ),
    );
    final secondKey = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .documentRef
        .key;

    expect(secondKey, isNot(firstKey));
  });
}
