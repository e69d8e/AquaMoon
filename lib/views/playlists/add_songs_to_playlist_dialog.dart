import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/playlist_provider.dart';
import '../widgets/glass_container.dart';
import '../widgets/song_artwork.dart';
import '../widgets/ui_helpers.dart';

class AddSongsToPlaylistDialog extends ConsumerStatefulWidget {
  final Playlist playlist;

  const AddSongsToPlaylistDialog({super.key, required this.playlist});

  static Future<void> show(BuildContext context, Playlist playlist) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddSongsToPlaylistDialog(playlist: playlist),
    );
  }

  @override
  ConsumerState<AddSongsToPlaylistDialog> createState() =>
      _AddSongsToPlaylistDialogState();
}

enum _SongSource { library, favorites }

class _AddSongsToPlaylistDialogState
    extends ConsumerState<AddSongsToPlaylistDialog> {
  String _searchQuery = '';
  _SongSource _source = _SongSource.library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPlaylists = ref.watch(playlistNotifierProvider);
    final currentPlaylist = allPlaylists.firstWhere(
      (p) => p.id == widget.playlist.id,
      orElse: () => widget.playlist,
    );

    final librarySongs = ref.watch(
      libraryNotifierProvider.select((s) => s.songs),
    );
    final favoriteSongs = ref.watch(favoritesSongsProvider);
    final sourceSongs = _source == _SongSource.library
        ? librarySongs
        : favoriteSongs;

    final filteredSongs = _searchQuery.trim().isEmpty
        ? sourceSongs
        : sourceSongs.where((s) {
            final q = _searchQuery.trim().toLowerCase();
            return s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q);
          }).toList();

    final currentSongIds = currentPlaylist.songIds.toSet();

    // Lift the sheet above the keyboard: the padding consumes the inset and
    // the fixed height gets clamped to the remaining space.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: GlassContainer(
        enableBlur: false,
        height: MediaQuery.sizeOf(context).height * 0.85,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            ModalSheetHeader(
              title: Text(
                '添加歌曲到歌单',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                '《${currentPlaylist.name}》· 已包含 ${currentSongIds.length} 首',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailingActions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('完成'),
                ),
              ],
            ),

            // Source selector: local library or the full favorites list
            // (including QQ Music cloud favorites).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text('曲库 (${librarySongs.length})'),
                      selected: _source == _SongSource.library,
                      showCheckmark: false,
                      labelStyle: const TextStyle(fontSize: 12.5),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          setState(() => _source = _SongSource.library),
                    ),
                    ChoiceChip(
                      label: Text('收藏 (${favoriteSongs.length})'),
                      selected: _source == _SongSource.favorites,
                      showCheckmark: false,
                      labelStyle: const TextStyle(fontSize: 12.5),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          setState(() => _source = _SongSource.favorites),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                decoration: InputDecoration(
                  hintText: _source == _SongSource.library
                      ? '搜索曲库中的歌曲、歌手...'
                      : '搜索收藏中的歌曲、歌手...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.85,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          tooltip: '清除搜索',
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 40,
                          ),
                          onPressed: () => setState(() => _searchQuery = ''),
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
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),

            // Song List
            Expanded(
              child: sourceSongs.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _source == _SongSource.library
                                  ? Icons.music_off_rounded
                                  : Icons.favorite_border_rounded,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _source == _SongSource.library
                                  ? '曲库暂无本地歌曲'
                                  : '收藏暂无歌曲',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _source == _SongSource.library
                                  ? '请先在曲库或设置中导入本地音乐'
                                  : '在收藏页点亮红心或接入 QQ 音乐收藏后再来添加',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filteredSongs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          '未找到与「$_searchQuery」匹配的歌曲',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      itemCount: filteredSongs.length,
                      itemBuilder: (context, index) {
                        final song = filteredSongs[index];
                        final isInPlaylist = currentSongIds.contains(song.id);

                        return Material(
                          color: isInPlaylist
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.08,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () async {
                              final added = await ref
                                  .read(playlistNotifierProvider.notifier)
                                  .toggleSongInPlaylist(
                                    currentPlaylist.id,
                                    song.id,
                                  );

                              if (context.mounted) {
                                AppToast.show(
                                  context,
                                  added
                                      ? '已添加《${song.title}》到歌单'
                                      : '已从歌单移除《${song.title}》',
                                  icon: added
                                      ? Icons.playlist_add_check_rounded
                                      : Icons.playlist_remove_rounded,
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 6.0,
                              ),
                              child: Row(
                                children: [
                                  SongArtwork(
                                    song: song,
                                    size: 42,
                                    borderRadius: 8,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isInPlaylist
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isInPlaylist
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          song.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                                  const SizedBox(width: 8),
                                  Text(
                                    Formatters.formatDuration(song.duration),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      isInPlaylist
                                          ? Icons.check_circle_rounded
                                          : Icons.add_circle_outline_rounded,
                                      key: ValueKey(isInPlaylist),
                                      color: isInPlaylist
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.5),
                                      size: 22,
                                    ),
                                  ),
                                ],
                              ),
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
