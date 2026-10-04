import 'package:flutter/material.dart';
import '../../core/utils/formatters.dart';
import '../../models/playback_progress.dart';

class CustomProgressBar extends StatefulWidget {
  final PlaybackProgress progress;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration>? onSeeking;
  final bool showTimeLabels;

  const CustomProgressBar({
    super.key,
    required this.progress,
    required this.onSeek,
    this.onSeeking,
    this.showTimeLabels = true,
  });

  @override
  State<CustomProgressBar> createState() => _CustomProgressBarState();
}

class _CustomProgressBarState extends State<CustomProgressBar> {
  double? _dragValue;

  /// 松手后的 seek 目标（毫秒）。进度流约 3 次/秒才更新一次，在它反映新
  /// 位置之前沿用拖动值渲染，否则滑块会先弹回旧位置、等流追上再跳回来。
  double? _pendingSeekMs;

  @override
  void didUpdateWidget(covariant CustomProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pendingSeekMs;
    if (pending != null) {
      final streamedMs = widget.progress.position.inMilliseconds.toDouble();
      // 进度流到达 seek 目标附近（±1.5s）后切回流式进度。
      if ((streamedMs - pending).abs() <= 1500) {
        setState(() {
          _pendingSeekMs = null;
          _dragValue = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final colorScheme = theme.colorScheme;

    final durationMs = widget.progress.duration.inMilliseconds.toDouble();
    final currentMs = _dragValue ?? widget.progress.position.inMilliseconds.toDouble();

    final maxVal = durationMs > 0 ? durationMs : 1.0;
    final clampedVal = currentMs.clamp(0.0, maxVal);

    final activeColor = colorScheme.onSurface;
    final inactiveColor = colorScheme.onSurface.withValues(alpha: isLight ? 0.12 : 0.22);
    final labelColor = colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 0,
              disabledThumbRadius: 0,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: activeColor,
            inactiveTrackColor: inactiveColor,
            thumbColor: activeColor,
            overlayColor: activeColor.withValues(alpha: 0.15),
          ),
          child: Slider(
            min: 0.0,
            max: maxVal,
            value: clampedVal,
            onChanged: (val) {
              setState(() {
                _dragValue = val;
                _pendingSeekMs = null;
              });
              widget.onSeeking?.call(Duration(milliseconds: val.toInt()));
            },
            onChangeEnd: (val) {
              setState(() {
                _pendingSeekMs = val;
              });
              widget.onSeek(Duration(milliseconds: val.toInt()));
            },
          ),
        ),
        if (widget.showTimeLabels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Formatters.formatDuration(
                    _dragValue != null
                        ? Duration(milliseconds: _dragValue!.toInt())
                        : widget.progress.position,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: labelColor,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  Formatters.formatDuration(widget.progress.duration),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: labelColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
