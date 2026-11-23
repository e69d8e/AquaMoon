import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_toast.dart';
import '../../../models/playlist.dart';
import '../../../models/song.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../services/file_export_service.dart';
import '../../playlists/playlist_detail_page.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/song_artwork.dart';
import '../../widgets/ui_helpers.dart';

class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistNotifierProvider);
    final songMap = ref.watch(songByIdMapProvider);
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);

    return ResponsivePageContainer(
      maxWidth: 960,
      child: Column(
        children: [
          // 轻量顶部动作行：窄屏或大字号自动折行。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '共 ${playlists.length} 个歌单',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _importM3uPlaylist(context, ref),
                        icon: const Icon(Icons.note_add_outlined, size: 16),
                        label: const Text('导入 M3U'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _showCreatePlaylistDialog(context, ref),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('新建歌单'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: playlists.isEmpty
                ? EmptyStateView(
                    icon: Icons.queue_music_rounded,
                    title: '暂无自定义歌单',
                    subtitle: '将喜欢的旋律整理成册，或导入已有的 M3U 播放列表',
                    actions: [
                      FilledButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('新建歌单'),
                        onPressed: () => _showCreatePlaylistDialog(context, ref),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.note_add_outlined, size: 18),
                        label: const Text('导入 M3U'),
                        onPressed: () => _importM3uPlaylist(context, ref),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 920
                          ? 4
                          : width >= 600
                          ? 3
                          : 2;
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(1.0);
                      const crossSpacing = 14.0;
                      final tileWidth =
                          (width - 32 - (crossAxisCount - 1) * crossSpacing) /
                          crossAxisCount;
                      // 正方形封面 + 底部两行文案按系统字体缩放比例自适应高度。
                      final cardExtent =
                          tileWidth + 12 + 44 * textScale.clamp(1.0, 2.5);

                      return GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          MediaQuery.paddingOf(context).bottom + 108,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: crossSpacing,
                          mainAxisSpacing: 18,
                          mainAxisExtent: cardExtent,
                        ),
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final pl = playlists[index];
                          final resolvedSongs = pl.songIds
                              .map((id) => songMap[id])
                              .whereType<Song>()
                              .toList(growable: false);
                          return _PlaylistGridCard(
                            playlist: pl,
                            songs: resolvedSongs,
                            borderColor: appColors.glassBorder,
                            onOpen: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PlaylistDetailPage(playlist: pl),
                                ),
                              );
                            },
                            onQuickPlay: resolvedSongs.isEmpty
                                ? null
                                : () {
                                    ref
                                        .read(audioControllerProvider)
                                        .playSong(
                                          resolvedSongs.first,
                                          queue: resolvedSongs,
                                        );
                                    AppToast.show(
                                      context,
                                      '开始播放《${pl.name}》',
                                      icon: Icons.play_arrow_rounded,
                                    );
                                  },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 导入 m3u/m3u8 播放列表：解析文件条目并与本地曲库匹配，
  /// 新建歌单并按文件内顺序写入匹配到的歌曲。
  Future<void> _importM3uPlaylist(BuildContext context, WidgetRef ref) async {
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
    final pickedFile = picked.first;
    final filePath = pickedFile.path;
    if (!context.mounted) return;

    final library = ref.read(libraryNotifierProvider.select((s) => s.songs));
    final String content;
    try {
      if (kIsWeb || filePath == null) {
        final bytes = await pickedFile.readAsBytes();
        content = utf8.decode(bytes);
      } else {
        content = await File(filePath).readAsString();
      }
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

    final fallbackName = filePath != null
        ? p.basenameWithoutExtension(filePath)
        : p.basenameWithoutExtension(pickedFile.name);
    final name = _extractPlaylistName(content) ?? fallbackName;

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

  Future<void> _showCreatePlaylistDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // The dialog owns its controllers so they are disposed only when the
    // dialog route is fully removed (disposing them in whenComplete runs
    // while the route is still animating out and breaks TextField).
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => const _CreatePlaylistDialog(),
    );
    if (result == null || !context.mounted) return;

    await ref
        .read(playlistNotifierProvider.notifier)
        .createPlaylist(result.name, description: result.description);
    if (!context.mounted) return;
    AppToast.show(
      context,
      '已创建歌单「${result.name}」',
      icon: Icons.check_circle_outline_rounded,
    );
  }
}

/// 专辑册风格的歌单网格卡片：正方形大图（支持自动四宫格拼贴）、角标一键直播。
class _PlaylistGridCard extends StatelessWidget {
  final Playlist playlist;
  final List<Song> songs;
  final Color borderColor;
  final VoidCallback onOpen;
  final VoidCallback? onQuickPlay;

  const _PlaylistGridCard({
    required this.playlist,
    required this.songs,
    required this.borderColor,
    required this.onOpen,
    required this.onQuickPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final uniqueCovers = <String>[];
    for (final song in songs) {
      final uri = song.albumArtUri;
      if (uri != null && uri.isNotEmpty && !uniqueCovers.contains(uri)) {
        uniqueCovers.add(uri);
        if (uniqueCovers.length == 4) break;
      }
    }
    final useMosaic = playlist.coverArtUri == null && uniqueCovers.length == 4;
    final singleCover = playlist.coverArtUri ?? uniqueCovers.firstOrNull;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: borderColor, width: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isLight ? 0.06 : 0.24,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (useMosaic)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final half = constraints.maxWidth / 2;
                        return Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SongArtwork(
                                      artUri: uniqueCovers[0],
                                      size: half,
                                      borderRadius: 0,
                                    ),
                                  ),
                                  Expanded(
                                    child: SongArtwork(
                                      artUri: uniqueCovers[1],
                                      size: half,
                                      borderRadius: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SongArtwork(
                                      artUri: uniqueCovers[2],
                                      size: half,
                                      borderRadius: 0,
                                    ),
                                  ),
                                  Expanded(
                                    child: SongArtwork(
                                      artUri: uniqueCovers[3],
                                      size: half,
                                      borderRadius: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) => SongArtwork(
                        artUri: singleCover,
                        size: constraints.maxWidth,
                        borderRadius: 0,
                      ),
                    ),
                  // 右下角磨砂直播圆钮（保证 44x44 触控热区）
                  if (onQuickPlay != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Tooltip(
                        message: '播放歌单 ${playlist.name}',
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onQuickPlay,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: GlassContainer(
                                  width: 36,
                                  height: 36,
                                  borderRadius: BorderRadius.circular(18),
                                  enableBlur: false,
                                  tint: theme.colorScheme.surface.withValues(
                                    alpha: isLight ? 0.94 : 0.90,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              playlist.description.isNotEmpty
                  ? playlist.description
                  : '${playlist.songIds.length} 首歌曲',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _titleController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, description: _descController.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建歌单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '歌单名称',
              hintText: '如：雨夜清音、车载精选',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: '描述 (可选)',
              hintText: '写点关于这个歌单的故事...',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        // Create stays disabled until the name is non-blank.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _titleController,
          builder: (context, value, _) {
            final name = value.text.trim();
            return FilledButton(
              onPressed: name.isEmpty ? null : _submit,
              child: const Text('创建'),
            );
          },
        ),
      ],
    );
  }
}
