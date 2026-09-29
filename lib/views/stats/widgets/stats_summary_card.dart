import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/listening_stats.dart';

class StatsSummaryCard extends StatelessWidget {
  final ListeningPeriodStats stats;

  const StatsSummaryCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasData = stats.totalDurationSeconds > 0;
    final totalDuration = stats.totalDuration;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  theme.colorScheme.surface,
                ]
              : [
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  theme.colorScheme.surface,
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(
            alpha: isDark ? 0.25 : 0.15,
          ),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(
              alpha: isDark ? 0.08 : 0.04,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header label with icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.headphones_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
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

          // Big Duration Typography
          if (hasData) ...[
            _buildDurationHero(context, totalDuration),
            const SizedBox(height: 8),
            Text(
              '已在此周期内沉浸聆听 ${Formatters.formatListeningDuration(totalDuration)}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.75,
                ),
              ),
            ),
          ] else ...[
            Text(
              '0 分钟',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '静心聆听，曲随心动',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Metric Badges Grid
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildMetricChip(
                context,
                icon: Icons.music_note_rounded,
                label: '收听曲目',
                value: '${stats.distinctSongsCount} 首',
              ),
              _buildMetricChip(
                context,
                icon: Icons.repeat_rounded,
                label: '播放次数',
                value: '${stats.totalPlayCount} 次',
              ),
              if (stats.distinctArtistsCount > 0)
                _buildMetricChip(
                  context,
                  icon: Icons.person_outline_rounded,
                  label: '常听歌手',
                  value: '${stats.distinctArtistsCount} 位',
                ),
              if (stats.periodType != PeriodType.day &&
                  stats.averageDailySeconds > 0)
                _buildMetricChip(
                  context,
                  icon: Icons.calendar_today_rounded,
                  label: '日均时长',
                  value: Formatters.formatListeningDuration(
                    stats.averageDailyDuration,
                    short: true,
                  ),
                ),
              if (hasData && stats.peakTimeSummary.isNotEmpty)
                _buildMetricChip(
                  context,
                  icon: Icons.access_time_rounded,
                  label: '时段偏好',
                  value: stats.peakTimeSummary,
                ),
            ],
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
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '小时',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          '$minutes',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: hours > 0
                ? theme.colorScheme.onSurface
                : theme.colorScheme.primary,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '分钟',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
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
    }
  }
}
