import 'package:camera/camera.dart' show CameraController, CameraPreview;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/service_locator.dart';
import '../../data/camera/camera_data_source.dart';
import '../../domain/entities/captured_image.dart';
import '../../domain/entities/normalized_focus_point.dart';
import '../theme/app_theme.dart';
import '../uploads/upload_cubit.dart';
import '../uploads/upload_state.dart';
import '../uploads/pending_uploads_screen.dart';
import 'camera_cubit.dart';
import 'camera_state.dart';
import 'focus_indicator.dart';

class CameraPreviewScreen extends StatelessWidget {
  const CameraPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CameraCubit>(),
      child: const _CameraPreviewView(),
    );
  }
}

class _CameraPreviewView extends StatefulWidget {
  const _CameraPreviewView();

  @override
  State<_CameraPreviewView> createState() => _CameraPreviewViewState();
}

class _CameraPreviewViewState extends State<_CameraPreviewView>
    with WidgetsBindingObserver {
  double _baseZoomLevel = 1.0;

  // This screen is always the app's root route (nothing below it in the
  // Navigator stack) - a back press here means "leave the app", so it's
  // gated behind a second press rather than popping immediately.
  DateTime? _lastBackPressTime;

  // Captured once in initState(), not looked up again in dispose(): by the
  // time dispose() runs the widget may already be deactivated, and
  // context.read() on a deactivated context throws ("Looking up a
  // deactivated widget's ancestor is unsafe").
  late final CameraCubit _cameraCubit;

  // UploadCubit is an app-wide singleton (see service_locator.dart) -
  // fetched directly from the service locator rather than through a
  // BlocProvider, since there's exactly one instance for the whole app.
  late final UploadCubit _uploadCubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraCubit = context.read<CameraCubit>();
    _uploadCubit = getIt<UploadCubit>();
    _cameraCubit.initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {
      _cameraCubit.disposeCamera();
    } else if (lifecycleState == AppLifecycleState.resumed) {
      _cameraCubit.initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraCubit.disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              BlocBuilder<CameraCubit, CameraState>(
                builder: (context, state) {
                  return switch (state.status) {
                    CameraStatus.initializing => const _LoadingView(),
                    CameraStatus.permissionDenied => _MessageView(
                      icon: Icons.camera_alt_outlined,
                      message:
                          state.errorMessage ??
                          'Camera permission is required to capture photos.',
                      actionLabel: 'Grant Permission',
                      onAction: _cameraCubit.requestPermission,
                    ),
                    CameraStatus.permissionPermanentlyDenied => _MessageView(
                      icon: Icons.camera_alt_outlined,
                      message:
                          state.errorMessage ??
                          'Camera permission was denied. Open Settings to continue.',
                      actionLabel: 'Open Settings',
                      onAction: _cameraCubit.openSettings,
                    ),
                    CameraStatus.unavailable => _MessageView(
                      icon: Icons.no_photography,
                      message:
                          state.errorMessage ??
                          'No camera is available on this device.',
                      actionLabel: 'Retry',
                      onAction: _cameraCubit.initializeCamera,
                    ),
                    CameraStatus.error => _MessageView(
                      icon: Icons.error_outline,
                      message:
                          state.errorMessage ??
                          'The camera could not be started.',
                      actionLabel: 'Retry',
                      onAction: _cameraCubit.initializeCamera,
                    ),
                    CameraStatus.ready => _buildReady(state),
                  };
                },
              ),
              Positioned(
                top: 8,
                left: 8,
                child: _GlassIconButton(
                  icon: Icons.photo_library_outlined,
                  tooltip: 'Pending Uploads',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PendingUploadsScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBackPress() {
    final now = DateTime.now();
    const exitWindow = Duration(seconds: 2);
    final lastPress = _lastBackPressTime;
    if (lastPress == null || now.difference(lastPress) > exitWindow) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: exitWindow,
          ),
        );
      return;
    }
    SystemNavigator.pop();
  }

  Future<void> _addCurrentBatchToQueue(List<CapturedImage> images) async {
    final success = await _uploadCubit.addBatchToQueue(images);
    if (success) {
      _cameraCubit.clearCurrentBatch();
    }
  }

  Widget _buildReady(CameraState state) {
    final controller = getIt<CameraDataSource>().previewController;

    if (controller == null || !controller.value.isInitialized) {
      return const _LoadingView();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _baseZoomLevel = state.zoomLevel,
              onScaleUpdate: (details) =>
                  _cameraCubit.setZoomLevel(_baseZoomLevel * details.scale),
              onTapUp: (details) {
                final dx = (details.localPosition.dx / constraints.maxWidth)
                    .clamp(0.0, 1.0);
                final dy = (details.localPosition.dy / constraints.maxHeight)
                    .clamp(0.0, 1.0);
                _cameraCubit.setFocusPoint(
                  NormalizedFocusPoint(x: dx, y: dy),
                  details.localPosition,
                );
              },
              child: _CoverCameraPreview(controller: controller),
            );
          },
        ),
        // Subtle top/bottom gradient scrims so the translucent controls stay
        // readable over a bright or busy live feed, without darkening the
        // whole preview.
        const _TopScrim(),
        const _BottomScrim(),
        if (state.focusIndicatorPosition != null)
          FocusIndicator(position: state.focusIndicatorPosition!),
        Positioned(
          top: 16,
          right: 16,
          child: _BatchCountBadge(count: state.batchImageCount),
        ),
        if (state.maxZoom > state.minZoom)
          Positioned(
            right: 8,
            top: 90,
            bottom: 200,
            child: _VerticalZoomSlider(
              value: state.zoomLevel.clamp(state.minZoom, state.maxZoom),
              min: state.minZoom,
              max: state.maxZoom,
              onChanged: _cameraCubit.setZoomLevel,
            ),
          ),
        if (state.captureErrorMessage != null)
          Positioned(
            top: 16,
            left: 64,
            right: 16,
            child: _ErrorBanner(message: state.captureErrorMessage!),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CameraControls(
            state: state,
            cubit: _cameraCubit,
            uploadCubit: _uploadCubit,
            onUploadBatch: () => _addCurrentBatchToQueue(state.batchImages),
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// Fills the available space without stretching, cropping edges as needed -
/// the standard "cover" treatment for a full-screen camera preview.
class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

/// Translucent dark scrim behind the top controls - a fixed-height
/// gradient, not a blur, so it stays cheap to render every frame.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 120,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black45, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        child: Container(
          height: 260,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small translucent circular icon button, matching the restrained control
/// treatment used across the preview overlay.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _BatchCountBadge extends StatelessWidget {
  const _BatchCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            '$count photo${count == 1 ? '' : 's'}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// The right-edge vertical zoom slider from the reference design. Wraps the
/// same [Slider] widget/callback as before, just rotated - the zoom
/// behavior itself (value, min, max, onChanged) is unchanged.
class _VerticalZoomSlider extends StatelessWidget {
  const _VerticalZoomSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: RotatedBox(
        quarterTurns: 3,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ),
    );
  }
}

class _CameraControls extends StatelessWidget {
  const _CameraControls({
    required this.state,
    required this.cubit,
    required this.uploadCubit,
    required this.onUploadBatch,
  });

  final CameraState state;
  final CameraCubit cubit;
  final UploadCubit uploadCubit;
  final VoidCallback onUploadBatch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.availableZoomLevels.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: state.availableZoomLevels
                  .map(
                    (zoom) => _ZoomButton(
                      zoom: zoom,
                      isSelected: (state.zoomLevel - zoom).abs() < 0.05,
                      onTap: () => cubit.setZoomLevel(zoom),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Balances the flip button + spacing on the right so the
              // capture button stays visually centered.
              const SizedBox(width: 64),
              _CaptureButton(
                isCapturing: state.isCapturing,
                onPressed: cubit.captureImage,
              ),
              const SizedBox(width: 16),
              _GlassIconButton(
                icon: Icons.cameraswitch_outlined,
                tooltip: state.isFrontCamera
                    ? 'Switch to back camera'
                    : 'Switch to front camera',
                onPressed: cubit.switchCamera,
              ),
            ],
          ),
          if (state.batchImages.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: BlocBuilder<UploadCubit, UploadState>(
                bloc: uploadCubit,
                builder: (context, uploadState) {
                  return _UploadBatchButton(
                    imageCount: state.batchImageCount,
                    isAdding: uploadState.isAddingBatch,
                    onPressed: onUploadBatch,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.zoom,
    required this.isSelected,
    required this.onTap,
  });

  final double zoom;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = zoom % 1 == 0
        ? zoom.toStringAsFixed(0)
        : zoom.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: isSelected ? 40 : 36,
          height: isSelected ? 40 : 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppColors.blue : Colors.black45,
            border: Border.all(
              color: isSelected ? AppColors.blue : Colors.white38,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '${label}x',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.isCapturing, required this.onPressed});

  final bool isCapturing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCapturing ? null : onPressed,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCapturing ? Colors.grey : Colors.white,
          ),
          child: isCapturing
              ? const Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ),
    );
  }
}

/// The prominent bottom action from the reference design - same
/// [UploadCubit.addBatchToQueue] call the old top-right button made, just
/// relocated and restyled to read as the primary call to action.
class _UploadBatchButton extends StatelessWidget {
  const _UploadBatchButton({
    required this.imageCount,
    required this.isAdding,
    required this.onPressed,
  });

  final int imageCount;
  final bool isAdding;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isAdding ? null : onPressed,
        icon: isAdding
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.cloud_upload_outlined, size: 20),
        label: Text('Upload Batch ($imageCount)'),
      ),
    );
  }
}
