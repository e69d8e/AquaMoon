import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/app_toast.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/playlist_provider.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_tile.dart';
import 'add_songs_to_playlist_dialog.dart';
import 'select_playlist_cover_dialog.dart';

class PlaylistDetailPage extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allPlaylists = ref.watch(playlistNotifierProvider);
    final currentPlaylist = allPlaylists.firstWhere(
      (p) => p.id == playlist.id,
      orElse: () => playlist,
    );

    final library = ref.watch(libraryNotifierProvider);
    final songMap = {for (final s in library.songs) s.id: s};

    final songs = currentPlaylist.songIds
        .map((id) => songMap[id])
        .whereType<Song>()
        .toList();

    final firstSongWithArt = songs.where((s) => s.albumArtUri != null && s.albumArtUri!.isNotEmpty).firstOrNull;
    final effectiveCoverArtUri = currentPlaylist.coverArtUri ?? firstSongWithArt?.albumArtUri;

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPlaylist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, size: 22),
            tooltip: '更换歌单封面',
            onPressed: () => SelectPlaylistCoverDialog.show(context, currentPlaylist),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded, size: 24),
            tooltip: '添加歌曲',
            onPressed: () => AddSongsToPlaylistDialog.show(context, currentPlaylist),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: '删除歌单',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Summary Card
          Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.18),
                  theme.colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Clickable Playlist Cover Artwork with Edit Badge
                Tooltip(
                  message: '点击更换歌单封面',
                  child: InkWell(
                    onTap: () => SelectPlaylistCoverDialog.show(context, currentPlaylist),
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        SongArtwork(
                          artUri: effectiveCoverArtUri,
                          size: 76,
                          borderRadius: 16,
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo_camera_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentPlaylist.name,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        currentPlaylist.description.isNotEmpty
                            ? currentPlaylist.description
                            : '共 ${songs.length} 首歌曲',
                        style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton.icon(
                            onPressed: songs.isEmpty
                                ? null
                                : () {
                                    ref.read(audioControllerProvider).playSong(songs.first, queue: songs);
                                  },
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('播放全部'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: songs.isEmpty
                                ? null
                                : () {
                                    final shuffled = List<Song>.from(songs)..shuffle();
                                    ref.read(audioControllerProvider).playSong(shuffled.first, queue: shuffled);
                                  },
                            icon: const Icon(Icons.shuffle_rounded, size: 17),
                            label: const Text('随机'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => AddSongsToPlaylistDialog.show(context, currentPlaylist),
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('添加歌曲'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Songs List
          Expanded(
            child: songs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.library_music_outlined,
                            size: 56,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '歌单暂无歌曲',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '您可以直接点击下方按钮从本地曲库添加歌曲',
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => AddSongsToPlaylistDialog.show(context, currentPlaylist),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('添加歌曲'),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return SongTile(
                        song: song,
                        contextQueue: songs,
                        index: index,
                        onSetAsPlaylistCover: () async {
                          await ref
                              .read(playlistNotifierProvider.notifier)
                              .setPlaylistCover(currentPlaylist.id, song.albumArtUri);
                          if (context.mounted) {
                            AppToast.show(
                              context,
                              '已将《${song.title}》封面设为歌单封面！',
                              icon: Icons.check_circle_rounded,
                            );
                          }
                        },
                        onDelete: () {
                          ref.read(playlistNotifierProvider.notifier).removeSongFromPlaylist(currentPlaylist.id, song.id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除歌单《${playlist.name}》吗？歌单内的本地歌曲不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(playlistNotifierProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
