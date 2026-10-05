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
    final favorites = ref.watch(favoritesSongsProvider);
    // Only depend on the current song's id: full-object updates (e.g. the
    // syncSong broadcast after a favorite toggle) must not rebuild this page.
    final currentSongId = ref.watch(
      currentSongProvider.select((a) => a.valueOrNull?.id),
    );

    final theme = Theme.of(context);
    final isCurrentSongInList =
        currentSongId != null && favorites.any((s) => s.id == currentSongId);

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
              '在播放页或歌曲菜单中点击红心即可收藏',
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
              // Playback actions live in one overflow menu to keep the
              // toolbar minimal.
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
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
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
      ],
    );
  }
}
