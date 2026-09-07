import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

@immutable
class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;

  /// Any non-negative magnitude; the chart only works in proportions.
  final int value;

  final Color color;
}

/// Sweeps on first build and whenever the data changes, growing each wedge
/// from zero. Honours the platform's reduced-motion setting.
class DonutChart extends StatefulWidget {
  const DonutChart({
    required this.slices,
    super.key,
    this.strokeWidth = 22,
    this.selectedIndex,
    this.onSliceTapped,
    this.centre,
  });

  final List<DonutSlice> slices;
  final double strokeWidth;

  /// Pulls one wedge slightly outward and dims the rest.
  final int? selectedIndex;

  final ValueChanged<int?>? onSliceTapped;

  /// Drawn in the hole. Usually the total.
  final Widget? centre;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.chart,
  );
  late Animation<double> _sweep = _buildAnimation();

  Animation<double> _buildAnimation() =>
      CurvedAnimation(parent: _controller, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..duration = Duration.zero
        ..value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant DonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameData(oldWidget.slices, widget.slices)) {
      _sweep = _buildAnimation();
      _controller.forward(from: 0);
    }
  }

  static bool _sameData(List<DonutSlice> a, List<DonutSlice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].label != b[i].label) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _DonutPainter(
      slices: widget.slices,
      strokeWidth: widget.strokeWidth,
      trackColor: context.colors.surfaceContainerHighest,
      selectedIndex: widget.selectedIndex,
      progress: 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: widget.onSliceTapped == null
              ? null
              : (details) => widget.onSliceTapped!(
                  painter.sliceAt(details.localPosition, Size(size, size)),
                ),
          child: SizedBox.square(
            dimension: size,
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, child) {
                return CustomPaint(
                  painter: _DonutPainter(
                    slices: widget.slices,
                    strokeWidth: widget.strokeWidth,
                    trackColor: context.colors.surfaceContainerHighest,
                    selectedIndex: widget.selectedIndex,
                    progress: _sweep.value,
                  ),
                  child: child,
                );
              },
              child: Center(child: widget.centre),
            ),
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.strokeWidth,
    required this.trackColor,
    required this.progress,
    required this.selectedIndex,
  });

  final List<DonutSlice> slices;
  final double strokeWidth;
  final Color trackColor;
  final double progress;
  final int? selectedIndex;

  /// Wedges start at 12 o'clock and run clockwise.
  static const _startAngle = -math.pi / 2;
  static const _fullTurn = math.pi * 2;

  /// Radians of blank space between wedges.
  static const _gap = 0.035;

  int get _total => slices.fold(0, (sum, slice) => sum + slice.value);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(centre, radius, track);

    final total = _total;
    if (total <= 0) return;

    var angle = _startAngle;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      if (slice.value <= 0) continue;

      final share = slice.value / total;
      final fullSweep = share * _fullTurn;
      final sweep = fullSweep * progress;
      // Measured against the full sweep, not the animated one, so gaps do not
      // pop into existence part way through the animation.
      final gap = fullSweep > _gap * 3 ? _gap : 0.0;
      final dimmed = selectedIndex != null && selectedIndex != i;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selectedIndex == i ? strokeWidth + 6 : strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = dimmed ? slice.color.withValues(alpha: 0.28) : slice.color;

      canvas.drawArc(
        rect,
        angle + gap / 2,
        math.max(sweep - gap, 0),
        false,
        paint,
      );
      angle += fullSweep;
    }
  }

  /// Null for the hole in the middle and for anything outside the ring.
  int? sliceAt(Offset position, Size size) {
    final total = _total;
    if (total <= 0) return null;

    final centre = size.center(Offset.zero);
    final offset = position - centre;
    final distance = offset.distance;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    if (distance < radius - strokeWidth || distance > radius + strokeWidth) {
      return null;
    }

    var angle = math.atan2(offset.dy, offset.dx) - _startAngle;
    if (angle < 0) angle += _fullTurn;

    var walked = 0.0;
    for (var i = 0; i < slices.length; i++) {
      walked += slices[i].value / total * _fullTurn;
      if (angle <= walked) return i;
    }
    return null;
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.selectedIndex != selectedIndex ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      !_DonutChartState._sameData(old.slices, slices);
}
