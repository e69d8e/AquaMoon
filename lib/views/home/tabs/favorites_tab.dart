import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_toast.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/qq_music_provider.dart';
import '../../online_search/online_search_page.dart';
import '../../widgets/debounced_search_field.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/locate_playing_button.dart';
import '../../widgets/qq_music_auth_dialog.dart';
import '../../widgets/qq_music_sync_helpers.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/ui_helpers.dart';

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
    final qqMeta = ref.watch(
      qqMusicFavoritesProvider.select(
        (s) => (
          isBound: s.isBound,
          isSyncing: s.isSyncing,
          syncError: s.syncError,
          displayLabel: s.config.displayLabel,
          localMatchedCount: s.localMatchedCount,
        ),
      ),
    );
    // Only depend on the current song's id: full-object updates (e.g. the
    // syncSong broadcast after a favorite toggle) must not rebuild this page.
    final currentSongId = ref.watch(
      currentSongProvider.select((a) => a.valueOrNull?.id),
    );

    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;
    final isCurrentSongInList =
        currentSongId != null && favorites.any((s) => s.id == currentSongId);

    if (allFavorites.isEmpty) {
      return _buildEmptyState(context, theme, qqMeta);
    }

    return ResponsivePageContainer(
      child: Column(
        children: [
          // 搜索框与收藏概览 + 快捷播放操作合并进同一可折叠区。
          CollapsibleSection(
            animation: _searchBarAnimation,
            collapsed: _searchCollapsed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DebouncedSearchField(
                          key: _searchFieldKey,
                          initialQuery: searchQuery,
                          hintText: '搜索收藏歌曲、歌手、专辑...',
                          onQueryChanged: (val) {
                            ref
                                .read(favoritesSearchQueryProvider.notifier)
                                .state = val;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: appColors.favorite.withValues(alpha: 0.90),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSearching
                            ? '${favorites.length}/${allFavorites.length}'
                            : '${allFavorites.length}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
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
                              final shuffled = List<Song>.from(favorites)
                                ..shuffle();
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
                              if (!qqMeta.isSyncing) {
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
                                if (qqMeta.isBound) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'QQ音乐 · ${qqMeta.displayLabel}'
                                    '${qqMeta.localMatchedCount > 0 ? ' (本地 ${qqMeta.localMatchedCount})' : ''}',
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
                          if (qqMeta.isBound) ...[
                            PopupMenuItem(
                              value: 'qq_sync',
                              enabled: !qqMeta.isSyncing,
                              child: Row(
                                children: [
                                  if (qqMeta.isSyncing)
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
                                  Text(
                                    qqMeta.isSyncing ? '正在同步...' : '同步 QQ 音乐收藏',
                                  ),
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
                  if (favorites.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ActionPillButton(
                                  icon: Icons.play_arrow_rounded,
                                  label: '播放全部',
                                  filled: true,
                                  onTap: () => ref
                                      .read(audioControllerProvider)
                                      .playSong(
                                        favorites.first,
                                        queue: favorites,
                                      ),
                                ),
                                ActionPillButton(
                                  icon: Icons.shuffle_rounded,
                                  label: '随机',
                                  onTap: () {
                                    final shuffled = List<Song>.from(favorites)
                                      ..shuffle();
                                    ref
                                        .read(audioControllerProvider)
                                        .playSong(
                                          shuffled.first,
                                          queue: shuffled,
                                        );
                                  },
                                ),
                              ],
                            ),
                            if (qqMeta.isBound)
                              Semantics(
                                button: true,
                                enabled: !qqMeta.isSyncing,
                                label: qqMeta.isSyncing
                                    ? '正在同步云端收藏'
                                    : '同步云端 QQ 音乐收藏',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: qqMeta.isSyncing
                                      ? null
                                      : () => triggerQQMusicSync(context, ref),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 36,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(
                                              alpha: isLight ? 0.5 : 0.4,
                                            ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: appColors.subtleDivider,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (qqMeta.isSyncing)
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.8,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            )
                                          else
                                            Icon(
                                              Icons.sync_rounded,
                                              size: 14,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          const SizedBox(width: 5),
                                          Text(
                                            qqMeta.isSyncing ? '同步中' : '同步云端',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (qqMeta.syncError != null)
            QQMusicSyncErrorBanner(message: qqMeta.syncError!),

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
                      // 底部留白 = 底部导航栏(MediaQuery 抬升量)+ 迷你播放器。
                      padding: EdgeInsets.only(
                        top: 2,
                        bottom: MediaQuery.paddingOf(context).bottom + 104,
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
                    bottom: MediaQuery.paddingOf(context).bottom + 98,
                    child: LocatePlayingButton(
                      onPressed: () =>
                          _scrollToCurrentPlaying(currentSongId, favorites),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
    ({
      bool isBound,
      bool isSyncing,
      String? syncError,
      String displayLabel,
      int localMatchedCount,
    }) qqMeta,
  ) {
    if (qqMeta.isSyncing) {
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

    if (qqMeta.isBound) {
      return EmptyStateView(
        icon: qqMeta.syncError != null
            ? Icons.cloud_off_rounded
            : Icons.favorite_border_rounded,
        title: qqMeta.syncError != null ? '同步 QQ 音乐收藏遇到问题' : '「我喜欢」歌单暂无歌曲',
        subtitle:
            qqMeta.syncError ??
            '已连接 ${qqMeta.displayLabel}，可刷新同步或检查账号配置',
        actions: [
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
      );
    }

    return EmptyStateView(
      icon: Icons.favorite_border_rounded,
      title: '接入 QQ 音乐「我喜欢」',
      subtitle: '绑定 QQ 号或歌单链接同步你的收藏，自动关联本地无损音频，未下载曲目支持在线流式播放',
      actions: [
        FilledButton.icon(
          onPressed: () => QQMusicAuthDialog.show(context),
          icon: const Icon(Icons.add_link_rounded, size: 19),
          label: const Text('连接 QQ 音乐收藏'),
        ),
      ],
    );
  }
}
