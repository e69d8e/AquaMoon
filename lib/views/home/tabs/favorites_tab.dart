import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_toast.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/qq_music_provider.dart';
import '../../online_search/online_search_page.dart';
import '../../widgets/debounced_search_field.dart';
import '../../widgets/locate_playing_button.dart';
import '../../widgets/qq_music_auth_dialog.dart';
import '../../widgets/qq_music_sync_helpers.dart';
import '../../widgets/song_tile.dart';

class FavoritesTab extends ConsumerStatefulWidget {
  const FavoritesTab({super.key});

  @override
  ConsumerState<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<FavoritesTab>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<DebouncedSearchFieldState> _searchFieldKey = GlobalKey();

  /// 列表向前滚动时收起搜索框，回滑或回到顶部时恢复；
  /// 搜索框 State 始终保留在树中，不会丢失输入内容与焦点。
  late final AnimationController _searchBarController;
  late final CurvedAnimation _searchBarAnimation;
  bool _searchCollapsed = false;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _searchBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _searchBarAnimation = CurvedAnimation(
      parent: _searchBarController,
      curve: Curves.easeOutCubic,
    );
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _searchBarAnimation.dispose();
    _searchBarController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 12) {
      _setSearchCollapsed(false);
    } else if (delta > 6 && offset > 24) {
      _setSearchCollapsed(true);
    } else if (delta < -6) {
      _setSearchCollapsed(false);
    }
  }

  void _setSearchCollapsed(bool collapsed) {
    if (_searchCollapsed == collapsed) return;
    _searchCollapsed = collapsed;
    if (collapsed) {
      _searchBarController.reverse();
    } else {
      _searchBarController.forward();
    }
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

  @override
  Widget build(BuildContext context) {
    final allFavorites = ref.watch(favoritesSongsProvider);
    final favorites = ref.watch(filteredFavoritesSongsProvider);
    final searchQuery = ref.watch(favoritesSearchQueryProvider);
    final trimmedQuery = searchQuery.trim();
    final isSearching = trimmedQuery.isNotEmpty;
    final qqState = ref.watch(qqMusicFavoritesProvider);
    // Only depend on the current song's id: full-object updates (e.g. the
    // syncSong broadcast after a favorite toggle) must not rebuild this page.
    final currentSongId = ref.watch(
      currentSongProvider.select((a) => a.valueOrNull?.id),
    );

    final theme = Theme.of(context);
    final isCurrentSongInList =
        currentSongId != null && favorites.any((s) => s.id == currentSongId);

    if (allFavorites.isEmpty) {
      return _buildEmptyState(context, theme, qqState);
    }

    return Column(
      children: [
        // 搜索框与收藏概览合并为一行：数量保持可见，QQ 同步、账号
        // 与播放操作全部收进右侧菜单，不再占用搜索框上方的空间。
        SizeTransition(
          sizeFactor: _searchBarAnimation,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: DebouncedSearchField(
                    key: _searchFieldKey,
                    initialQuery: searchQuery,
                    hintText: '搜索收藏歌曲、歌手、专辑...',
                    onQueryChanged: (val) {
                      ref.read(favoritesSearchQueryProvider.notifier).state =
                          val;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.favorite_rounded,
                  size: 14,
                  color: theme.colorScheme.primary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 3),
                Text(
                  isSearching
                      ? '${favorites.length}/${allFavorites.length}'
                      : '${allFavorites.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.8,
                    ),
                  ),
                  tooltip: '收藏操作',
                  position: PopupMenuPosition.under,
                  onSelected: (value) {
                    switch (value) {
                      case 'play_all':
                        if (favorites.isEmpty) return;
                        ref
                            .read(audioControllerProvider)
                            .playSong(favorites.first, queue: favorites);
                        break;
                      case 'play_shuffled':
                        if (favorites.isEmpty) return;
                        final shuffled = List<Song>.from(favorites)..shuffle();
                        ref
                            .read(audioControllerProvider)
                            .playSong(shuffled.first, queue: shuffled);
                        break;
                      case 'locate':
                        if (currentSongId != null) {
                          _scrollToCurrentPlaying(currentSongId, favorites);
                        }
                        break;
                      case 'qq_sync':
                        if (!qqState.isSyncing) {
                          triggerQQMusicSync(context, ref);
                        }
                        break;
                      case 'qq_account':
                      case 'qq_connect':
                        QQMusicAuthDialog.show(context);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSearching
                                ? '匹配到 ${favorites.length} 首 / 共 ${allFavorites.length} 首'
                                : '收藏共 ${allFavorites.length} 首',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (qqState.isBound) ...[
                            const SizedBox(height: 2),
                            Text(
                              'QQ音乐 · ${qqState.config.displayLabel}'
                              '${qqState.localMatchedCount > 0 ? ' (本地 ${qqState.localMatchedCount})' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    if (favorites.isNotEmpty) ...[
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
                    ],
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
                    if (qqState.isBound) ...[
                      PopupMenuItem(
                        value: 'qq_sync',
                        enabled: !qqState.isSyncing,
                        child: Row(
                          children: [
                            if (qqState.isSyncing)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const Icon(Icons.sync_rounded, size: 18),
                            const SizedBox(width: 10),
                            Text(qqState.isSyncing ? '正在同步...' : '同步 QQ 音乐收藏'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'qq_account',
                        child: Row(
                          children: [
                            Icon(Icons.account_circle_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('QQ 音乐账号配置'),
                          ],
                        ),
                      ),
                    ] else
                      const PopupMenuItem(
                        value: 'qq_connect',
                        child: Row(
                          children: [
                            Icon(Icons.add_link_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('接入 QQ 音乐收藏'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (qqState.syncError != null)
          QQMusicSyncErrorBanner(message: qqState.syncError!),

        Expanded(
          child: Stack(
            children: [
              if (favorites.isEmpty)
                _buildSearchEmptyState(context, theme, trimmedQuery)
              else
                RefreshIndicator(
                  onRefresh: () => triggerQQMusicSync(context, ref),
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
              if (isCurrentSongInList)
                Positioned(
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 96,
                  child: LocatePlayingButton(
                    onPressed: () =>
                        _scrollToCurrentPlaying(currentSongId, favorites),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchEmptyState(
    BuildContext context,
    ThemeData theme,
    String query,
  ) {
    return SongSearchEmptyState(
      message: '收藏中未找到「$query」相关歌曲',
      onClearSearch: () => _searchFieldKey.currentState?.clear(),
      onSecondaryAction: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OnlineSearchPage(initialQuery: query),
          ),
        );
      },
      secondaryLabel: '全网在线检索「$query」',
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
