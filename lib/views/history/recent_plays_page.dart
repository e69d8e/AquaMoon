import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../providers/audio_provider.dart';
import '../../providers/playlist_provider.dart';
import '../player/mini_player.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui_helpers.dart';

/// 最近播放页：按时间倒序展示播放历史（最多 100 条），不占用底部导航位，
/// 从首页入口进入。播放全部即以历史顺序作为队列。
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
      body: Stack(
        children: [
          if (historySongs.isEmpty)
            const EmptyStateView(
              icon: Icons.history_rounded,
              title: '还没有播放记录',
              subtitle: '播放过的歌曲会按聆听时间自动记录在这里',
            )
          else
            ResponsivePageContainer(
              maxWidth: 900,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '共 ${historySongs.length} 条记录',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilledButton.icon(
                                onPressed: () {
                                  ref
                                      .read(audioControllerProvider)
                                      .playSong(
                                        historySongs.first,
                                        queue: historySongs,
                                      );
                                },
                                icon: const Icon(Icons.play_arrow_rounded, size: 17),
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
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 104,
                      ),
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
            ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: '清空播放历史',
      message: '将清空全部最近播放记录（不影响收藏、歌单与听歌统计），此操作不可撤销。',
      confirmLabel: '清空',
    );
    if (!confirmed) return;
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
