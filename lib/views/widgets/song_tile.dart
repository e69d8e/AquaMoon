import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/qq_music_download_provider.dart';
import '../../providers/qq_music_provider.dart';
import 'aquamoon_mark.dart';
import 'edit_song_dialog.dart';
import 'local_song_link_dialog.dart';
import 'online_candidate_dialog.dart';
import 'qq_music_quality_picker.dart';
import 'song_artwork.dart';
import 'ui_helpers.dart';

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

  /// 在行尾显示直达「关联本地音频」的快捷按钮（用于未匹配歌曲页）。
  final bool showQuickLinkAction;

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
    this.showQuickLinkAction = false,
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
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;

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

    return Semantics(
      selected: isCurrent || isSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: isLight ? 0.12 : 0.18)
              : isCurrent
              ? theme.colorScheme.primary.withValues(alpha: isLight ? 0.075 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: (isSelected || isCurrent) ? Clip.antiAlias : Clip.none,
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
            child: Stack(
              children: [
                // 当前播放曲目左侧极细朱砂/主题墨线标识。
                if (isCurrent && !selectionMode)
                  Positioned(
                    left: 0,
                    top: 12,
                    bottom: 12,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                  child: Row(
                    children: [
                      if (selectionMode) ...[
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 21,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.72,
                                ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      SongArtwork(song: song, size: 44, borderRadius: 9),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (isCurrent) ...[
                                  PlayingWaveIndicator(
                                    isPlaying: isPlaying,
                                    size: 13,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.2,
                                      fontWeight: isCurrent
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      letterSpacing: -0.1,
                                      color: isCurrent
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2.5),
                            Row(
                              children: [
                                if (song.qqSongMid != null &&
                                    song.qqSongMid!.isNotEmpty) ...[
                                  _buildSourceBadge(
                                    theme,
                                    appColors,
                                    label: song.hasLocalFile ? '本地' : 'QQ音乐',
                                    isLocal: song.hasLocalFile,
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                if (song.isVip && song.isQQMusicOnline) ...[
                                  _buildVipBadge(appColors),
                                  const SizedBox(width: 5),
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
                                          .withValues(alpha: 0.92),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (song.playCount > 0) ...[
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.85,
                          ),
                        ),
                        Text(
                          '${song.playCount}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.90),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        Formatters.formatDuration(song.duration),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.90,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      if (selectionMode)
                        const SizedBox(width: 26)
                      else ...[
                        if (showQuickLinkAction &&
                            isQQBound &&
                            !song.hasLocalFile &&
                            hasQqMid)
                          IconButton(
                            icon: Icon(
                              Icons.link_rounded,
                              size: 19,
                              color: theme.colorScheme.primary,
                            ),
                            tooltip: '关联本地音频',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            onPressed: () => _linkLocalSong(context),
                          ),
                        // Favorite toggle and all other per-song operations live in
                        // the overflow menu so each row carries a single trailing
                        // control.
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.80),
                          ),
                          tooltip: '歌曲操作：${song.title}',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onSelected: (action) =>
                              _handleAction(context, ref, action),
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
                                  color: song.isFavorite
                                      ? appColors.favorite
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Text(song.isFavorite ? '取消收藏' : '收藏'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'play_next',
                            child: Row(
                              children: [
                                Icon(Icons.queue_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('下一首播放'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'add_to_playlist',
                            child: Row(
                              children: [
                                Icon(Icons.playlist_add_rounded, size: 18),
                                SizedBox(width: 10),
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
                                  SizedBox(width: 10),
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
                                  SizedBox(width: 10),
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
                                  SizedBox(width: 10),
                                  Text('关联本地音频'),
                                ],
                              ),
                            ),
                          // 云端曲目尚未落地成本地文件时，直接提供下载入口。
                          if (hasQqMid && !song.hasLocalFile)
                            const PopupMenuItem(
                              value: 'download_song',
                              child: Row(
                                children: [
                                  Icon(Icons.download_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('下载到本地'),
                                ],
                              ),
                            ),
                          if (isQQBound && song.hasLocalFile && hasQqMid)
                            const PopupMenuItem(
                              value: 'unlink_local_song',
                              child: Row(
                                children: [
                                  Icon(Icons.link_off_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('取消本地关联'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'online_candidate_select',
                            child: Row(
                              children: [
                                Icon(Icons.saved_search_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('在线检索歌曲信息'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'fetch_online_metadata',
                            child: Row(
                              children: [
                                Icon(Icons.cloud_download_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('智能补齐歌词与封面'),
                              ],
                            ),
                          ),
                          if (!song.isQQMusicOnline || onDelete != null) ...[
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
                                    '从曲库移除',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// 选择音质 → 加入串行下载队列 → 完成/失败后提示结果。
  Future<void> _downloadSong(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(qqMusicDownloadSettingsProvider);
    var hasCookie = false;
    try {
      hasCookie =
          ref.read(storageServiceProvider).getQQMusicConfig().hasCookie;
    } catch (_) {}
    final quality = await showQQMusicQualityPicker(
      context,
      title: '选择下载音质',
      subtitle: '《${song.title}》· 保存到 ${settings.directoryLabel}',
      selected: settings.quality,
      hasCookie: hasCookie,
    );
    if (quality == null || !context.mounted) return;

    AppToast.show(
      context,
      '已加入下载队列：${quality.label}',
      icon: Icons.download_rounded,
    );
    final task = await ref
        .read(qqMusicDownloadProvider.notifier)
        .enqueue(song, quality: quality);
    if (!context.mounted) return;
    if (task.status == QQMusicDownloadStatus.completed) {
      AppToast.show(
        context,
        '《${song.title}》已保存到 ${task.directory ?? settings.directoryLabel}',
        icon: Icons.download_done_rounded,
      );
    } else if (task.isFailed) {
      AppToast.show(
        context,
        task.message.isEmpty ? '下载失败，请稍后重试' : task.message,
      );
    }
  }

  Future<void> _linkLocalSong(BuildContext context) async {
    final message = await LocalSongLinkDialog.show(context, song);
    if (context.mounted && message != null && message.isNotEmpty) {
      AppToast.show(context, message, icon: Icons.link_rounded);
    }
  }

  Widget _buildSourceBadge(
    ThemeData theme,
    AppColors appColors, {
    required String label,
    required bool isLocal,
  }) {
    final badgeColor = isLocal
        ? theme.colorScheme.primary
        : appColors.onlineBadge;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 0.5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.30),
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

  Widget _buildVipBadge(AppColors appColors) {
    final color = appColors.vipBadge;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'link_local_song':
        await _linkLocalSong(context);
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
      case 'download_song':
        await _downloadSong(context, ref);
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
            '已应用来自 ${selected.source} 的《${selected.title}》元数据',
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
            error != null ? '在线匹配失败：$error' : '在线信息匹配完成',
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

  Future<void> _confirmDeleteFromLibrary(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final library = ref.read(libraryNotifierProvider.notifier);
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: '从曲库移除',
      message: '确定将《${song.title}》从曲库移除吗？\n\n提示：设备中的本地原音频文件不会被删除。',
      confirmLabel: '确认移除',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !context.mounted) return;
    library.deleteSong(song);
    AppToast.show(
      context,
      '已从曲库移除《${song.title}》',
      icon: Icons.delete_sweep_rounded,
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref) {
    final playlists = ref.read(playlistNotifierProvider);
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加到歌单'),
        content: playlists.isEmpty
            ? const Text('暂无自定义歌单，请先在歌单页面创建。')
            : SizedBox(
                width: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (c, i) {
                    final pl = playlists[i];
                    final contains = pl.songIds.contains(song.id);
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Text(pl.name),
                      subtitle: Text('${pl.songIds.length} 首歌曲'),
                      trailing: contains
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: theme.colorScheme.primary,
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
