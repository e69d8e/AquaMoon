import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_toast.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/library_provider.dart';
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
      final targetOffset = (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
      final clamped = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);

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
    final libraryState = ref.watch(libraryNotifierProvider);
    final songs = ref.watch(filteredSongsProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final sortType = ref.watch(sortTypeProvider);
    final sortAscending = ref.watch(sortAscendingProvider);
    final currentSongAsync = ref.watch(currentSongProvider);
    final currentSong = currentSongAsync.valueOrNull;

    final theme = Theme.of(context);
    final isCurrentSongInList = currentSong != null && songs.any((s) => s.id == currentSong.id);

    return Column(
      children: [
        // Top Search & Sort Action Row (Clean & Minimal)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索音乐、歌手、专辑...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => ref.read(searchQueryProvider.notifier).state = '',
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => ref.read(searchQueryProvider.notifier).state = val,
                ),
              ),
              const SizedBox(width: 4),

              // Sort Menu Button
              PopupMenuButton<SongSortType>(
                icon: Icon(
                  Icons.sort_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
                tooltip: '排序方式',
                initialValue: sortType,
                onSelected: (type) {
                  if (sortType == type) {
                    ref.read(sortAscendingProvider.notifier).state = !sortAscending;
                  } else {
                    ref.read(sortTypeProvider.notifier).state = type;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: SongSortType.dateAdded, child: Text('按添加时间')),
                  const PopupMenuItem(value: SongSortType.playCount, child: Text('按播放次数')),
                  const PopupMenuItem(value: SongSortType.title, child: Text('按歌曲名称')),
                  const PopupMenuItem(value: SongSortType.artist, child: Text('按歌手名字')),
                  const PopupMenuItem(value: SongSortType.duration, child: Text('按歌曲时长')),
                ],
              ),
            ],
          ),
        ),

        // Subheader Action Row: Icon count on left, locate & play all on right (clean & icon-driven)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            children: [
              // Icon + Count (replacing '全部歌曲' text with icon)
              Icon(
                Icons.music_note_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                '${songs.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
              const Spacer(),
              if (isCurrentSongInList)
                IconButton(
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  tooltip: '定位当前播放',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _scrollToCurrentPlaying(currentSong.id, songs),
                ),
              if (songs.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: '播放全部',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    ref.read(audioControllerProvider).playSong(songs.first, queue: songs);
                  },
                ),
            ],
          ),
        ),

        // Scanning Indicator Bar
        if (libraryState.isScanning)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
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
                        libraryState.scanProgressText ?? '正在处理...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (libraryState.scanProgressPercent != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: libraryState.scanProgressPercent),
                ],
              ],
            ),
          ),

        // Songs List
        Expanded(
          child: songs.isEmpty
              ? _buildEmptyState(context, ref, searchQuery.isNotEmpty)
              : ListView.builder(
                  controller: _scrollController,
                  itemExtent: 58.0,
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return SongTile(
                      song: song,
                      contextQueue: songs,
                      index: index,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, bool isSearching) {
    final theme = Theme.of(context);
    final searchQuery = ref.watch(searchQueryProvider);
    if (isSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 56, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
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
                      builder: (_) => OnlineSearchPage(initialQuery: searchQuery),
                    ),
                  );
                },
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: Text('全网在线检索「$searchQuery」'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => ref.read(libraryNotifierProvider.notifier).importFiles(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加本地歌曲'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
