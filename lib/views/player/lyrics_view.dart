import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/lyrics_settings_provider.dart';
import '../widgets/online_candidate_dialog.dart';

class LyricsView extends ConsumerStatefulWidget {
  final Song song;
  final VoidCallback? onTapBackground;

  const LyricsView({super.key, required this.song, this.onTapBackground});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const _highlightDuration = Duration(milliseconds: 350);
  static const _autoScrollDuration = Duration(milliseconds: 700);

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  bool _userScrolling = false;
  int _lastActiveIndex = -1;
  Timer? _userScrollResumeTimer;

  // The auto-scroll glide is driven by our own AnimationController feeding
  // per-frame jumpTo calls. ScrollController.animateTo must NOT be used here:
  // it runs a DrivenScrollActivity, which sets IgnorePointer over the list
  // for its whole duration, so a lyric line tapped inside that window never
  // reaches its InkWell and the tap falls through to the background
  // GestureDetector — sliding the player PageView back to the cover page.
  late final AnimationController _autoScrollController = AnimationController(
    vsync: this,
    duration: _autoScrollDuration,
  );
  late final CurvedAnimation _autoScrollCurve = CurvedAnimation(
    parent: _autoScrollController,
    curve: Curves.easeInOutCubic,
  );
  Tween<double>? _autoScrollTween;

  // Keeps the scroll position alive inside the player PageView, so swiping
  // back to the cover and returning does not rebuild from the top.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _autoScrollCurve.addListener(_applyAutoScrollTick);
  }

  void _applyAutoScrollTick() {
    final tween = _autoScrollTween;
    if (tween == null || !_scrollController.hasClients) return;
    final target = tween.transform(_autoScrollCurve.value);
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  void _stopAutoScroll() {
    _autoScrollTween = null;
    _autoScrollController.stop();
  }

  void _glideTo(double targetOffset) {
    if (!_scrollController.hasClients) return;
    final from = _scrollController.offset;
    if ((targetOffset - from).abs() < 0.5) return;
    _autoScrollTween = Tween<double>(begin: from, end: targetOffset);
    _autoScrollController.forward(from: 0);
  }

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
      _stopAutoScroll();
      _itemKeys.clear();
      _lastActiveIndex = -1;
      _userScrolling = false;
    }
  }

  @override
  void dispose() {
    _userScrollResumeTimer?.cancel();
    _itemKeys.clear();
    _autoScrollController.dispose();
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
    final isFirstPositioning = _lastActiveIndex == -1;
    _lastActiveIndex = index;

    final settings = ref.read(lyricsDisplaySettingsProvider);
    final estimatedLineHeight =
        settings.baseFontSize * settings.lineHeight + 24;

    // Resolve the target offset within the lyrics list only. Do NOT use
    // Scrollable.ensureVisible here: it reveals the target in every ancestor
    // Scrollable, including the player's horizontal PageView, which yanks the
    // page mid-swipe while the user is dragging between cover and lyrics.
    double? targetOffset;
    final itemContext = _itemKeys[index]?.currentContext;
    final itemRenderObject = itemContext?.findRenderObject();
    if (itemRenderObject != null) {
      final viewport = RenderAbstractViewport.maybeOf(itemRenderObject);
      if (viewport != null) {
        targetOffset = viewport
            .getOffsetToReveal(itemRenderObject, settings.scrollAlignment)
            .offset;
      }
    }
    targetOffset ??= index * estimatedLineHeight;

    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    // Snap on first positioning (page just opened or song changed) so the
    // list never visibly "flies" from the top; glide as lines advance.
    if (isFirstPositioning) {
      _stopAutoScroll();
      _scrollController.jumpTo(clampedOffset);
    } else {
      _glideTo(clampedOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final activeIndex = ref.watch(currentLyricIndexProvider);
    final lyricsSettings = ref.watch(lyricsDisplaySettingsProvider);
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
                  fontSize: lyricsSettings.baseFontSize,
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
        final topPadding = viewportHeight * lyricsSettings.scrollAlignment;
        final bottomPadding = viewportHeight * 0.55;

        return GestureDetector(
          onTap: widget.onTapBackground,
          behavior: HitTestBehavior.translucent,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification &&
                  notification.direction != ScrollDirection.idle) {
                // User took over: kill the glide so its per-frame jumpTo
                // cannot fight the drag, and pause auto centering.
                _stopAutoScroll();
                _userScrolling = true;
              } else if (notification is UserScrollNotification) {
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
              } else if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _stopAutoScroll();
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: _highlightDuration,
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: isActive
                            ? lyricsSettings.activeFontSize
                            : lyricsSettings.baseFontSize,
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: isLight ? 0.38 : 0.45,
                              ),
                        height: lyricsSettings.lineHeight,
                      ),
                      child: Text(line.text, textAlign: TextAlign.center),
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
