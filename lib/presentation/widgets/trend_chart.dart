import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// One month of the trend chart.
@immutable
class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.income,
    required this.expense,
  });

  /// Short month label, e.g. "Mar".
  final String label;

  /// Minor units, both non-negative.
  final int income;
  final int expense;
}

/// A six-month income/expense trend, drawn with [CustomPainter].
///
/// Two lines with a gradient fill under the expense curve, a horizontal grid
/// scaled to the data, and a draggable read-out. The whole thing is one
/// repaint; there is no chart library involved.
class TrendChart extends StatefulWidget {
  const TrendChart({
    required this.points,
    required this.formatValue,
    super.key,
    this.selectedIndex,
    this.onSelected,
    this.height = 172,
  });

  final List<TrendPoint> points;

  /// Turns minor units into an axis label. Passed in so the chart never has to
  /// know about currencies.
  final String Function(int minorUnits) formatValue;

  final int? selectedIndex;
  final ValueChanged<int?>? onSelected;
  final double height;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.chart,
  );
  late Animation<double> _growth = CurvedAnimation(
    parent: _controller,
    curve: Motion.curve,
  );

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
  void didUpdateWidget(covariant TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length ||
        !_sameValues(oldWidget.points, widget.points)) {
      _growth = CurvedAnimation(parent: _controller, curve: Motion.curve);
      _controller.forward(from: 0);
    }
  }

  static bool _sameValues(List<TrendPoint> a, List<TrendPoint> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].income != b[i].income || a[i].expense != b[i].expense) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(Offset localPosition, double width) {
    if (widget.onSelected == null || widget.points.isEmpty) return;
    final step = width / widget.points.length;
    final index = (localPosition.dx / step).floor().clamp(
      0,
      widget.points.length - 1,
    );
    if (index != widget.selectedIndex) widget.onSelected!(index);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.ledgerColors;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _select(d.localPosition, constraints.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _select(d.localPosition, constraints.maxWidth),
            onHorizontalDragEnd: (_) => widget.onSelected?.call(null),
            onTapCancel: () => widget.onSelected?.call(null),
            child: AnimatedBuilder(
              animation: _growth,
              builder: (context, _) => CustomPaint(
                size: Size(constraints.maxWidth, widget.height),
                painter: _TrendPainter(
                  points: widget.points,
                  progress: _growth.value,
                  expenseColor: ledger.expense,
                  incomeColor: ledger.income,
                  gridColor: ledger.gridLine,
                  labelStyle: context.texts.labelSmall!.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  selectedIndex: widget.selectedIndex,
                  selectionColor: context.colors.onSurface,
                  formatValue: widget.formatValue,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.progress,
    required this.expenseColor,
    required this.incomeColor,
    required this.gridColor,
    required this.labelStyle,
    required this.selectedIndex,
    required this.selectionColor,
    required this.formatValue,
    required this.textDirection,
  });

  final List<TrendPoint> points;
  final double progress;
  final Color expenseColor;
  final Color incomeColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final int? selectedIndex;
  final Color selectionColor;
  final String Function(int) formatValue;
  final TextDirection textDirection;

  static const _labelHeight = 20.0;
  static const _topPadding = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final plotHeight = size.height - _labelHeight - _topPadding;
    if (plotHeight <= 0) return;

    final peak = points.fold<int>(
      0,
      (best, p) => math.max(best, math.max(p.income, p.expense)),
    );
    // A flat zero ledger still needs a sensible axis.
    final axisMax = _niceCeiling(peak == 0 ? 1 : peak);

    final step = size.width / points.length;
    double xFor(int index) => step * (index + 0.5);
    double yFor(int value) =>
        _topPadding + plotHeight * (1 - value / axisMax) * 1.0;

    _paintGrid(canvas, size, plotHeight, axisMax);

    _paintSeries(
      canvas,
      size,
      points.map((p) => p.expense).toList(),
      xFor,
      yFor,
      expenseColor,
      fill: true,
      plotBottom: _topPadding + plotHeight,
    );
    _paintSeries(
      canvas,
      size,
      points.map((p) => p.income).toList(),
      xFor,
      yFor,
      incomeColor,
      fill: false,
      plotBottom: _topPadding + plotHeight,
    );

    _paintLabels(canvas, size, step);

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      final x = xFor(selected);
      canvas.drawLine(
        Offset(x, _topPadding),
        Offset(x, _topPadding + plotHeight),
        Paint()
          ..color = selectionColor.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      for (final (value, color) in [
        (points[selected].expense, expenseColor),
        (points[selected].income, incomeColor),
      ]) {
        canvas
          ..drawCircle(Offset(x, yFor(value)), 5, Paint()..color = color)
          ..drawCircle(
            Offset(x, yFor(value)),
            2,
            Paint()..color = selectionColor.withValues(alpha: 0.9),
          );
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size, double plotHeight, int axisMax) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 2; i++) {
      final value = axisMax - axisMax * i ~/ 2;
      final y = _topPadding + plotHeight * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);

      if (i < 2) {
        final label = _layout(formatValue(value), labelStyle);
        label.paint(canvas, Offset(0, y - label.height - 2));
      }
    }
  }

  void _paintSeries(
    Canvas canvas,
    Size size,
    List<int> values,
    double Function(int) xFor,
    double Function(int) yFor,
    Color color, {
    required bool fill,
    required double plotBottom,
  }) {
    final path = Path();
    final area = Path();

    for (var i = 0; i < values.length; i++) {
      // Each point rises from the baseline as the animation runs.
      final animated = (values[i] * progress).round();
      final point = Offset(xFor(i), yFor(animated));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
        area
          ..moveTo(point.dx, plotBottom)
          ..lineTo(point.dx, point.dy);
      } else {
        final previous = Offset(
          xFor(i - 1),
          yFor((values[i - 1] * progress).round()),
        );
        // A gentle cubic between neighbours reads better than straight
        // segments without inventing data between the months.
        final controlX = (previous.dx + point.dx) / 2;
        path.cubicTo(
          controlX,
          previous.dy,
          controlX,
          point.dy,
          point.dx,
          point.dy,
        );
        area.cubicTo(
          controlX,
          previous.dy,
          controlX,
          point.dy,
          point.dx,
          point.dy,
        );
      }
    }

    if (fill && values.isNotEmpty) {
      area
        ..lineTo(xFor(values.length - 1), plotBottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, _topPadding),
            Offset(0, plotBottom),
            [color.withValues(alpha: 0.26), color.withValues(alpha: 0.02)],
          ),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fill ? 2.6 : 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  void _paintLabels(Canvas canvas, Size size, double step) {
    for (var i = 0; i < points.length; i++) {
      final selected = selectedIndex == i;
      final painter = _layout(
        points[i].label,
        selected
            ? labelStyle.copyWith(
                color: selectionColor,
                fontWeight: FontWeight.w700,
              )
            : labelStyle,
      );
      painter.paint(
        canvas,
        Offset(
          step * i + (step - painter.width) / 2,
          size.height - _labelHeight + 4,
        ),
      );
    }
  }

  TextPainter _layout(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
  )..layout();

  /// Rounds an axis maximum up to 1, 2 or 5 times a power of ten, so the grid
  /// labels are numbers a person would choose.
  static int _niceCeiling(int value) {
    final magnitude = math
        .pow(10, (math.log(value) / math.ln10).floor())
        .toInt();
    for (final multiple in [1, 2, 5, 10]) {
      final candidate = magnitude * multiple;
      if (candidate >= value) return candidate;
    }
    return magnitude * 10;
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.progress != progress ||
      old.selectedIndex != selectedIndex ||
      old.expenseColor != expenseColor ||
      old.incomeColor != incomeColor ||
      old.points != points;
}
