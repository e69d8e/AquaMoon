import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/app_toast.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../services/file_export_service.dart';
import '../../playlists/playlist_detail_page.dart';
import '../../widgets/song_artwork.dart';

class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistNotifierProvider);
    final songs = ref.watch(libraryNotifierProvider.select((s) => s.songs));
    final songMap = {for (final s in songs) s.id: s};
    final theme = Theme.of(context);

    return Column(
      children: [
        // Action Header (Minimal & Icon-driven)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              Icon(
                Icons.queue_music_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${playlists.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.note_add_outlined,
                  size: 21,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.8,
                  ),
                ),
                tooltip: '导入 M3U 歌单',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _importM3uPlaylist(context, ref),
              ),
              IconButton(
                icon: Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                tooltip: '新建歌单',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _showCreatePlaylistDialog(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.queue_music_rounded,
                        size: 56,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '暂无自定义歌单',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('新建歌单'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () =>
                            _showCreatePlaylistDialog(context, ref),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    final firstSongWithArt = pl.songIds
                        .map((id) => songMap[id])
                        .whereType<Song>()
                        .where(
                          (s) =>
                              s.albumArtUri != null &&
                              s.albumArtUri!.isNotEmpty,
                        )
                        .firstOrNull;
                    final effectiveCover =
                        pl.coverArtUri ?? firstSongWithArt?.albumArtUri;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: SongArtwork(
                          artUri: effectiveCover,
                          size: 44,
                          borderRadius: 10,
                        ),
                        title: Text(
                          pl.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          pl.description.isNotEmpty
                              ? pl.description
                              : '${pl.songIds.length} 首歌曲',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlaylistDetailPage(playlist: pl),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 导入 m3u/m3u8 播放列表：解析文件条目并与本地曲库匹配，
  /// 新建歌单并按文件内顺序写入匹配到的歌曲。
  Future<void> _importM3uPlaylist(
    BuildContext context,
    WidgetRef ref,
  ) async {
    List<PlatformFile>? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
      );
    } catch (_) {
      picked = null;
    }
    // 某些平台取消时可能返回空列表而非 null（List.single 会抛 StateError）。
    if (picked == null || picked.isEmpty) return;
    final filePath = picked.first.path;
    if (filePath == null || !context.mounted) return;

    final library =
        ref.read(libraryNotifierProvider.select((s) => s.songs));
    final String content;
    try {
      content = await File(filePath).readAsString();
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, '歌单文件读取失败', icon: Icons.error_outline_rounded);
      }
      return;
    }

    final result = M3uPlaylistParser.parse(content, library);
    if (result.matchedSongIds.isEmpty) {
      if (context.mounted) {
        AppToast.show(
          context,
          '未匹配到曲库中的歌曲（共 ${result.unmatchedEntries} 条无法导入）',
          icon: Icons.info_outline_rounded,
        );
      }
      return;
    }

    final name = _extractPlaylistName(content) ??
        p.basenameWithoutExtension(filePath);

    final playlist = await ref
        .read(playlistNotifierProvider.notifier)
        .createPlaylist(name);
    await ref
        .read(playlistNotifierProvider.notifier)
        .addSongsToPlaylist(playlist.id, result.matchedSongIds);

    if (context.mounted) {
      final skipped = result.unmatchedEntries;
      AppToast.show(
        context,
        skipped > 0
            ? '已导入歌单「$name」：匹配 ${result.matchedSongIds.length} 首，$skipped 首不在曲库'
            : '已导入歌单「$name」共 ${result.matchedSongIds.length} 首歌曲',
        icon: Icons.playlist_add_check_rounded,
      );
    }
  }

  static String? _extractPlaylistName(String content) {
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#PLAYLIST:')) {
        final name = trimmed.substring('#PLAYLIST:'.length).trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '歌单名称',
                hintText: '如：我的车载热歌、轻音乐',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述 (可选)',
                hintText: '写点关于这个歌单的故事...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          // Create stays disabled until the name is non-blank.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: titleController,
            builder: (context, value, _) {
              final name = value.text.trim();
              return FilledButton(
                onPressed: name.isEmpty
                    ? null
                    : () {
                        ref
                            .read(playlistNotifierProvider.notifier)
                            .createPlaylist(
                              name,
                              description: descController.text,
                            );
                        AppToast.show(
                          dialogContext,
                          '已创建歌单「$name」',
                          icon: Icons.check_circle_outline_rounded,
                        );
                        Navigator.pop(dialogContext);
                      },
                child: const Text('创建'),
              );
            },
          ),
        ],
      ),
    ).whenComplete(() {
      titleController.dispose();
      descController.dispose();
    });
  }
}
