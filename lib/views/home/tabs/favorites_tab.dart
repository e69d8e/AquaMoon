import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_toast.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/playlist_provider.dart';
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
      const itemHeight = 68.0;
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
    final favorites = ref.watch(favoritesSongsProvider);
    final currentSongAsync = ref.watch(currentSongProvider);
    final currentSong = currentSongAsync.valueOrNull;

    final theme = Theme.of(context);
    final isCurrentSongInList = currentSong != null && favorites.any((s) => s.id == currentSong.id);

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有收藏的歌曲',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '在曲目列表中点击红心图标即可收藏',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Action Header (Minimal & Icon-driven)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 16,
                color: Colors.redAccent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 4),
              Text(
                '${favorites.length}',
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
                  onPressed: () => _scrollToCurrentPlaying(currentSong.id, favorites),
                ),
              IconButton(
                icon: const Icon(Icons.shuffle_rounded, size: 19),
                tooltip: '随机播放',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  final shuffled = List<Song>.from(favorites)..shuffle();
                  ref.read(audioControllerProvider).playSong(shuffled.first, queue: shuffled);
                },
              ),
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
                  ref.read(audioControllerProvider).playSong(favorites.first, queue: favorites);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 120),
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
      ],
    );
  }
}
