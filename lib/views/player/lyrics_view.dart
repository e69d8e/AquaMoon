import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../widgets/online_candidate_dialog.dart';

class LyricsView extends ConsumerStatefulWidget {
  final Song song;
  final VoidCallback? onTapBackground;

  const LyricsView({super.key, required this.song, this.onTapBackground});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  bool _userScrolling = false;
  int _lastActiveIndex = -1;
  Timer? _userScrollResumeTimer;

  Future<void> _calibrateOnline() async {
    final selected = await OnlineCandidateSelectDialog.show(
      context,
      widget.song,
    );
    if (selected != null) {
      final onlineService = ref.read(onlineMetadataServiceProvider);
      String? newArtUri = widget.song.albumArtUri;
      if (selected.coverUrl != null && selected.coverUrl!.isNotEmpty) {
        newArtUri = await onlineService.cacheOnlineImage(selected.coverUrl!);
      }
      final newLrc = selected.syncedLyrics ?? selected.plainLyrics;

      final updated = widget.song.copyWith(
        title: selected.title,
        artist: selected.artist,
        album: selected.album.isNotEmpty ? selected.album : widget.song.album,
        albumArtUri: newArtUri,
        lrcContent: newLrc,
      );

      await ref.read(libraryNotifierProvider.notifier).updateSong(updated);
      ref
          .read(audioHandlerProvider)
          .updateCurrentSongMetadata(
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtUri: updated.albumArtUri,
            lrcContent: updated.lrcContent,
          );
      ref.read(lyricsNotifierProvider.notifier).loadLyricsForSong(updated);

      if (mounted) {
        AppToast.show(
          context,
          '已应用来自 ${selected.source} 的歌词与元数据！',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _itemKeys.clear();
      _lastActiveIndex = -1;
      _userScrolling = false;
    }
  }

  @override
  void dispose() {
    _userScrollResumeTimer?.cancel();
    _itemKeys.clear();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveIndex(int index, int totalCount) {
    if (_userScrolling ||
        !_scrollController.hasClients ||
        index < 0 ||
        totalCount == 0) {
      return;
    }

    if (index == _lastActiveIndex) return;
    _lastActiveIndex = index;

    final key = _itemKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.34, // 居中偏上 (34% from top)
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    } else {
      const estimatedLineHeight = 56.0;
      final targetOffset = index * estimatedLineHeight;
      if (_scrollController.hasClients) {
        final clampedOffset = targetOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final activeIndex = ref.watch(currentLyricIndexProvider);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    if (lyricsState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在加载/匹配歌词...',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (lyricsState.lines.isEmpty) {
      if (lyricsState.plainText != null && lyricsState.plainText!.isNotEmpty) {
        return GestureDetector(
          onTap: widget.onTapBackground,
          behavior: HitTestBehavior.translucent,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Text(
                lyricsState.plainText!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 2.0,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        );
      }

      return GestureDetector(
        onTap: widget.onTapBackground,
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lyrics_rounded,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '暂无歌词',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      ref
                          .read(lyricsNotifierProvider.notifier)
                          .loadLyricsForSong(widget.song, forceOnline: true);
                    },
                    icon: const Icon(Icons.cloud_download_rounded, size: 16),
                    label: const Text('智能匹配在线歌词'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _calibrateOnline,
                    icon: const Icon(Icons.saved_search_rounded, size: 16),
                    label: const Text('在线检索更换'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Trigger auto scroll when active line changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveIndex(activeIndex, lyricsState.lines.length);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final topPadding = viewportHeight * 0.34;
        final bottomPadding = viewportHeight * 0.55;

        return GestureDetector(
          onTap: widget.onTapBackground,
          behavior: HitTestBehavior.translucent,
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction != ScrollDirection.idle) {
                _userScrolling = true;
              } else {
                // Delay re-enabling auto scroll after manual swipe; a new
                // swipe cancels the pending resume so timers don't pile up.
                _userScrollResumeTimer?.cancel();
                _userScrollResumeTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) {
                    setState(() {
                      _userScrolling = false;
                    });
                  }
                });
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: topPadding,
                bottom: bottomPadding,
              ),
              itemCount: lyricsState.lines.length,
              itemBuilder: (context, index) {
                final line = lyricsState.lines[index];
                final isActive = index == activeIndex;
                final key = _itemKeys.putIfAbsent(index, () => GlobalKey());

                return InkWell(
                  key: key,
                  onTap: () {
                    ref.read(audioControllerProvider).seek(line.time);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isActive
                          ? (isLight
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.14,
                                  )
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ))
                          : Colors.transparent,
                    ),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isActive ? 21 : 16,
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isActive
                            ? (isLight
                                  ? const Color(0xFF1B1C26)
                                  : theme.colorScheme.primary)
                            : theme.colorScheme.onSurface.withValues(
                                alpha: isLight ? 0.38 : 0.45,
                              ),
                        height: 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
