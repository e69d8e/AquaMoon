import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../providers/audio_provider.dart';
import '../../providers/playlist_provider.dart';
import '../widgets/song_tile.dart';

/// 最近播放页：按时间倒序展示播放历史（最多 100 条），不占用底部导航位，
/// 从首页「更多」菜单进入。播放全部即以历史顺序作为队列。
class RecentPlaysPage extends ConsumerWidget {
  const RecentPlaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historySongs = ref.watch(historySongsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('最近播放'),
        actions: [
          if (historySongs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 22),
              tooltip: '清空播放历史',
              onPressed: () => _confirmClearHistory(context, ref),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: historySongs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 64,
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '还没有播放记录',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '播放过的歌曲会按时间自动出现在这里',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '共 ${historySongs.length} 条记录',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(audioControllerProvider)
                              .playSong(historySongs.first,
                                  queue: historySongs);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('播放全部'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final shuffled = List.of(historySongs)..shuffle();
                          ref
                              .read(audioControllerProvider)
                              .playSong(shuffled.first, queue: shuffled);
                        },
                        icon: const Icon(Icons.shuffle_rounded, size: 16),
                        label: const Text('随机'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: historySongs.length,
                    itemBuilder: (context, index) {
                      final song = historySongs[index];
                      return SongTile(
                        song: song,
                        contextQueue: historySongs,
                        index: index,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text(
          '将清空全部最近播放记录（不影响收藏、歌单与听歌统计），此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Capture the notifier before the await — ref dies with the page if it
    // gets popped while the Hive write runs.
    final storage = ref.read(storageServiceProvider);
    final historyTick = ref.read(historyRefreshTickProvider.notifier);
    await storage.clearHistory();
    if (!context.mounted) return;
    historyTick.state++;
    AppToast.show(context, '已清空播放历史', icon: Icons.delete_sweep_rounded);
  }
}
