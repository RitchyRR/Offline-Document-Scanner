import 'package:docscanner/widgets/cyclic_double_tap_zoom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cycles from base to double, maximum, and base', () {
    expect(nextDoubleTapZoom(currentZoom: 1, baseZoom: 1, maxZoom: 5), 2);
    expect(nextDoubleTapZoom(currentZoom: 2, baseZoom: 1, maxZoom: 5), 5);
    expect(nextDoubleTapZoom(currentZoom: 5, baseZoom: 1, maxZoom: 5), 1);
  });

  test('skips duplicate zoom level when maximum is below double', () {
    expect(nextDoubleTapZoom(currentZoom: 1, baseZoom: 1, maxZoom: 1.5), 1.5);
    expect(nextDoubleTapZoom(currentZoom: 1.5, baseZoom: 1, maxZoom: 1.5), 1);
  });
}
