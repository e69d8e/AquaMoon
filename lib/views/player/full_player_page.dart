import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../models/playback_mode.dart';
import '../../models/playback_progress.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/file_export_service.dart';
import '../online_search/online_search_page.dart';
import '../widgets/custom_progress_bar.dart';
import '../widgets/edit_song_dialog.dart';
import '../widgets/online_candidate_dialog.dart';
import '../widgets/song_artwork.dart';
import 'lyrics_view.dart';

class FullPlayerPage extends ConsumerStatefulWidget {
  const FullPlayerPage({super.key});

  @override
  ConsumerState<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends ConsumerState<FullPlayerPage> {
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentCover(Song song) async {
    final uri = song.albumArtUri;
    if (uri == null || uri.isEmpty) {
      AppToast.show(
        context,
        '当前歌曲暂无可用封面图片',
        icon: Icons.image_not_supported_rounded,
      );
      return;
    }
    AppToast.show(context, '正在保存当前封面...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveCoverImage(
      coverUrlOrPath: uri,
      title: song.title,
      artist: song.artist,
    );
    if (mounted) {
      AppToast.show(
        context,
        res.success ? '封面已成功保存至 SoundCraft 文件夹！' : res.message,
        icon: res.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _exportCurrentLyrics(Song song) async {
    final lyricsState = ref.read(lyricsNotifierProvider);
    String? content = song.lrcContent;
    if (content == null || content.trim().isEmpty) {
      if (lyricsState.lines.isNotEmpty) {
        content = lyricsState.lines
            .map((l) {
              final m = l.time.inMinutes
                  .remainder(60)
                  .toString()
                  .padLeft(2, '0');
              final s = l.time.inSeconds
                  .remainder(60)
                  .toString()
                  .padLeft(2, '0');
              final ms = (l.time.inMilliseconds.remainder(1000) ~/ 10)
                  .toString()
                  .padLeft(2, '0');
              return '[$m:$s.$ms]${l.text}';
            })
            .join('\n');
      } else if (lyricsState.plainText != null &&
          lyricsState.plainText!.trim().isNotEmpty) {
        content = lyricsState.plainText;
      }
    }

    if (content == null || content.trim().isEmpty) {
      AppToast.show(context, '当前歌曲暂无歌词可导出', icon: Icons.lyrics_outlined);
      return;
    }

    AppToast.show(context, '正在导出 LRC 歌词文件...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveLyricFile(
      lyricContent: content,
      title: song.title,
      artist: song.artist,
    );
    if (mounted) {
      AppToast.show(
        context,
        res.success ? '歌词文件已保存至 SoundCraft 文件夹！' : res.message,
        icon: res.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _copyCurrentLyrics(Song song) async {
    final lyricsState = ref.read(lyricsNotifierProvider);
    String? content = song.lrcContent ?? lyricsState.plainText;
    if (content == null || content.trim().isEmpty) {
      if (lyricsState.lines.isNotEmpty) {
        content = lyricsState.lines.map((l) => l.text).join('\n');
      }
    }

    if (content == null || content.trim().isEmpty) {
      AppToast.show(context, '暂无可复制的歌词内容', icon: Icons.info_outline_rounded);
      return;
    }

    await FileExportService.copyToClipboard(content);
    if (mounted) {
      AppToast.show(context, '歌词已复制到剪贴板！', icon: Icons.copy_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSongAsync = ref.watch(currentSongProvider);
    final song = currentSongAsync.valueOrNull;

    if (song == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('当前无播放曲目')),
      );
    }

    final isPlaying = ref.watch(
      playbackStateStreamProvider.select(
        (s) => s.valueOrNull?.playing ?? false,
      ),
    );
    final isBuffering = ref.watch(
      playbackStateStreamProvider.select(
        (s) =>
            s.valueOrNull?.processingState == AudioProcessingState.loading ||
            s.valueOrNull?.processingState == AudioProcessingState.buffering,
      ),
    );
    final playbackMode = ref.watch(
      playbackModeStreamProvider.select(
        (m) => m.valueOrNull ?? PlaybackMode.sequence,
      ),
    );

    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final screenWidth = MediaQuery.of(context).size.width;
    final coverSize = min(screenWidth * 0.72, 300.0);

    // Dynamic light / dark color tokens
    final primaryTextColor = isLight ? const Color(0xFF1B1C26) : Colors.white;
    final secondaryTextColor = isLight
        ? const Color(0xFF6B6E7D)
        : Colors.white.withValues(alpha: 0.75);
    final iconColor = isLight ? const Color(0xFF1F202B) : Colors.white;
    final composerTextColor = isLight
        ? const Color(0xFF8B8E9D)
        : Colors.white.withValues(alpha: 0.55);

    final gradientColors = isLight
        ? const [
            Color(0xFFEBE6F3), // Soft airy lilac
            Color(0xFFF6F2F8), // Morning mist lavender
            Color(0xFFFFFFFF), // Pure silky alabaster
          ]
        : const [
            Color(0xFF5E4866), // Sunset mauve
            Color(0xFF382A4D), // Twilight deep violet
            Color(0xFF191326), // Obsidian midnight
          ];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.45, 1.0],
            colors: gradientColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar with back button, perfectly centered title & subtitle, and actions
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 4.0,
                ),
                child: SizedBox(
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Perfectly Centered Song Title & Artist
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 92.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: primaryTextColor,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${song.artist} - ${song.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Left Back Icon
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 30,
                            color: secondaryTextColor,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),

                      // Right Favorite & More Actions
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                song.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 23,
                                color: song.isFavorite
                                    ? const Color(0xFFFF5252)
                                    : secondaryTextColor,
                              ),
                              onPressed: () {
                                ref
                                    .read(libraryNotifierProvider.notifier)
                                    .toggleFavorite(song);
                              },
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert_rounded,
                                size: 23,
                                color: secondaryTextColor,
                              ),
                              tooltip: '更多操作与下载',
                              onSelected: (action) async {
                                switch (action) {
                                  case 'save_cover':
                                    _saveCurrentCover(song);
                                    break;
                                  case 'export_lyrics':
                                    _exportCurrentLyrics(song);
                                    break;
                                  case 'copy_lyrics':
                                    _copyCurrentLyrics(song);
                                    break;
                                  case 'online_calibrate':
                                    final selected =
                                        await OnlineCandidateSelectDialog.show(
                                          context,
                                          song,
                                        );
                                    if (selected != null) {
                                      final onlineService = ref.read(
                                        onlineMetadataServiceProvider,
                                      );
                                      String? newArtUri = song.albumArtUri;
                                      if (selected.coverUrl != null &&
                                          selected.coverUrl!.isNotEmpty) {
                                        newArtUri = await onlineService
                                            .cacheOnlineImage(
                                              selected.coverUrl!,
                                            );
                                      }
                                      final newLrc =
                                          selected.syncedLyrics ??
                                          selected.plainLyrics;

                                      final updated = song.copyWith(
                                        title: selected.title,
                                        artist: selected.artist,
                                        album: selected.album.isNotEmpty
                                            ? selected.album
                                            : song.album,
                                        albumArtUri: newArtUri,
                                        lrcContent: newLrc,
                                      );

                                      await ref
                                          .read(
                                            libraryNotifierProvider.notifier,
                                          )
                                          .updateSong(updated);
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
                                      if (context.mounted) {
                                        AppToast.show(
                                          context,
                                          '已应用来自 ${selected.source} 的元数据！',
                                          icon: Icons
                                              .check_circle_outline_rounded,
                                        );
                                      }
                                    }
                                    break;
                                  case 'global_online_search':
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => OnlineSearchPage(
                                          initialQuery:
                                              '${song.title} ${song.artist}',
                                        ),
                                      ),
                                    );
                                    break;
                                  case 'edit_song':
                                    EditSongDialog.show(context, song);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'save_cover',
                                  child: Row(
                                    children: [
                                      Icon(Icons.image_outlined, size: 18),
                                      SizedBox(width: 10),
                                      Text('保存当前封面图片'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'export_lyrics',
                                  child: Row(
                                    children: [
                                      Icon(Icons.lyrics_outlined, size: 18),
                                      SizedBox(width: 10),
                                      Text('导出当前歌词 (.lrc)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'copy_lyrics',
                                  child: Row(
                                    children: [
                                      Icon(Icons.copy_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text('复制歌词文本'),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'online_calibrate',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.saved_search_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Text('在线检索与更换数据'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'global_online_search',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.cloud_download_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Text('全网在线歌曲检索'),
                                    ],
                                  ),
                                ),
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
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Center Switchable Content (PageView for left-right swipe between Cover & Lyrics)
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (page) {
                          setState(() {
                            _currentPage = page;
                          });
                        },
                        children: [
                          // Page 0: Cover Artwork & Active Lyric Preview Line
                          GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                1,
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                              );
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Spacer(flex: 2),
                                // Cover Art
                                Container(
                                  width: coverSize,
                                  height: coverSize,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isLight
                                            ? const Color(0x1F2A1E40)
                                            : Colors.black.withValues(
                                                alpha: 0.45,
                                              ),
                                        blurRadius: 28,
                                        offset: const Offset(0, 14),
                                      ),
                                      BoxShadow(
                                        color: isLight
                                            ? const Color(0x146B4B6E)
                                            : const Color(0xFF6B4B6E)
                                                  .withValues(alpha: 0.25),
                                        blurRadius: 36,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Hero(
                                      tag: 'player_artwork',
                                      child: SongArtwork(
                                        song: song,
                                        size: coverSize,
                                        borderRadius: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(flex: 3),
                                // Sub-Artwork Composer & Synced Lyric
                                _FullPlayerLyricPreview(
                                  artist: song.artist,
                                  primaryTextColor: primaryTextColor,
                                  composerTextColor: composerTextColor,
                                ),
                                const Spacer(flex: 2),
                              ],
                            ),
                          ),

                          // Page 1: Full Lyrics View
                          LyricsView(
                            song: song,
                            onTapBackground: () {
                              _pageController.animateToPage(
                                0,
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Subtle Indicator Dots
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(2, (index) {
                          final isSelected = _currentPage == index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: isSelected ? 12 : 5,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.7,
                                    )
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.2,
                                    ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Progress Bar (Isolated Rebuild)
              const _FullPlayerProgressBar(),

              const SizedBox(height: 16),

              // Bottom 5-Button Controls Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 1. Loop Mode Toggle
                    IconButton(
                      icon: Icon(
                        _getModeIcon(playbackMode),
                        size: 24,
                        color: playbackMode == PlaybackMode.sequence
                            ? iconColor.withValues(alpha: 0.5)
                            : (isLight
                                  ? theme.colorScheme.primary
                                  : Colors.white),
                      ),
                      tooltip: playbackMode.label,
                      onPressed: () {
                        ref.read(audioControllerProvider).togglePlaybackMode();
                        final nextMode = playbackMode.next();
                        AppToast.show(
                          context,
                          nextMode.label,
                          icon: _getModeIcon(nextMode),
                          duration: const Duration(milliseconds: 1000),
                        );
                      },
                    ),

                    // 2. Previous Track
                    IconButton(
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        size: 34,
                        color: iconColor,
                      ),
                      onPressed: () =>
                          ref.read(audioControllerProvider).previous(),
                    ),

                    // 3. Play / Pause Button
                    IconButton(
                      icon: isBuffering
                          ? SizedBox(
                              width: 48,
                              height: 48,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: iconColor,
                                ),
                              ),
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 48,
                              color: iconColor,
                            ),
                      onPressed: () =>
                          ref.read(audioControllerProvider).togglePlayPause(),
                    ),

                    // 4. Next Track
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        size: 34,
                        color: iconColor,
                      ),
                      onPressed: () => ref.read(audioControllerProvider).next(),
                    ),

                    // 5. Playlist Queue
                    IconButton(
                      icon: Icon(
                        Icons.playlist_play_rounded,
                        size: 28,
                        color: iconColor,
                      ),
                      tooltip: '播放队列',
                      onPressed: () => _showQueueModal(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getModeIcon(PlaybackMode mode) {
    switch (mode) {
      case PlaybackMode.sequence:
      case PlaybackMode.repeatAll:
        return Icons.repeat_rounded;
      case PlaybackMode.repeatOne:
        return Icons.repeat_one_rounded;
      case PlaybackMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  void _showQueueModal(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isLight ? Colors.white : const Color(0xFF1E172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final queueAsync = ref.watch(playlistQueueStreamProvider);
          final currentSongAsync = ref.watch(currentSongProvider);
          final queue = queueAsync.valueOrNull ?? [];
          final currentSong = currentSongAsync.valueOrNull;

          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '当前播放队列 (${queue.length})',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isLight
                                ? const Color(0xFF1C1D24)
                                : Colors.white,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('清空播放队列？'),
                                content: const Text(
                                  '将移除队列中的全部歌曲并停止播放，此操作不可撤销。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('清空'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              ref.read(audioControllerProvider).clearQueue();
                              Navigator.of(context).pop();
                            }
                          },
                          child: const Text(
                            '清空队列',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isLight ? const Color(0x1F000000) : Colors.white12,
                  ),
                  Expanded(
                    child: queue.isEmpty
                        ? Center(
                            child: Text(
                              '队列为空',
                              style: TextStyle(
                                color: isLight
                                    ? const Color(0xFF75788A)
                                    : Colors.white54,
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            scrollController: scrollController,
                            itemCount: queue.length,
                            onReorderItem: (oldIndex, newIndex) {
                              ref
                                  .read(audioControllerProvider)
                                  .reorderQueue(oldIndex, newIndex);
                            },
                            itemBuilder: (context, index) {
                              final s = queue[index];
                              final isCurrent = s.id == currentSong?.id;

                              return ListTile(
                                key: ValueKey('queue_song_${s.id}_$index'),
                                leading: SongArtwork(
                                  song: s,
                                  size: 40,
                                  borderRadius: 6,
                                ),
                                title: Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isCurrent
                                        ? theme.colorScheme.primary
                                        : (isLight
                                              ? const Color(0xFF1C1D24)
                                              : Colors.white70),
                                  ),
                                ),
                                subtitle: Text(
                                  s.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isLight
                                        ? const Color(0xFF75788A)
                                        : Colors.white38,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: isLight
                                        ? const Color(0xFF75788A)
                                        : Colors.white38,
                                  ),
                                  onPressed: () {
                                    ref
                                        .read(audioControllerProvider)
                                        .removeQueueItem(index);
                                  },
                                ),
                                onTap: () {
                                  ref
                                      .read(audioControllerProvider)
                                      .playAtIndex(index);
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FullPlayerLyricPreview extends ConsumerWidget {
  final String artist;
  final Color primaryTextColor;
  final Color composerTextColor;

  const _FullPlayerLyricPreview({
    required this.artist,
    required this.primaryTextColor,
    required this.composerTextColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final activeLyricIndex = ref.watch(currentLyricIndexProvider);

    String activeLyricText = '纯音乐，请欣赏';
    if (lyricsState.lines.isNotEmpty) {
      if (activeLyricIndex >= 0 &&
          activeLyricIndex < lyricsState.lines.length) {
        activeLyricText = lyricsState.lines[activeLyricIndex].text;
      } else if (activeLyricIndex == -1) {
        activeLyricText = lyricsState.lines.first.text;
      }
    } else if (lyricsState.plainText != null &&
        lyricsState.plainText!.trim().isNotEmpty) {
      activeLyricText = lyricsState.plainText!.trim().split('\n').first;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '歌手 : $artist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: composerTextColor,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              activeLyricText,
              key: ValueKey(activeLyricText),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: primaryTextColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullPlayerProgressBar extends ConsumerWidget {
  const _FullPlayerProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(playbackProgressStreamProvider).valueOrNull ??
        const PlaybackProgress();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: CustomProgressBar(
        progress: progress,
        onSeek: (pos) => ref.read(audioControllerProvider).seek(pos),
      ),
    );
  }
}
