import 'package:docscanner/widgets/pdf_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('non-interactive PDF pages pass pointer events to parents', (
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

  testWidgets('interactive PDF pages receive pointer events', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PdfPageView(path: '/missing.pdf', interactive: true),
      ),
    );

    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('pdf-page-pointer-/missing.pdf')),
          )
          .ignoring,
      isFalse,
    );
  });
}
