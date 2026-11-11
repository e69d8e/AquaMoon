import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_toast.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/qq_music_provider.dart';
import '../../../services/qq_music_service.dart';
import '../../widgets/qq_music_auth_dialog.dart';
import '../../widgets/song_tile.dart';

class FavoritesTab extends ConsumerStatefulWidget {
  const FavoritesTab({super.key});

  @override
  ConsumerState<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<FavoritesTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentPlaying(String currentSongId, List<Song> songs) {
    final index = songs.indexWhere((s) => s.id == currentSongId);
    if (index >= 0 && _scrollController.hasClients) {
      const itemHeight = 58.0;
      final viewportHeight = _scrollController.position.viewportDimension;
      final targetOffset =
          (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
      final clamped = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );

      AppToast.show(
        context,
        '已定位至第 ${index + 1} 首: ${songs[index].title}',
        icon: Icons.my_location_rounded,
      );
    }
  }

  Future<void> _triggerSync() async {
    final qqState = ref.read(qqMusicFavoritesProvider);
    if (!qqState.isBound) {
      await QQMusicAuthDialog.show(context);
      return;
    }
    try {
      final summary = await ref
          .read(qqMusicFavoritesProvider.notifier)
          .syncFavorites(silent: false);
      if (mounted && summary.isNotEmpty) {
        AppToast.show(
          context,
          summary,
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } on QQMusicApiException catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          e.message,
          icon: Icons.error_outline_rounded,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          '同步失败，请检查网络连接后重试',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesSongsProvider);
    final qqState = ref.watch(qqMusicFavoritesProvider);
    // Only depend on the current song's id: full-object updates (e.g. the
    // syncSong broadcast after a favorite toggle) must not rebuild this page.
    final currentSongId = ref.watch(
      currentSongProvider.select((a) => a.valueOrNull?.id),
    );

    final theme = Theme.of(context);
    final isCurrentSongInList =
        currentSongId != null && favorites.any((s) => s.id == currentSongId);

    if (favorites.isEmpty) {
      return _buildEmptyState(context, theme, qqState);
    }

    return Column(
      children: [
        // Action Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 16,
                color: Colors.redAccent.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              Text(
                '${favorites.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (qqState.isBound)
                Flexible(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => QQMusicAuthDialog.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_done_outlined,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'QQ音乐 · ${qqState.config.displayLabel}'
                              '${qqState.localMatchedCount > 0 ? ' (本地 ${qqState.localMatchedCount})' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () => QQMusicAuthDialog.show(context),
                  icon: const Icon(Icons.add_link_rounded, size: 15),
                  label: const Text(
                    '接入 QQ 音乐收藏',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              const Spacer(),
              if (qqState.isBound) ...[
                IconButton(
                  icon: qqState.isSyncing
                      ? SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.sync_rounded,
                          size: 19,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                  tooltip: '同步 QQ 音乐收藏',
                  visualDensity: VisualDensity.compact,
                  onPressed: qqState.isSyncing ? null : _triggerSync,
                ),
                IconButton(
                  icon: Icon(
                    Icons.manage_accounts_outlined,
                    size: 19,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.75,
                    ),
                  ),
                  tooltip: 'QQ 音乐账号配置',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => QQMusicAuthDialog.show(context),
                ),
              ],
              // Playback actions menu
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 19,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                tooltip: '播放操作',
                position: PopupMenuPosition.under,
                onSelected: (value) {
                  switch (value) {
                    case 'play_all':
                      ref
                          .read(audioControllerProvider)
                          .playSong(favorites.first, queue: favorites);
                      break;
                    case 'play_shuffled':
                      final shuffled = List<Song>.from(favorites)..shuffle();
                      ref
                          .read(audioControllerProvider)
                          .playSong(shuffled.first, queue: shuffled);
                      break;
                    case 'locate':
                      final id = currentSongId;
                      if (id != null) {
                        _scrollToCurrentPlaying(id, favorites);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'play_all',
                    child: Row(
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('播放全部'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'play_shuffled',
                    child: Row(
                      children: [
                        Icon(Icons.shuffle_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('随机播放'),
                      ],
                    ),
                  ),
                  if (isCurrentSongInList)
                    const PopupMenuItem(
                      value: 'locate',
                      child: Row(
                        children: [
                          Icon(Icons.my_location_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('定位当前播放'),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        if (qqState.syncError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      qqState.syncError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => QQMusicAuthDialog.show(context),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('配置', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _triggerSync,
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemExtent: 58.0,
              // 底部留白 = 底部导航栏(MediaQuery 抬升量)+ 迷你播放器。
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 96,
              ),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final song = favorites[index];
                return SongTile(
                  song: song,
                  contextQueue: favorites,
                  index: index,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    QQMusicFavoritesState qqState,
  ) {
    if (qqState.isSyncing) {
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

    if (qqState.isBound) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                qqState.syncError != null
                    ? Icons.cloud_off_rounded
                    : Icons.favorite_border_rounded,
                size: 60,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
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
                    onPressed: _triggerSync,
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 14),
            const Text(
              '接入 QQ 音乐「我喜欢」',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '绑定 QQ 号或「我喜欢」歌单链接，同步你的 QQ 音乐收藏\n自动关联本地无损音频，未下载曲目支持在线流式播放',
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
}
