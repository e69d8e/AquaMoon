import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/listening_stats.dart';

/// 静谧档案风格的听歌时长总览卡：清晰的大号等宽数字与细线分隔指标栏。
class StatsSummaryCard extends StatelessWidget {
  final ListeningPeriodStats stats;

  const StatsSummaryCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);

    final hasData = stats.totalDurationSeconds > 0;
    final totalDuration = stats.totalDuration;

    final metrics = <({String label, String value})>[
      (label: '收听曲目', value: '${stats.distinctSongsCount} 首'),
      (label: '播放次数', value: '${stats.totalPlayCount} 次'),
      if (stats.distinctArtistsCount > 0)
        (label: '常听歌手', value: '${stats.distinctArtistsCount} 位'),
      if (stats.periodType != PeriodType.day && stats.averageDailySeconds > 0)
        (
          label: '日均时长',
          value: Formatters.formatListeningDuration(
            stats.averageDailyDuration,
            short: true,
          ),
        ),
      if (hasData && stats.peakTimeSummary.isNotEmpty)
        (label: '时段偏好', value: stats.peakTimeSummary),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: appColors.glassBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _getPeriodLabel(stats.periodType),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (hasData) ...[
            _buildDurationHero(context, totalDuration),
            const SizedBox(height: 6),
            Text(
              '在此周期内累计聆听 ${Formatters.formatListeningDuration(totalDuration)}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.78,
                ),
              ),
            ),
          ] else ...[
            Text(
              '0 分钟',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurface.withValues(alpha: 0.36),
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '静心聆听，曲随心动',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.65,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          Divider(height: 1, color: appColors.subtleDivider),
          const SizedBox(height: 14),

          // 规整指标栅格：每行固定 3 列均衡排布，杜绝孤立尾项。
          LayoutBuilder(
            builder: (context, constraints) {
              const columns = 3;
              const spacing = 12.0;
              final cellWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: 14,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: cellWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            metric.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            metric.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDurationHero(BuildContext context, Duration duration) {
    final theme = Theme.of(context);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (hours > 0) ...[
          Text(
            '$hours',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: theme.colorScheme.onSurface,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '小时',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Text(
          '$minutes',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: theme.colorScheme.onSurface,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '分钟',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _getPeriodLabel(PeriodType type) {
    switch (type) {
      case PeriodType.day:
        return '今日听歌时长';
      case PeriodType.week:
        return '本周累计听歌';
      case PeriodType.month:
        return '本月累计听歌';
      case PeriodType.year:
        return '年度累计听歌';
      case PeriodType.all:
        return '累计收听时长';
    }
  }
}
