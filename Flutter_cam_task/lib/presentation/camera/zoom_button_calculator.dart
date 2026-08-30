const _candidateZoomLevels = [0.5, 1.0, 2.0, 3.0, 5.0];

/// Builds the "quick select" zoom buttons from the camera's actual
/// supported range, so a device that only supports e.g. 1.0-4.0 never shows
/// an unsupported 0.5x button. Falls back to the minimum supported zoom if
/// none of the standard candidates fall within range.
List<double> buildZoomButtonValues({required double minZoom, required double maxZoom}) {
  final values = _candidateZoomLevels
      .where((zoom) => zoom >= minZoom && zoom <= maxZoom)
      .toList();
  return values.isEmpty ? [minZoom] : values;
}
