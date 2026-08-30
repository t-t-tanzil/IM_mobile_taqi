import 'package:flutter_test/flutter_test.dart';

import 'package:camera_sync/presentation/camera/zoom_button_calculator.dart';

void main() {
  test('excludes zoom levels outside the supported range', () {
    final values = buildZoomButtonValues(minZoom: 1.0, maxZoom: 4.0);

    expect(values, [1.0, 2.0, 3.0]);
    expect(values, isNot(contains(0.5)));
  });

  test('falls back to the minimum zoom when no candidate is in range', () {
    final values = buildZoomButtonValues(minZoom: 6.0, maxZoom: 7.0);

    expect(values, [6.0]);
  });

  test('includes the full candidate set when the range covers everything', () {
    final values = buildZoomButtonValues(minZoom: 0.5, maxZoom: 10.0);

    expect(values, [0.5, 1.0, 2.0, 3.0, 5.0]);
  });
}
