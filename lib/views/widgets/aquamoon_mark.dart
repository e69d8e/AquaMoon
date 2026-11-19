import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 水月音（AquaMoon）品牌徽标：一弯新月与三道水波声纹。
///
/// 视觉语言呼应应用图标（弯月 + 声波涟漪），主色自动跟随当前配色方案。
class AquaMoonMark extends StatelessWidget {
  final double size;
  final Color? color;

  const AquaMoonMark({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final primary = color ?? Theme.of(context).colorScheme.primary;
    final secondary = Color.lerp(
      primary,
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFE7A94E)
          : const Color(0xFFF3C677),
      0.32,
    )!;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AquaMoonMarkPainter(primary: primary, highlight: secondary),
      ),
    );
  }
}

class _AquaMoonMarkPainter extends CustomPainter {
  final Color primary;
  final Color highlight;

  const _AquaMoonMarkPainter({required this.primary, required this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. 弯月：外圆与偏右上的内圆做差集，绘出温润新月轮廓。
    final moonCenter = Offset(w * 0.44, h * 0.50);
    final outerR = w * 0.38;
    final innerCenter = Offset(w * 0.57, h * 0.41);
    final innerR = w * 0.325;

    final outerPath = Path()
      ..addOval(Rect.fromCircle(center: moonCenter, radius: outerR));
    final innerPath = Path()
      ..addOval(Rect.fromCircle(center: innerCenter, radius: innerR));
    final crescent = Path.combine(
      PathOperation.difference,
      outerPath,
      innerPath,
    );

    final moonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [highlight, primary],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(crescent, moonPaint);

    // 2. 三道声波涟漪弧：从弯月怀抱轻缓向外荡开，由浓渐淡。
    final waveOrigin = Offset(w * 0.45, h * 0.50);
    final radii = [w * 0.19, w * 0.30, w * 0.41];
    final alphas = [0.78, 0.52, 0.28];
    final strokeW = (w * 0.055).clamp(1.1, 2.6);

    for (var i = 0; i < radii.length; i++) {
      final arcPaint = Paint()
        ..color = primary.withValues(alpha: alphas[i])
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      final rect = Rect.fromCircle(center: waveOrigin, radius: radii[i]);
      final sweep = 0.72 + i * 0.14;
      canvas.drawArc(rect, -sweep / 2, sweep, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AquaMoonMarkPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.highlight != highlight;
}

/// 轻盈的三柱声波指示器：播放时如水波呼吸起伏，暂停时静止收束，零冗余开销。
class PlayingWaveIndicator extends StatefulWidget {
  final bool isPlaying;
  final Color? color;
  final double size;

  const PlayingWaveIndicator({
    super.key,
    required this.isPlaying,
    this.color,
    this.size = 14,
  });

  @override
  State<PlayingWaveIndicator> createState() => _PlayingWaveIndicatorState();
}

class _PlayingWaveIndicatorState extends State<PlayingWaveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PlayingWaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (widget.isPlaying && !reduceMotion && tickerEnabled) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.color ?? Theme.of(context).colorScheme.primary;
    final barWidth = (widget.size * 0.17).clamp(2.0, 3.2);
    final gap = (widget.size * 0.13).clamp(1.4, 2.4);
    final barRadius = BorderRadius.circular(barWidth);
    final barBox = DecoratedBox(
      decoration: BoxDecoration(color: barColor, borderRadius: barRadius),
      child: SizedBox(width: barWidth, height: widget.size),
    );

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value * 2 * math.pi;
            final r0 = widget.isPlaying
                ? 0.34 + 0.56 * (0.5 + 0.5 * math.sin(t))
                : 0.34;
            final r1 = widget.isPlaying
                ? 0.42 + 0.54 * (0.5 + 0.5 * math.sin(t + 1.9))
                : 0.56;
            final r2 = widget.isPlaying
                ? 0.28 + 0.58 * (0.5 + 0.5 * math.sin(t + 3.6))
                : 0.30;

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Transform.scale(
                  scaleY: r0,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
                SizedBox(width: gap),
                Transform.scale(
                  scaleY: r1,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
                SizedBox(width: gap),
                Transform.scale(
                  scaleY: r2,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ],
            );
          },
          child: barBox,
        ),
      ),
    );
  }
}
