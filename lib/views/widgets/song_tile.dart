import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/qq_music_provider.dart';
import 'edit_song_dialog.dart';
import 'local_song_link_dialog.dart';
import 'online_candidate_dialog.dart';
import 'song_artwork.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final List<Song>? contextQueue;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onSetAsPlaylistCover;

  /// 多选模式：点击行为切换为勾选/取消勾选，长按由外层列表接管。
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;
  final VoidCallback? onLongPress;

  const SongTile({
    super.key,
    required this.song,
    this.contextQueue,
    this.index,
    this.onTap,
    this.onDelete,
    this.onSetAsPlaylistCover,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(
      currentSongProvider.select((s) => s.valueOrNull?.id == song.id),
    );
    final isPlaying = isCurrent
        ? ref.watch(
            playbackStateStreamProvider.select(
              (s) => s.valueOrNull?.playing ?? false,
            ),
          )
        : false;

    final theme = Theme.of(context);
    // 只依赖 isBound 这一个 bool，避免云端同步引发整个列表重建。
    // 未注入 storageService 时（如纯渲染的 widget 测试）降级为未绑定，
    // 与 qq_music_provider 里对 audioHandlerProvider 的处理保持一致。
    var isQQBound = false;
    try {
      isQQBound = ref.watch(
        qqMusicFavoritesProvider.select((s) => s.isBound),
      );
    } catch (_) {}
    final hasQqMid = song.qqSongMid != null && song.qqSongMid!.isNotEmpty;

    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.14)
          : isCurrent
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: selectionMode
            ? onSelectionToggle
            : onTap ??
                  () {
                    ref
                        .read(audioControllerProvider)
                        .playSong(song, queue: contextQueue);
                  },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Row(
            children: [
              if (selectionMode) ...[
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                ),
                const SizedBox(width: 10),
              ],
              SongArtwork(song: song, size: 44, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          Icon(
                            isPlaying
                                ? Icons.equalizer_rounded
                                : Icons.pause_circle_filled_rounded,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (song.qqSongMid != null &&
                            song.qqSongMid!.isNotEmpty) ...[
                          _buildSourceBadge(
                            theme,
                            label: song.hasLocalFile ? '本地' : 'QQ音乐',
                            isLocal: song.hasLocalFile,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (song.isVip && song.isQQMusicOnline) ...[
                          _buildVipBadge(theme),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            song.album.isNotEmpty &&
                                    song.album != song.title &&
                                    song.album != song.artist
                                ? '${song.artist} · ${song.album}'
                                : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (song.playCount > 0) ...[
                Icon(
                  Icons.play_arrow_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                Text(
                  '${song.playCount}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                Formatters.formatDuration(song.duration),
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              if (selectionMode)
                const SizedBox(width: 26)
              else
                // Favorite toggle and all other per-song operations live in
                // the overflow menu so each row carries a single trailing
                // control.
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 32,
                  ),
                  onSelected: (action) => _handleAction(context, ref, action),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle_favorite',
                      child: Row(
                        children: [
                          Icon(
                            song.isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: song.isFavorite ? Colors.redAccent : null,
                          ),
                          const SizedBox(width: 8),
                          Text(song.isFavorite ? '取消收藏' : '收藏'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'play_next',
                      child: Row(
                        children: [
                          Icon(Icons.queue_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('下一首播放'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_to_playlist',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('添加到歌单'),
                        ],
                      ),
                    ),
                  if (onSetAsPlaylistCover != null)
                    const PopupMenuItem(
                      value: 'set_as_cover',
                      child: Row(
                        children: [
                          Icon(Icons.image_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('设为歌单封面'),
                        ],
                      ),
                    ),
                  if (!song.isQQMusicOnline)
                    const PopupMenuItem(
                      value: 'edit_song',
                      child: Row(
                        children: [
                          Icon(Icons.edit_note_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('编辑歌曲信息'),
                        ],
                      ),
                    ),
                  // 云端曲目没匹配到本地文件时，允许用户自己指定
                  if (isQQBound && !song.hasLocalFile && hasQqMid)
                    const PopupMenuItem(
                      value: 'link_local_song',
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('关联本地音频'),
                        ],
                      ),
                    ),
                  if (isQQBound && song.hasLocalFile && hasQqMid)
                    const PopupMenuItem(
                      value: 'unlink_local_song',
                      child: Row(
                        children: [
                          Icon(Icons.link_off_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('取消本地关联'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'online_candidate_select',
                    child: Row(
                      children: [
                        Icon(Icons.saved_search_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('在线检索歌曲信息'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'fetch_online_metadata',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_download_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('智能补齐歌词与封面'),
                      ],
                    ),
                  ),
                  if (!song.isQQMusicOnline || onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '从曲库移除',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(
    ThemeData theme, {
    required String label,
    required bool isLocal,
  }) {
    final badgeColor = isLocal ? theme.colorScheme.primary : Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3.5),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.35),
          width: 0.6,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: badgeColor,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildVipBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(3.5),
        border: Border.all(
          color: Colors.amber.shade700.withValues(alpha: 0.45),
          width: 0.6,
        ),
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: Colors.amber.shade800,
          height: 1.2,
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'link_local_song':
        final message = await LocalSongLinkDialog.show(context, song);
        if (context.mounted && message != null && message.isNotEmpty) {
          AppToast.show(context, message, icon: Icons.link_rounded);
        }
        break;
      case 'unlink_local_song':
        final message = await ref
            .read(qqMusicFavoritesProvider.notifier)
            .unlinkLocalSong(song);
        if (context.mounted) {
          AppToast.show(context, message, icon: Icons.link_off_rounded);
        }
        break;
      case 'toggle_favorite':
        final res = await ref
            .read(qqMusicFavoritesProvider.notifier)
            .toggleFavorite(song);
        if (context.mounted && res.toastMessage != null) {
          AppToast.show(
            context,
            res.toastMessage!,
            icon: res.isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          );
        }
        break;
      case 'play_next':
        await ref.read(audioControllerProvider).playNext(song);
        if (context.mounted) {
          AppToast.show(
            context,
            '已加入下一首播放：《${song.title}》',
            icon: Icons.queue_rounded,
          );
        }
        break;
      case 'set_as_cover':
        onSetAsPlaylistCover?.call();
        break;
      case 'edit_song':
        EditSongDialog.show(context, song);
        break;
      case 'add_to_playlist':
        _showAddToPlaylistDialog(context, ref);
        break;
      case 'online_candidate_select':
        final selected = await OnlineCandidateSelectDialog.show(context, song);
        if (selected != null) {
          // The tile can be disposed while the cover downloads (list scroll /
          // navigation) — capture what we need before the first await and
          // bail out instead of touching `ref` on a dead widget.
          final library = ref.read(libraryNotifierProvider.notifier);
          final onlineService = ref.read(onlineMetadataServiceProvider);
          String? newArtUri = song.albumArtUri;
          if (selected.coverUrl != null && selected.coverUrl!.isNotEmpty) {
            newArtUri = await onlineService.cacheOnlineImage(
              selected.coverUrl!,
            );
          }
          final newLrc = selected.syncedLyrics ?? selected.plainLyrics;

          final applied = await library.updateSongMerged(song.id, (current) {
            return current.copyWith(
              title: selected.title,
              artist: selected.artist,
              album: selected.album.isNotEmpty ? selected.album : current.album,
              albumArtUri: newArtUri,
              lrcContent: newLrc,
            );
          });
          if (applied == null || !context.mounted) break;
          final updated = applied;

          final currentSong = ref.read(currentSongProvider).valueOrNull;
          if (currentSong != null && currentSong.id == updated.id) {
            ref
                .read(audioHandlerProvider)
                .updateCurrentSongMetadata(
                  title: updated.title,
                  artist: updated.artist,
                  album: updated.album,
                  albumArtUri: updated.albumArtUri,
                  lrcContent: updated.lrcContent,
                );
            ref
                .read(lyricsNotifierProvider.notifier)
                .loadLyricsForSong(updated);
          }

          AppToast.show(
            context,
            '已应用来自 ${selected.source} 的《${selected.title}》元数据！',
            icon: Icons.check_circle_outline_rounded,
          );
        }
        break;
      case 'fetch_online_metadata':
        AppToast.show(
          context,
          '正在匹配《${song.title}》在线信息...',
          icon: Icons.sync_rounded,
        );
        final error = await ref
            .read(lyricsNotifierProvider.notifier)
            .loadLyricsForSong(song, forceOnline: true);
        if (context.mounted) {
          AppToast.show(
            context,
            error != null ? '在线匹配失败：$error' : '在线信息匹配完成！',
            icon: error != null
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
          );
        }
        break;
      case 'delete':
        if (onDelete != null) {
          onDelete!();
        } else {
          _confirmDeleteFromLibrary(context, ref);
        }
        break;
    }
  }

  void _confirmDeleteFromLibrary(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('从曲库移除'),
          ],
        ),
        content: Text(
          '确定将《${song.title}》从曲库移除吗？\n\n提示：设备中的本地原音频文件不会被删除。',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(libraryNotifierProvider.notifier).deleteSong(song);
              AppToast.show(
                context,
                '已从曲库移除《${song.title}》',
                icon: Icons.delete_sweep_rounded,
              );
            },
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref) {
    final playlists = ref.read(playlistNotifierProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加到歌单'),
        content: playlists.isEmpty
            ? const Text('暂无自定义歌单，请先在歌单页面创建！')
            : SizedBox(
                width: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (c, i) {
                    final pl = playlists[i];
                    final contains = pl.songIds.contains(song.id);
                    return ListTile(
                      title: Text(pl.name),
                      subtitle: Text('${pl.songIds.length} 首歌曲'),
                      trailing: contains
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                            )
                          : const Icon(Icons.add_circle_outline_rounded),
                      onTap: () {
                        if (!contains) {
                          ref
                              .read(playlistNotifierProvider.notifier)
                              .addSongToPlaylist(pl.id, song.id);
                          Navigator.pop(ctx);
                          AppToast.show(
                            context,
                            '已添加到《${pl.name}》',
                            icon: Icons.playlist_add_check_rounded,
                          );
                        }
                      },
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
  }
}
