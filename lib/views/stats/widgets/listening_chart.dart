import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/listening_stats.dart';

class ListeningChart extends StatefulWidget {
  final List<ChartBarData> bars;
  final PeriodType periodType;

  const ListeningChart({
    super.key,
    required this.bars,
    required this.periodType,
  });

  @override
  State<ListeningChart> createState() => _ListeningChartState();
}

class _ListeningChartState extends State<ListeningChart> {
  int? _selectedBarIndex;

  @override
  void didUpdateWidget(covariant ListeningChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodType != widget.periodType) {
      _selectedBarIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final maxDurationSec = widget.bars.fold<int>(
      0,
      (max, b) => b.durationSeconds > max ? b.durationSeconds : max,
    );

    if (widget.bars.isEmpty || maxDurationSec <= 0) {
      return Container(
        height: 190,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              '当前时段暂无时长分布数据',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selectedBar =
        _selectedBarIndex != null && _selectedBarIndex! < widget.bars.length
        ? widget.bars[_selectedBarIndex!]
        : null;

    final isMonthView = widget.periodType == PeriodType.month;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getChartTitle(widget.periodType),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (selectedBar != null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(selectedBar.label),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${selectedBar.label}: ${Formatters.formatListeningDuration(selectedBar.duration, short: true)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                )
              else
                Text(
                  '最高: ${Formatters.formatListeningDuration(Duration(seconds: maxDurationSec), short: true)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          // Bars rendering
          SizedBox(
            height: 140,
            child: isMonthView
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(widget.bars.length, (index) {
                        return _buildBarItem(
                          context,
                          index: index,
                          bar: widget.bars[index],
                          maxSec: maxDurationSec,
                          width: 14,
                          margin: 4,
                          showLabel:
                              (index == 0 ||
                              (index + 1) % 5 == 0 ||
                              index == widget.bars.length - 1),
                        );
                      }),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(widget.bars.length, (index) {
                      return Expanded(
                        child: _buildBarItem(
                          context,
                          index: index,
                          bar: widget.bars[index],
                          maxSec: maxDurationSec,
                          showLabel: _shouldShowLabel(
                            widget.periodType,
                            index,
                            widget.bars.length,
                          ),
                        ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarItem(
    BuildContext context, {
    required int index,
    required ChartBarData bar,
    required int maxSec,
    double? width,
    double margin = 2,
    required bool showLabel,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedBarIndex == index;

    final ratio = maxSec > 0
        ? (bar.durationSeconds / maxSec).clamp(0.0, 1.0)
        : 0.0;
    final barHeight = max(4.0, ratio * 96.0);

    Color barColor;
    if (bar.durationSeconds == 0) {
      barColor = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06);
    } else if (isSelected) {
      barColor = theme.colorScheme.primary;
    } else if (bar.isHighlighted) {
      barColor = theme.colorScheme.primary.withValues(alpha: 0.85);
    } else {
      barColor = theme.colorScheme.primary.withValues(
        alpha: isDark ? 0.45 : 0.35,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          if (_selectedBarIndex == index) {
            _selectedBarIndex = null;
          } else {
            _selectedBarIndex = index;
          }
        });
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: margin),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Top duration dot / indicator when selected or highlighted
            SizedBox(
              height: 14,
              child: isSelected && bar.durationSeconds > 0
                  ? Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: theme.colorScheme.primary,
                    )
                  : (bar.isHighlighted && bar.durationSeconds > 0
                        ? Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null),
            ),
            const SizedBox(height: 2),

            // Bar shape
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: width ?? double.infinity,
              height: barHeight,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(
                  width != null ? width / 2 : 4,
                ),
                border: isSelected
                    ? Border.all(color: theme.colorScheme.surface, width: 1.2)
                    : null,
              ),
            ),

            const SizedBox(height: 6),

            // Bottom Label
            SizedBox(
              height: 18,
              child: Text(
                showLabel ? bar.sublabel : '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected || bar.isHighlighted
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : (bar.isHighlighted
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getChartTitle(PeriodType type) {
    switch (type) {
      case PeriodType.day:
        return '24 小时活跃时段分布';
      case PeriodType.week:
        return '本周单日听歌时长分布';
      case PeriodType.month:
        return '本月每日听歌时长走势';
      case PeriodType.year:
        return '年度各月听歌时长走势';
      case PeriodType.all:
        return '历史各时段听歌分布';
    }
  }

  bool _shouldShowLabel(PeriodType type, int index, int total) {
    switch (type) {
      case PeriodType.day:
        // Show labels every 4 hours: 00:00, 04:00, 08:00, 12:00, 16:00, 20:00
        return index % 4 == 0;
      case PeriodType.week:
        return true;
      case PeriodType.month:
        return index == 0 || (index + 1) % 5 == 0 || index == total - 1;
      case PeriodType.year:
        return true;
      case PeriodType.all:
        return index % 4 == 0;
    }
  }
}
