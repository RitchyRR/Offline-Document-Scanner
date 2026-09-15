abstract interface class WarpPagePreviewController {
  List<List<int>> rotateCornerPoints(List<List<int>> cornerPoints);

  Future<void> reprocessPhoto({List<List<int>>? newCornerPointsIn});
}
