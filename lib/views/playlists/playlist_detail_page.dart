import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../services/file_export_service.dart';
import '../player/mini_player.dart';
import '../widgets/empty_state_view.dart';
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

    final songMap = ref.watch(songByIdMapProvider);

    final songs = currentPlaylist.songIds
        .map((id) => songMap[id])
        .whereType<Song>()
        .toList();

    final firstSongWithArt = songs
        .where((s) => s.albumArtUri != null && s.albumArtUri!.isNotEmpty)
        .firstOrNull;
    final effectiveCoverArtUri =
        currentPlaylist.coverArtUri ?? firstSongWithArt?.albumArtUri;

    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPlaylist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, size: 21),
            tooltip: '更换歌单封面',
            onPressed: () =>
                SelectPlaylistCoverDialog.show(context, currentPlaylist),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded, size: 23),
            tooltip: '添加歌曲',
            onPressed: () =>
                AddSongsToPlaylistDialog.show(context, currentPlaylist),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 21),
            tooltip: '更多操作',
            onSelected: (action) {
              switch (action) {
                case 'rename':
                  _showRenameDialog(context, ref, currentPlaylist);
                  break;
                case 'export_m3u':
                  _exportM3u(context, currentPlaylist, songs);
                  break;
                case 'delete':
                  _confirmDelete(context, ref, currentPlaylist);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('重命名 / 描述'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_m3u',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add_check_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('导出 M3U 播放列表'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '删除歌单',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 简洁编辑态歌单头部卡片（去除了繁杂渐变底，以素净细框托起封面）
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: appColors.glassBorder, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: '点击更换歌单封面',
                      child: InkWell(
                        onTap: () => SelectPlaylistCoverDialog.show(
                          context,
                          currentPlaylist,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isLight ? 0.08 : 0.30,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: SongArtwork(
                                artUri: effectiveCoverArtUri,
                                size: 86,
                                borderRadius: 14,
                              ),
                            ),
                            Positioned(
                              right: 5,
                              bottom: 5,
                              child: Container(
                                padding: const EdgeInsets.all(4.5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentPlaylist.description.isNotEmpty
                                ? currentPlaylist.description
                                : '共 ${songs.length} 首歌曲',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilledButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        ref
                                            .read(audioControllerProvider)
                                            .playSong(
                                              songs.first,
                                              queue: songs,
                                            );
                                      },
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 17,
                                ),
                                label: const Text('播放全部'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        final shuffled = List<Song>.from(songs)
                                          ..shuffle();
                                        final first = shuffled.first;
                                        ref
                                            .read(audioControllerProvider)
                                            .playSong(first, queue: shuffled);
                                        AppToast.show(
                                          context,
                                          '随机播放《${first.title}》',
                                          icon: Icons.shuffle_rounded,
                                        );
                                      },
                                icon: const Icon(
                                  Icons.shuffle_rounded,
                                  size: 16,
                                ),
                                label: const Text('随机'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 6,
                                  ),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => AddSongsToPlaylistDialog.show(
                                  context,
                                  currentPlaylist,
                                ),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('添加歌曲'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 6,
                                  ),
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
                    ? EmptyStateView(
                        icon: Icons.library_music_outlined,
                        title: '歌单暂无歌曲',
                        subtitle: '从本地曲库或收藏中挑选曲目加入此歌单',
                        actions: [
                          FilledButton.icon(
                            onPressed: () => AddSongsToPlaylistDialog.show(
                              context,
                              currentPlaylist,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('添加歌曲'),
                          ),
                        ],
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemExtent: 58.0,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 104,
                        ),
                        itemCount: songs.length,
                        // onReorderItem 的 newIndex 已按移除位置校正，
                        // 与 reorderPlaylistSongs 的 removeAt+insert 语义一致。
                        onReorderItem: (oldIndex, newIndex) {
                          ref
                              .read(playlistNotifierProvider.notifier)
                              .reorderPlaylistSongs(
                                currentPlaylist.id,
                                oldIndex,
                                newIndex,
                              );
                        },
                        proxyDecorator: (child, index, animation) =>
                            AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final t = Curves.easeInOut.transform(
                                  animation.value.clamp(0.0, 1.0),
                                );
                                return Material(
                                  elevation: t * 6,
                                  borderRadius: BorderRadius.circular(12),
                                  child: child,
                                );
                              },
                            ),
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          // 长按整行启动拖拽排序；普通滑动仍用于列表滚动。
                          return ReorderableDelayedDragStartListener(
                            key: ValueKey('playlist_song_${song.id}'),
                            index: index,
                            child: SongTile(
                              song: song,
                              contextQueue: songs,
                              index: index,
                              onSetAsPlaylistCover: () async {
                                await ref
                                    .read(playlistNotifierProvider.notifier)
                                    .setPlaylistCover(
                                      currentPlaylist.id,
                                      song.albumArtUri,
                                    );
                                if (context.mounted) {
                                  AppToast.show(
                                    context,
                                    '已将《${song.title}》封面设为歌单封面',
                                    icon: Icons.check_circle_rounded,
                                  );
                                }
                              },
                              onDelete: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('从歌单移除'),
                                    content: Text(
                                      '确定将《${song.title}》从歌单《${currentPlaylist.name}》中移除吗？\n\n提示：歌曲仍保留在本地曲库中。',
                                      style: const TextStyle(height: 1.45),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              theme.colorScheme.error,
                                          foregroundColor:
                                              theme.colorScheme.onError,
                                        ),
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          ref
                                              .read(
                                                playlistNotifierProvider
                                                    .notifier,
                                              )
                                              .removeSongFromPlaylist(
                                                currentPlaylist.id,
                                                song.id,
                                              );
                                          AppToast.show(
                                            context,
                                            '已从歌单移除《${song.title}》',
                                            icon: Icons.delete_sweep_rounded,
                                          );
                                        },
                                        child: const Text('移除'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Playlist currentPlaylist,
  ) async {
    final nameController = TextEditingController(text: currentPlaylist.name);
    final descController = TextEditingController(
      text: currentPlaylist.description,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名歌单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '歌单名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '描述 (可选)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nameController,
            builder: (context, value, _) {
              return FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () {
                        ref
                            .read(playlistNotifierProvider.notifier)
                            .renamePlaylist(
                              currentPlaylist.id,
                              value.text,
                              description: descController.text,
                            );
                        Navigator.pop(dialogContext);
                      },
                child: const Text('保存'),
              );
            },
          ),
        ],
      ),
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
    });
  }

  Future<void> _exportM3u(
    BuildContext context,
    Playlist currentPlaylist,
    List<Song> songs,
  ) async {
    final res = await FileExportService.exportPlaylistM3u(
      playlistName: currentPlaylist.name,
      songs: songs,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        res.message,
        icon: res.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Playlist currentPlaylist,
  ) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除歌单《${currentPlaylist.name}》吗？歌单内的本地歌曲不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () {
              ref
                  .read(playlistNotifierProvider.notifier)
                  .deletePlaylist(currentPlaylist.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
