import 'dart:math' as math;

double nextDoubleTapZoom({
  required double currentZoom,
  required double baseZoom,
  required double maxZoom,
}) {
  final firstZoom = math.min(baseZoom * 2, maxZoom);
  if (currentZoom <= baseZoom + 0.01) return firstZoom;
  if (currentZoom <= firstZoom + 0.01 && maxZoom > firstZoom + 0.01) {
    return maxZoom;
  }
  return baseZoom;
}
