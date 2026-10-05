import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_toast.dart';
import '../../../models/playlist.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../online_search/online_search_page.dart';
import '../../settings/settings_page.dart';
import '../../widgets/song_tile.dart';

class AllSongsTab extends ConsumerStatefulWidget {
  const AllSongsTab({super.key});

  @override
  ConsumerState<AllSongsTab> createState() => _AllSongsTabState();
}

class _AllSongsTabState extends ConsumerState<AllSongsTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _enterSelectionMode(String songId) {
    setState(() => _selectedIds.add(songId));
  }

  void _exitSelectionMode() {
    setState(() => _selectedIds.clear());
  }

  void _toggleSelection(String songId) {
    setState(() {
      if (!_selectedIds.remove(songId)) _selectedIds.add(songId);
      // 取消到空时自然退出多选模式。
    });
  }

  void _selectAll(List<Song> songs) {
    setState(() {
      for (final song in songs) {
        _selectedIds.add(song.id);
      }
    });
  }

  Future<void> _batchDelete(List<Song> songs) async {
    final selected = songs
        .where((s) => _selectedIds.contains(s.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量移除'),
        content: Text(
          '确定将 ${selected.length} 首歌曲从曲库移除吗？\n\n提示：设备中的本地原音频文件不会被删除。',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final library = ref.read(libraryNotifierProvider.notifier);
    final count = await library.deleteSongsByIds([
      for (final s in selected) s.id,
    ]);
    if (mounted) {
      AppToast.show(
        context,
        '已从曲库移除 $count 首歌曲',
        icon: Icons.delete_sweep_rounded,
      );
      _exitSelectionMode();
    }
  }

  Future<void> _batchFavorite(List<Song> songs, bool favorite) async {
    final library = ref.read(libraryNotifierProvider.notifier);
    final count = await library.setFavorites(_selectedIds.toList(), favorite);
    if (mounted) {
      AppToast.show(
        context,
        favorite ? '已收藏 $count 首歌曲' : '已取消收藏 $count 首歌曲',
        icon: favorite
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
      );
      _exitSelectionMode();
    }
  }

  Future<void> _batchAddToPlaylist() async {
    final playlists = ref.read(playlistNotifierProvider);
    final selectedIds = _selectedIds.toList();
    if (playlists.isEmpty || selectedIds.isEmpty) {
      AppToast.show(
        context,
        playlists.isEmpty ? '暂无自定义歌单，请先在歌单页面创建！' : '未选中歌曲',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    final chosen = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('将 ${selectedIds.length} 首歌添加到歌单'),
        content: SizedBox(
          width: 300,
          height: 280,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (c, i) {
              final pl = playlists[i];
              return ListTile(
                title: Text(pl.name),
                subtitle: Text('${pl.songIds.length} 首歌曲'),
                trailing: const Icon(Icons.add_circle_outline_rounded),
                onTap: () => Navigator.pop(ctx, pl),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (chosen is! Playlist || !mounted) return;
    final playlistNotifier = ref.read(playlistNotifierProvider.notifier);
    await playlistNotifier.addSongsToPlaylist(chosen.id, selectedIds);
    if (mounted) {
      AppToast.show(
        context,
        '已添加 ${selectedIds.length} 首歌曲到《${chosen.name}》',
        icon: Icons.playlist_add_check_rounded,
      );
      _exitSelectionMode();
    }
  }

  @override
  void initState() {
    super.initState();
    // searchQueryProvider outlives this State (tab switches, desktop layout
    // toggle): restore it into the fresh field, otherwise a cancelled-look
    // empty search box would keep filtering with no visible way to reset it.
    _searchController.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 多选模式下的顶部操作栏：全选、批量收藏、加入歌单、批量移除、退出。
  Widget _buildSelectionBar(BuildContext context, List<Song> songs) {
    final theme = Theme.of(context);
    final selectedCount = _selectedIds.length;
    final selectedSongs = songs
        .where((s) => _selectedIds.contains(s.id))
        .toList(growable: false);
    final allFavorite =
        selectedSongs.isNotEmpty && selectedSongs.every((s) => s.isFavorite);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: '退出多选',
            visualDensity: VisualDensity.compact,
            onPressed: _exitSelectionMode,
          ),
          Text(
            '已选 $selectedCount 首',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.select_all_rounded, size: 20),
            tooltip: '全选',
            visualDensity: VisualDensity.compact,
            onPressed: songs.isEmpty ? null : () => _selectAll(songs),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              allFavorite
                  ? Icons.favorite_border_rounded
                  : Icons.favorite_rounded,
              size: 20,
              color: allFavorite ? null : Colors.redAccent,
            ),
            tooltip: allFavorite ? '批量取消收藏' : '批量收藏',
            visualDensity: VisualDensity.compact,
            onPressed: selectedSongs.isEmpty
                ? null
                : () => _batchFavorite(songs, !allFavorite),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded, size: 20),
            tooltip: '添加到歌单',
            visualDensity: VisualDensity.compact,
            onPressed: selectedSongs.isEmpty ? null : _batchAddToPlaylist,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: Colors.redAccent,
            ),
            tooltip: '从曲库移除',
            visualDensity: VisualDensity.compact,
            onPressed: selectedSongs.isEmpty
                ? null
                : () => _batchDelete(songs),
          ),
        ],
      ),
    );
  }

  /// Cancels the active search: text, filter and IME session all at once.
  /// Unfocusing first closes the input connection, so an in-flight IME
  /// composition commit cannot re-insert the just-cleared query afterwards.
  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
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

  PopupMenuItem<String> _buildSortItem(
    SongSortType type,
    String label,
    SongSortType currentType,
    bool ascending,
  ) {
    final theme = Theme.of(context);
    final isActive = currentType == type;
    return PopupMenuItem<String>(
      value: 'sort_${type.name}',
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: isActive
                ? Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  )
                : null,
          ),
          Text(label),
          const Spacer(),
          if (isActive)
            Icon(
              ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  /// Single dispatcher for the unified library menu: 'sort_*' values toggle
  /// the sort field (tap again to flip direction), the rest are actions.
  void _handleMenuSelection(String value, List<Song> songs) {
    if (value.startsWith('sort_')) {
      final type = SongSortType.values.firstWhere(
        (t) => 'sort_${t.name}' == value,
      );
      if (ref.read(sortTypeProvider) == type) {
        ref.read(sortAscendingProvider.notifier).state =
            !ref.read(sortAscendingProvider);
      } else {
        ref.read(sortTypeProvider.notifier).state = type;
      }
      return;
    }

    switch (value) {
      case 'play_all':
        ref.read(audioControllerProvider).playSong(songs.first, queue: songs);
        break;
      case 'play_shuffled':
        final shuffled = List<Song>.from(songs)..shuffle();
        ref
            .read(audioControllerProvider)
            .playSong(shuffled.first, queue: shuffled);
        break;
      case 'locate':
        final currentSongId = ref
            .read(currentSongProvider)
            .valueOrNull
            ?.id;
        if (currentSongId != null) {
          _scrollToCurrentPlaying(currentSongId, songs);
        }
        break;
      case 'multi_select':
        if (songs.isNotEmpty) _enterSelectionMode(songs.first.id);
        break;
      case 'rescan':
        _rescanLibrary();
        break;
    }
  }

  Future<void> _rescanLibrary() async {
    try {
      final count = await ref
          .read(libraryNotifierProvider.notifier)
          .scanSystemMusicDirectory();
      if (mounted && count == 0) {
        AppToast.show(context, '未发现新歌曲', icon: Icons.done_all_rounded);
      }
    } on StoragePermissionDeniedException {
      if (mounted) {
        AppToast.show(
          context,
          '存储权限未授予，无法扫描',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Select individual scan fields instead of watching the whole LibraryState
    // so the progress updates during a scan don't rebuild the entire list.
    final isScanning = ref.watch(
      libraryNotifierProvider.select((s) => s.isScanning),
    );
    final scanProgressText = ref.watch(
      libraryNotifierProvider.select((s) => s.scanProgressText),
    );
    final scanProgressPercent = ref.watch(
      libraryNotifierProvider.select((s) => s.scanProgressPercent),
    );
    final songs = ref.watch(filteredSongsProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final sortType = ref.watch(sortTypeProvider);
    final sortAscending = ref.watch(sortAscendingProvider);
    final currentSongId = ref.watch(
      currentSongProvider.select((a) => a.valueOrNull?.id),
    );

    final theme = Theme.of(context);
    final isCurrentSongInList =
        currentSongId != null && songs.any((s) => s.id == currentSongId);

    return Column(
      children: [
        // Top Search & Sort Action Row (Clean & Minimal); swapped for the
        // batch-selection toolbar while a multi-select is in progress.
        if (_selectionMode)
          _buildSelectionBar(context, songs)
        else
          Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Expanded(
                // Listen to the controller locally so keystrokes only rebuild
                // the field (suffix icon visibility), not the whole tab — the
                // clear button must be tappable the moment text exists, not
                // only after the debounce has settled.
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: '搜索音乐、歌手、专辑...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.65,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: value.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: _clearSearch,
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () {
                            if (mounted) {
                              ref.read(searchQueryProvider.notifier).state =
                                  val;
                            }
                          },
                        );
                      },
                      // Flutter's default leaves touch taps outside the field
                      // focused on mobile, so the IME stays attached and gets
                      // re-summoned every time a menu or page hands focus
                      // back. Any other operation should end input mode for
                      // good — unfocus on every outside tap, all platforms.
                      onTapOutside: (_) => _searchFocusNode.unfocus(),
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),

              // Unified overflow menu: count header, playback actions, rescan
              // and sorting — keeps the toolbar to search + one button.
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.8,
                  ),
                ),
                tooltip: '排序与更多操作',
                position: PopupMenuPosition.under,
                onSelected: (value) => _handleMenuSelection(value, songs),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Text(
                      searchQuery.isNotEmpty
                          ? '匹配到 ${songs.length} 首'
                          : '曲库共 ${songs.length} 首',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  if (songs.isNotEmpty) ...[
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
                  if (songs.isNotEmpty)
                    const PopupMenuItem(
                      value: 'multi_select',
                      child: Row(
                        children: [
                          Icon(Icons.checklist_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('批量管理（多选）'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'rescan',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('重新扫描曲库'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  _buildSortItem(
                    SongSortType.dateAdded,
                    '按添加时间',
                    sortType,
                    sortAscending,
                  ),
                  _buildSortItem(
                    SongSortType.playCount,
                    '按播放次数',
                    sortType,
                    sortAscending,
                  ),
                  _buildSortItem(
                    SongSortType.title,
                    '按歌曲名称',
                    sortType,
                    sortAscending,
                  ),
                  _buildSortItem(
                    SongSortType.artist,
                    '按歌手名字',
                    sortType,
                    sortAscending,
                  ),
                  _buildSortItem(
                    SongSortType.duration,
                    '按歌曲时长',
                    sortType,
                    sortAscending,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Scanning Indicator Bar
        if (isScanning)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scanProgressText ?? '正在处理...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (scanProgressPercent != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: scanProgressPercent),
                ],
              ],
            ),
          ),

        // Songs List
        Expanded(
          child: songs.isEmpty
              ? _buildEmptyState(context, ref, searchQuery.isNotEmpty)
              : RefreshIndicator(
                  onRefresh: _rescanLibrary,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemExtent: 58.0,
                    // 底部留白 = 底部导航栏(MediaQuery 抬升量)+ 迷你播放器。
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 96,
                    ),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return SongTile(
                        song: song,
                        contextQueue: songs,
                        index: index,
                        selectionMode: _selectionMode,
                        isSelected: _selectedIds.contains(song.id),
                        onSelectionToggle: () => _toggleSelection(song.id),
                        onLongPress: () => _enterSelectionMode(song.id),
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
    WidgetRef ref,
    bool isSearching,
  ) {
    final theme = Theme.of(context);
    final searchQuery = ref.watch(searchQueryProvider);
    if (isSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '本地曲库中未找到「$searchQuery」相关歌曲',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          OnlineSearchPage(initialQuery: searchQuery),
                    ),
                  );
                },
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: Text('全网在线检索「$searchQuery」'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              '曲库暂无音乐',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '可在右上角「设置」中管理导入，或点击下方直接添加',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(libraryNotifierProvider.notifier).importFiles(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加本地歌曲'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('进入设置'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
