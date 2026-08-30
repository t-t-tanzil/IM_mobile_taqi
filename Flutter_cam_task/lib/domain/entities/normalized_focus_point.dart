import 'package:equatable/equatable.dart';

/// A tap position expressed as camera-normalized coordinates (0.0-1.0 on
/// each axis), independent of any UI widget's pixel space or the camera
/// plugin's own point type.
class NormalizedFocusPoint extends Equatable {
  const NormalizedFocusPoint({required this.x, required this.y});

  final double x;
  final double y;

  @override
  List<Object?> get props => [x, y];
}
