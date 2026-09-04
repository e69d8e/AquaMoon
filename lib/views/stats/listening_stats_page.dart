import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../models/listening_stats.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/listening_stats_provider.dart';
import '../widgets/song_artwork.dart';
import 'widgets/listening_chart.dart';
import 'widgets/stats_summary_card.dart';

class ListeningStatsPage extends ConsumerWidget {
  const ListeningStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final periodType = ref.watch(statsPeriodTypeProvider);
    final selectedDate = ref.watch(selectedStatsDateProvider);
    final stats = ref.watch(listeningPeriodStatsProvider);

    final now = DateTime.now();
    final isCurrentPeriod = _isCurrentPeriod(periodType, selectedDate, now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('听歌统计'),
        actions: [
          if (!isCurrentPeriod)
            TextButton.icon(
              onPressed: () {
                ref.read(selectedStatsDateProvider.notifier).state = DateTime.now();
              },
              icon: const Icon(Icons.today_rounded, size: 18),
              label: const Text('今天'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: '选择日期',
            onPressed: () => _selectDate(context, ref, selectedDate),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Period Selector Tabs (Day, Week, Month, Year)
          _buildPeriodSelector(context, ref, periodType),

          const SizedBox(height: 16),

          // 2. Date Navigation Bar (< Date Title >)
          _buildDateNavigator(context, ref, periodType, selectedDate, isCurrentPeriod),

          const SizedBox(height: 16),

          // 3. Hero Summary Card
          StatsSummaryCard(stats: stats),

          const SizedBox(height: 20),

          // 4. Interactive Duration Distribution Chart
          ListeningChart(
            bars: stats.chartBars,
            periodType: periodType,
          ),

          const SizedBox(height: 24),

          // 5. Top Songs Section
          _buildTopSongsSection(context, ref, stats.topSongs),

          const SizedBox(height: 24),

          // 6. Top Artists Section
          if (stats.topArtists.isNotEmpty) ...[
            _buildTopArtistsSection(context, stats.topArtists),
            const SizedBox(height: 24),
          ],

          // Footer
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                '水月音 · 静心聆听，乐随心转',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector(BuildContext context, WidgetRef ref, PeriodType activeType) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2230) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: PeriodType.values.map((type) {
          final isSelected = type == activeType;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isSelected) {
                  ref.read(statsPeriodTypeProvider.notifier).state = type;
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  type.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateNavigator(
    BuildContext context,
    WidgetRef ref,
    PeriodType periodType,
    DateTime selectedDate,
    bool isCurrentPeriod,
  ) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          tooltip: '上一${periodType.label}',
          onPressed: () {
            ref.read(selectedStatsDateProvider.notifier).state =
                _stepDate(periodType, selectedDate, -1);
          },
        ),
        GestureDetector(
          onTap: () => _selectDate(context, ref, selectedDate),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDateTitle(periodType, selectedDate),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          tooltip: isCurrentPeriod ? '已是最新时段' : '下一${periodType.label}',
          onPressed: isCurrentPeriod
              ? null
              : () {
                  ref.read(selectedStatsDateProvider.notifier).state =
                      _stepDate(periodType, selectedDate, 1);
                },
        ),
      ],
    );
  }

  Widget _buildTopSongsSection(BuildContext context, WidgetRef ref, List<SongStatItem> topSongs) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.leaderboard_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '常听歌曲榜',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (topSongs.isNotEmpty)
              Text(
                '共 ${topSongs.length} 首',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (topSongs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.library_music_outlined,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 8),
                Text(
                  '此周期内暂无听歌记录',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          )
        else
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topSongs.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, index) {
                final item = topSongs[index];
                return _buildTopSongTile(context, ref, index + 1, item);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTopSongTile(BuildContext context, WidgetRef ref, int rank, SongStatItem item) {
    final theme = Theme.of(context);

    // Medal colors for top 3
    Widget rankWidget;
    if (rank == 1) {
      rankWidget = Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Color(0xFFFFD700),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text('1', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    } else if (rank == 2) {
      rankWidget = Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Color(0xFFE0E0E0),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text('2', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    } else if (rank == 3) {
      rankWidget = Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Color(0xFFCD7F32),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text('3', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    } else {
      rankWidget = SizedBox(
        width: 22,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          rankWidget,
          const SizedBox(width: 10),
          SongArtwork(
            artUri: item.albumArtUri,
            size: 42,
            borderRadius: 8,
          ),
        ],
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        item.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Formatters.formatListeningDuration(item.duration, short: true),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          if (item.playCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${item.playCount} 次',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        // Try finding the song from library and play it
        final allSongs = ref.read(libraryNotifierProvider).songs;
        final match = allSongs.where((s) => s.id == item.songId).firstOrNull;
        if (match != null) {
          ref.read(audioControllerProvider).playSong(match);
          AppToast.show(
            context,
            '开始播放《${match.title}》',
            icon: Icons.play_arrow_rounded,
          );
        } else {
          // If song was an online or deleted track, create lightweight Song object
          final song = Song(
            id: item.songId,
            title: item.title,
            artist: item.artist,
            album: item.album,
            durationMs: item.durationSeconds * 1000,
            filePath: '',
            albumArtUri: item.albumArtUri,
            dateAdded: DateTime.now(),
          );
          AppToast.show(
            context,
            '《${song.title}》为历史收听快照',
            icon: Icons.history_rounded,
          );
        }
      },
    );
  }

  Widget _buildTopArtistsSection(BuildContext context, List<ArtistStatItem> topArtists) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.person_pin_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              '常听歌手榜',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topArtists.length > 10 ? 10 : topArtists.length,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 56),
            itemBuilder: (context, index) {
              final item = topArtists[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                title: Text(
                  item.artist,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '收听 ${item.songCount} 首曲目 · ${item.playCount} 次播放',
                  style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  Formatters.formatListeningDuration(item.duration, short: true),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isCurrentPeriod(PeriodType type, DateTime selected, DateTime now) {
    switch (type) {
      case PeriodType.day:
        return selected.year == now.year && selected.month == now.month && selected.day == now.day;
      case PeriodType.week:
        final selMonday = selected.subtract(Duration(days: selected.weekday - 1));
        final nowMonday = now.subtract(Duration(days: now.weekday - 1));
        return selMonday.year == nowMonday.year &&
            selMonday.month == nowMonday.month &&
            selMonday.day == nowMonday.day;
      case PeriodType.month:
        return selected.year == now.year && selected.month == now.month;
      case PeriodType.year:
        return selected.year == now.year;
    }
  }

  DateTime _stepDate(PeriodType type, DateTime date, int step) {
    switch (type) {
      case PeriodType.day:
        return date.add(Duration(days: step));
      case PeriodType.week:
        return date.add(Duration(days: step * 7));
      case PeriodType.month:
        return DateTime(date.year, date.month + step, date.day.clamp(1, 28));
      case PeriodType.year:
        return DateTime(date.year + step, date.month, date.day.clamp(1, 28));
    }
  }

  String _formatDateTitle(PeriodType type, DateTime date) {
    switch (type) {
      case PeriodType.day:
        return Formatters.formatChineseDate(date);
      case PeriodType.week:
        final monday = date.subtract(Duration(days: date.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return '${monday.month}月${monday.day}日 - ${sunday.month}月${sunday.day}日';
      case PeriodType.month:
        return '${date.year}年${date.month}月';
      case PeriodType.year:
        return '${date.year}年度';
    }
  }

  Future<void> _selectDate(BuildContext context, WidgetRef ref, DateTime initialDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(selectedStatsDateProvider.notifier).state = picked;
    }
  }
}
