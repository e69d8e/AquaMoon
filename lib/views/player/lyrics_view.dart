import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/lyrics_settings_provider.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/glass_container.dart';
import '../widgets/online_candidate_dialog.dart';
import '../widgets/ui_helpers.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _stopAutoScroll();
    }
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
      // Hoist provider access above the await-heavy section: the hosting
      // player page can be popped while the cover downloads, and riverpod
      // throws on ref use after dispose.
      final library = ref.read(libraryNotifierProvider.notifier);
      final handler = ref.read(audioHandlerProvider);
      final lyricsNotifier = ref.read(lyricsNotifierProvider.notifier);
      final onlineService = ref.read(onlineMetadataServiceProvider);
      String? newArtUri = widget.song.albumArtUri;
      if (selected.coverUrl != null && selected.coverUrl!.isNotEmpty) {
        newArtUri = await onlineService.cacheOnlineImage(selected.coverUrl!);
      }
      final newLrc = selected.syncedLyrics ?? selected.plainLyrics;

      final applied = await library.updateSongMerged(widget.song.id, (current) {
        return current.copyWith(
          title: selected.title,
          artist: selected.artist,
          album: selected.album.isNotEmpty ? selected.album : current.album,
          albumArtUri: newArtUri,
          lrcContent: newLrc,
        );
      });
      if (applied == null) return;
      final updated = applied;

      handler.updateCurrentSongMetadata(
        title: updated.title,
        artist: updated.artist,
        album: updated.album,
        albumArtUri: updated.albumArtUri,
        lrcContent: updated.lrcContent,
      );
      lyricsNotifier.loadLyricsForSong(updated);

      if (mounted) {
        AppToast.show(
          context,
          '已应用来自 ${selected.source} 的歌词与元数据',
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

  void _scrollToActiveIndex(int index, int totalCount, {bool force = false}) {
    if ((_userScrolling && !force) ||
        !_scrollController.hasClients ||
        index < 0 ||
        totalCount == 0) {
      return;
    }

    if (!force && index == _lastActiveIndex) return;
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
    // list never visibly "flies" from the top; glide as lines advance, unless
    // reduced motion is preferred.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion || (isFirstPositioning && !force)) {
      _stopAutoScroll();
      _scrollController.jumpTo(clampedOffset);
    } else {
      _glideTo(clampedOffset);
    }
  }

  void _recenterToActive(int activeIndex, int totalCount) {
    _userScrollResumeTimer?.cancel();
    setState(() => _userScrolling = false);
    _scrollToActiveIndex(activeIndex, totalCount, force: true);
  }

  Widget _wrapWithEdgeFade({
    required Widget child,
    required AppColors appColors,
  }) {
    final topColor = appColors.playerGradient.first;
    final bottomColor =
        Color.lerp(appColors.playerGradient[1], appColors.playerGradient.last, 0.72) ??
        appColors.playerGradient.last;
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 36,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [topColor, topColor.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 44,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bottomColor.withValues(alpha: 0), bottomColor],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final activeIndex = ref.watch(currentLyricIndexProvider);
    final lyricsSettings = ref.watch(lyricsDisplaySettingsProvider);
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;

    if (lyricsState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '正在加载歌词...',
              style: TextStyle(
                fontSize: 13.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
          child: _wrapWithEdgeFade(
            appColors: appColors,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 48,
                ),
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
          ),
        );
      }

      return GestureDetector(
        onTap: widget.onTapBackground,
        behavior: HitTestBehavior.translucent,
        child: EmptyStateView(
          icon: Icons.lyrics_rounded,
          title: '暂无歌词',
          subtitle: '可尝试智能匹配在线歌词，或手动挑选更精准的版本',
          actions: [
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
      );
    }

    // Trigger auto scroll only when visible and active line actually moved.
    if (tickerEnabled && activeIndex >= 0 && activeIndex != _lastActiveIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveIndex(activeIndex, lyricsState.lines.length);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final topPadding = viewportHeight * lyricsSettings.scrollAlignment;
        final bottomPadding = viewportHeight * 0.55;

        return Stack(
          children: [
            GestureDetector(
              onTap: widget.onTapBackground,
              behavior: HitTestBehavior.translucent,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle) {
                    // User took over: kill the glide so its per-frame jumpTo
                    // cannot fight the drag, and pause auto centering.
                    _stopAutoScroll();
                    if (!_userScrolling) {
                      setState(() => _userScrolling = true);
                    }
                  } else if (notification is UserScrollNotification) {
                    // Delay re-enabling auto scroll after manual swipe; a new
                    // swipe cancels the pending resume so timers don't pile up.
                    _userScrollResumeTimer?.cancel();
                    _userScrollResumeTimer = Timer(
                      const Duration(seconds: 3),
                      () {
                        if (mounted) {
                          setState(() {
                            _userScrolling = false;
                          });
                        }
                      },
                    );
                  } else if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _stopAutoScroll();
                  }
                  return false;
                },
                child: _wrapWithEdgeFade(
                  appColors: appColors,
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
                      final distance = activeIndex >= 0
                          ? (index - activeIndex).abs()
                          : 1;
                      final inactiveAlpha = distance <= 1
                          ? (isLight ? 0.64 : 0.68)
                          : (isLight ? 0.48 : 0.52);
                      final key = _itemKeys.putIfAbsent(
                        index,
                        () => GlobalKey(),
                      );

                      final baseStyle = TextStyle(
                        fontSize: isActive
                            ? lyricsSettings.activeFontSize
                            : lyricsSettings.baseFontSize,
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w500,
                        letterSpacing: isActive ? -0.2 : 0.0,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: inactiveAlpha,
                              ),
                        height: lyricsSettings.lineHeight,
                      );

                      final Widget lineChild;
                      if (isActive && line.hasWordTimings) {
                        // Leaf ConsumerWidget isolates ~5Hz word-progress
                        // rebuilds to just the single active lyric row.
                        lineChild = _KaraokeLyricLine(
                          text: line.text,
                          baseStyle: baseStyle,
                        );
                      } else {
                        lineChild = AnimatedDefaultTextStyle(
                          duration: motionDuration(context, _highlightDuration),
                          curve: Curves.easeOutCubic,
                          style: baseStyle,
                          child: Text(line.text, textAlign: TextAlign.center),
                        );
                      }

                      return Semantics(
                        button: true,
                        selected: isActive,
                        hint: '点按跳转到此句歌词',
                        child: InkWell(
                          key: key,
                          onTap: () {
                            ref.read(audioControllerProvider).seek(line.time);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: lineChild,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_userScrolling && activeIndex >= 0)
              Positioned(
                right: 20,
                bottom: 14,
                child: Semantics(
                  button: true,
                  label: '回到当前播放歌词',
                  child: GlassContainer(
                    borderRadius: BorderRadius.circular(20),
                    blurSigma: 16,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _recenterToActive(
                          activeIndex,
                          lyricsState.lines.length,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.my_location_rounded,
                                  size: 15,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '回到当前句',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 逐字卡拉OK行：独立订阅 5Hz 进度并缓存 grapheme 切片，避免每帧重建整表与重复分词。
class _KaraokeLyricLine extends ConsumerStatefulWidget {
  final String text;
  final TextStyle baseStyle;

  const _KaraokeLyricLine({required this.text, required this.baseStyle});

  @override
  ConsumerState<_KaraokeLyricLine> createState() => _KaraokeLyricLineState();
}

class _KaraokeLyricLineState extends ConsumerState<_KaraokeLyricLine> {
  late List<String> _graphemes;

  @override
  void initState() {
    super.initState();
    _graphemes = widget.text.characters.toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant _KaraokeLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _graphemes = widget.text.characters.toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = ref.watch(currentLyricLitFractionProvider);
    if (fraction == null) {
      return Text(
        widget.text,
        textAlign: TextAlign.center,
        style: widget.baseStyle,
      );
    }
    final theme = Theme.of(context);
    final litCount = (_graphemes.length * fraction).round().clamp(
      0,
      _graphemes.length,
    );
    return Text.rich(
      TextSpan(
        style: widget.baseStyle,
        children: [
          TextSpan(text: _graphemes.take(litCount).join()),
          TextSpan(
            text: _graphemes.skip(litCount).join(),
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(
                alpha: theme.brightness == Brightness.light ? 0.50 : 0.45,
              ),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
