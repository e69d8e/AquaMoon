import 'dart:math';

import 'package:flutter/material.dart';

/// GitHub 风格的年度听歌热力图：一列一周（周一到周日），颜色深浅代表
/// 当日收听时长。支持横向滚动查看整年。
class ListeningHeatmap extends StatelessWidget {
  final int year;

  /// dateStr (yyyy-MM-dd) -> 当日收听秒数。
  final Map<String, int> dailySeconds;

  static const double _cellSize = 13;
  static const double _cellGap = 3;

  const ListeningHeatmap({
    super.key,
    required this.year,
    required this.dailySeconds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxSeconds = dailySeconds.values.fold(0, max);

    final jan1 = DateTime(year, 1, 1);
    final leadingOffset = jan1.weekday - 1; // Monday-based rows.
    final isLeap =
        (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    final daysInYear = isLeap ? 366 : 365;
    final totalCells = leadingOffset + daysInYear;
    final weekColumns = (totalCells / 7).ceil();

    // 月份标签：每月第一格落在第几周列。
    final monthLabels = <int, String>{};
    for (var m = 1; m <= 12; m++) {
      final first = DateTime(year, m, 1);
      final dayOfYear = first.difference(DateTime(year, 1, 1)).inDays;
      monthLabels[(leadingOffset + dayOfYear) ~/ 7] = '$m月';
    }

    Color cellColor(DateTime day) {
      final seconds = dailySeconds[_dateKey(day)] ?? 0;
      if (seconds <= 0) {
        return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
      }
      // 对数刻度：10 分钟、1 小时、3 小时 三档渐进，避免单日爆量压扁其余。
      final intensity = maxSeconds > 0
          ? (log(seconds + 1) / log(maxSeconds + 1)).clamp(0.0, 1.0)
          : 0.0;
      return Color.lerp(
        theme.colorScheme.primary.withValues(alpha: 0.25),
        theme.colorScheme.primary,
        0.2 + 0.8 * intensity,
      )!;
    }

    // 标签行与网格共用一个横向滚动视图：分开的两个 ScrollView 会在手机上
    // 各滚各的，标签与周列错位。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 月份标签行，与周列水平对齐。
              SizedBox(
                width: weekColumns * (_cellSize + _cellGap),
                height: 14,
                child: Stack(
                  children: [
                    for (final entry in monthLabels.entries)
                      Positioned(
                        left: entry.key * (_cellSize + _cellGap),
                        top: 0,
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 9.5,
                            color:
                                theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: weekColumns * (_cellSize + _cellGap),
                height: 7 * _cellSize + 6 * _cellGap,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: _cellGap,
                    crossAxisSpacing: _cellGap,
                    // 不给 mainAxisExtent 时格子被反算成 13.43px，实际列距
                    // 16.43 ≠ 标签用的 16px：月标签越往后越歪，年末最后几列
                    // 排到视口外永远看不到。
                    mainAxisExtent: _cellSize,
                  ),
                  // 横向主轴 + 7 行交叉轴 = 按周列优先填充。
                  scrollDirection: Axis.horizontal,
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    final cell = index - leadingOffset;
                    if (cell < 0 || cell >= daysInYear) {
                      return const SizedBox.shrink();
                    }
                    // 用构造式日期而不是 1/1 + Duration：夏令时回拨的时区里
                    // 按绝对时间加天会落在前一天 23:00，之后全部错位一天。
                    final day = DateTime(year, 1, cell + 1);
                    return Tooltip(
                      message:
                          '${day.month}月${day.day}日 · ${_formatMinutes(dailySeconds[_dateKey(day)] ?? 0)}',
                      child: Container(
                        decoration: BoxDecoration(
                          color: cellColor(day),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              Text(
                '少',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              for (final alpha in [0.1, 0.35, 0.6, 0.8, 1.0]) ...[
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: alpha == 0.1
                        ? theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.55)
                        : theme.colorScheme.primary.withValues(alpha: alpha),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Text(
                '多',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _dateKey(DateTime day) {
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '${day.year}-$m-$d';
  }

  static String _formatMinutes(int seconds) {
    if (seconds <= 0) return '未收听';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
  }
}
