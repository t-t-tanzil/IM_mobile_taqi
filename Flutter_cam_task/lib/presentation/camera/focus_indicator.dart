import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Renders the focus-ring visual at a given position within an ancestor
/// Stack. Tap handling, automatic dismissal after a brief delay, and
/// wiring to an actual camera focus request live in CameraCubit.
class FocusIndicator extends StatelessWidget {
  const FocusIndicator({super.key, required this.position});

  final Offset position;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - (_size / 2),
      top: position.dy - (_size / 2),
      child: IgnorePointer(
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.blue, width: 2),
          ),
        ),
      ),
    );
  }
}
