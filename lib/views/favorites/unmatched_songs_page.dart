import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/qq_music_provider.dart';
import '../online_search/online_search_page.dart';
import '../widgets/debounced_search_field.dart';
import '../widgets/qq_music_auth_dialog.dart';
import '../widgets/qq_music_sync_helpers.dart';
import '../widgets/song_tile.dart';

/// 本地未匹配歌曲页：集中展示 QQ 音乐收藏中尚未匹配到本地音频的曲目，
/// 支持搜索、试听以及一键「关联本地音频」。
class UnmatchedSongsPage extends ConsumerStatefulWidget {
  const UnmatchedSongsPage({super.key});

  @override
  ConsumerState<UnmatchedSongsPage> createState() => _UnmatchedSongsPageState();
}

class _UnmatchedSongsPageState extends ConsumerState<UnmatchedSongsPage> {
  final GlobalKey<DebouncedSearchFieldState> _searchFieldKey = GlobalKey();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final qqState = ref.watch(qqMusicFavoritesProvider);
    final allUnmatched = ref.watch(unmatchedFavoritesProvider);
    final theme = Theme.of(context);

    final trimmedQuery = _searchQuery.trim();
    final normalizedQuery = trimmedQuery.toLowerCase();
    final isSearching = normalizedQuery.isNotEmpty;
    final filtered = isSearching
        ? allUnmatched
              .where((song) => songMatchesQuery(song, normalizedQuery))
              .toList(growable: false)
        : allUnmatched;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地未匹配歌曲'),
        actions: [
          if (qqState.isBound) ...[
            IconButton(
              icon: qqState.isSyncing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 22),
              tooltip: '同步并重新匹配',
              onPressed: qqState.isSyncing
                  ? null
                  : () => triggerQQMusicSync(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.manage_accounts_outlined, size: 22),
              tooltip: 'QQ 音乐账号配置',
              onPressed: () => QQMusicAuthDialog.show(context),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: allUnmatched.isEmpty
          ? _buildStatusState(context, theme, qqState)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSearching
                                  ? '未匹配 ${filtered.length}/${allUnmatched.length} 首'
                                  : '共 ${allUnmatched.length} 首未匹配',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '已匹配 ${qqState.localMatchedCount}/${qqState.mergedSongs.length} 首 · 点右侧 🔗 关联本地文件',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: filtered.isEmpty
                            ? null
                            : () {
                                ref
                                    .read(audioControllerProvider)
                                    .playSong(filtered.first, queue: filtered);
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('播放全部'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: filtered.isEmpty
                            ? null
                            : () {
                                final shuffled = List<Song>.from(filtered)
                                  ..shuffle();
                                ref
                                    .read(audioControllerProvider)
                                    .playSong(shuffled.first, queue: shuffled);
                              },
                        icon: const Icon(Icons.shuffle_rounded, size: 16),
                        label: const Text('随机'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: DebouncedSearchField(
                    key: _searchFieldKey,
                    initialQuery: _searchQuery,
                    hintText: '搜索未匹配歌曲、歌手、专辑...',
                    onQueryChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
                ),
                if (qqState.syncError != null)
                  QQMusicSyncErrorBanner(message: qqState.syncError!),
                Expanded(
                  child: filtered.isEmpty
                      ? SongSearchEmptyState(
                          message: '未找到与「$trimmedQuery」相关的未匹配歌曲',
                          onClearSearch: () =>
                              _searchFieldKey.currentState?.clear(),
                          onSecondaryAction: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    OnlineSearchPage(initialQuery: trimmedQuery),
                              ),
                            );
                          },
                          secondaryLabel: '全网在线检索「$trimmedQuery」',
                        )
                      : RefreshIndicator(
                          onRefresh: () => triggerQQMusicSync(context, ref),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemExtent: 58.0,
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom + 32,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final song = filtered[index];
                              return SongTile(
                                song: song,
                                contextQueue: filtered,
                                index: index,
                                showQuickLinkAction: true,
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusState(
    BuildContext context,
    ThemeData theme,
    QQMusicFavoritesState qqState,
  ) {
    if (!qqState.isBound && qqState.mergedSongs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.link_off_rounded,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 14),
              const Text(
                '尚未接入 QQ 音乐收藏',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '绑定 QQ 音乐「我喜欢」后，未能自动匹配到本地音频的收藏曲目会集中列在这里，方便查找与手动关联。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => QQMusicAuthDialog.show(context),
                icon: const Icon(Icons.add_link_rounded, size: 19),
                label: const Text('连接 QQ 音乐收藏'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (qqState.isSyncing && qqState.mergedSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在同步 QQ 音乐「我喜欢」歌单...',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (qqState.mergedSongs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                qqState.syncError != null
                    ? Icons.cloud_off_rounded
                    : Icons.playlist_remove_rounded,
                size: 60,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                qqState.syncError != null ? '同步 QQ 音乐收藏遇到问题' : '「我喜欢」歌单暂无歌曲',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                qqState.syncError ??
                    '已连接 ${qqState.config.displayLabel}，点击下方按钮可刷新同步或修改配置',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => triggerQQMusicSync(context, ref),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('立即同步'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => QQMusicAuthDialog.show(context),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('账号配置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 已绑定且收藏非空，但所有歌曲均已匹配到本地音频。
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 14),
            const Text(
              '全部收藏均已匹配本地音频',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '共 ${qqState.mergedSongs.length} 首 QQ 音乐收藏曲目，均已关联本地文件',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: qqState.isSyncing
                  ? null
                  : () => triggerQQMusicSync(context, ref),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('刷新同步'),
            ),
          ],
        ),
      ),
    );
  }
}
