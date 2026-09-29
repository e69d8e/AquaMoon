import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/playlist_provider.dart';
import '../widgets/song_artwork.dart';

class SelectPlaylistCoverDialog extends ConsumerStatefulWidget {
  final Playlist playlist;

  const SelectPlaylistCoverDialog({super.key, required this.playlist});

  static Future<void> show(BuildContext context, Playlist playlist) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectPlaylistCoverDialog(playlist: playlist),
    );
  }

  @override
  ConsumerState<SelectPlaylistCoverDialog> createState() =>
      _SelectPlaylistCoverDialogState();
}

class _SelectPlaylistCoverDialogState
    extends ConsumerState<SelectPlaylistCoverDialog> {
  bool _showAllLibrarySongs = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPlaylists = ref.watch(playlistNotifierProvider);
    final currentPlaylist = allPlaylists.firstWhere(
      (p) => p.id == widget.playlist.id,
      orElse: () => widget.playlist,
    );

    final libraryState = ref.watch(libraryNotifierProvider);
    final songMap = {for (final s in libraryState.songs) s.id: s};

    // Songs from current playlist
    final playlistSongs = currentPlaylist.songIds
        .map((id) => songMap[id])
        .whereType<Song>()
        .where((s) => s.albumArtUri != null && s.albumArtUri!.isNotEmpty)
        .toList();

    // All songs from library that have artwork
    final libraryArtworkSongs = libraryState.songs
        .where((s) => s.albumArtUri != null && s.albumArtUri!.isNotEmpty)
        .toList();

    final candidateSongs = _showAllLibrarySongs
        ? libraryArtworkSongs
        : playlistSongs;

    // Lift the sheet above the keyboard: the padding consumes the inset and
    // the fixed height gets clamped to the remaining space.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择歌单封面',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '点击选择任意歌曲的封面作为《${currentPlaylist.name}》的封面',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (currentPlaylist.coverArtUri != null)
                    TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('恢复默认'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        await ref
                            .read(playlistNotifierProvider.notifier)
                            .setPlaylistCover(currentPlaylist.id, null);
                        if (context.mounted) {
                          Navigator.pop(context);
                          AppToast.show(
                            context,
                            '已恢复默认歌单封面',
                            icon: Icons.check_circle_outline_rounded,
                          );
                        }
                      },
                    ),
                ],
              ),
            ),

            // Scope Switcher (Playlist Songs vs Entire Library)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('歌单内歌曲 (${playlistSongs.length})'),
                    selected: !_showAllLibrarySongs,
                    onSelected: (val) {
                      if (val) setState(() => _showAllLibrarySongs = false);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('全部曲库 (${libraryArtworkSongs.length})'),
                    selected: _showAllLibrarySongs,
                    onSelected: (val) {
                      if (val) setState(() => _showAllLibrarySongs = true);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Artwork Grid / List
            Expanded(
              child: candidateSongs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_not_supported_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              !_showAllLibrarySongs &&
                                      libraryArtworkSongs.isNotEmpty
                                  ? '当前歌单内暂无带封面的歌曲'
                                  : '曲库中暂无带封面的歌曲',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (!_showAllLibrarySongs &&
                                libraryArtworkSongs.isNotEmpty)
                              FilledButton.tonal(
                                onPressed: () =>
                                    setState(() => _showAllLibrarySongs = true),
                                child: const Text('从全部曲库选择'),
                              ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                      itemCount: candidateSongs.length,
                      itemBuilder: (context, index) {
                        final song = candidateSongs[index];
                        final isSelected =
                            currentPlaylist.coverArtUri == song.albumArtUri;

                        return InkWell(
                          onTap: () async {
                            await ref
                                .read(playlistNotifierProvider.notifier)
                                .setPlaylistCover(
                                  currentPlaylist.id,
                                  song.albumArtUri,
                                );

                            if (context.mounted) {
                              Navigator.pop(context);
                              AppToast.show(
                                context,
                                '已将《${song.title}》封面设为歌单封面！',
                                icon: Icons.check_circle_rounded,
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: SongArtwork(
                                          song: song,
                                          size: 120,
                                          borderRadius: 10,
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          right: 6,
                                          top: 6,
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
