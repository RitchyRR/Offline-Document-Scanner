import 'package:flutter/material.dart';

import '../features/camera/camera_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/pages/pages_screen.dart';
import '../features/preview/page_preview.dart';
import '../features/warp/warp.dart';
import '../features/warp/warp_page_preview_controller.dart';

Route<dynamic> generateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case "/":
      return MaterialPageRoute(builder: (_) => const DocumentsHome());
    case "/pages":
      final args = settings.arguments as Map<String, dynamic>;
      return MaterialPageRoute(
        builder: (_) => Pages(
          docIndex: args["docIndex"],
          initialPageIndex: args["initialPageIndex"],
        ),
      );
    case "/preview":
      final args = settings.arguments as Map<String, dynamic>;
      return MaterialPageRoute(
        builder: (_) => PagePreview(
          docIndex: args["docIndex"],
          pageIndex: args["pageIndex"],
        ),
      );
    case "/camera":
      return MaterialPageRoute(
        builder: (context) => Theme(
          data: Theme.of(context).copyWith(brightness: Brightness.dark),
          child: const CameraScreen(),
        ),
      );
    case "/warp":
      final args = settings.arguments as Map<String, dynamic>;
      final pagePreviewController = args["pagePreviewController"];
      final cornerPoints = args["cornerPoints"];
      if (pagePreviewController is! WarpPagePreviewController) {
        throw ArgumentError.value(
          pagePreviewController,
          "pagePreviewController",
          "A WarpPagePreviewController is required for /warp.",
        );
      }
      if (cornerPoints is! List<List<int>>) {
        throw ArgumentError.value(
          cornerPoints,
          "cornerPoints",
          "A non-null List<List<int>> is required for /warp.",
        );
      }
      return MaterialPageRoute(
        builder: (_) => Warp(
          pagePreviewController: pagePreviewController,
          docIndex: args["docIndex"] as int,
          pageIndex: args["pageIndex"] as int,
          imagePath: args["imagePath"] as String,
          cornerPoints: cornerPoints,
          rotation: args["rotation"] as int,
        ),
      );
    default:
      return MaterialPageRoute(builder: (_) => const DocumentsHome());
  }
}
