import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../models/playback_mode.dart';
import '../../models/playback_progress.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/qq_music_provider.dart';
import '../../services/file_export_service.dart';
import '../online_search/online_search_page.dart';
import '../widgets/aquamoon_mark.dart';
import '../widgets/custom_progress_bar.dart';
import '../widgets/edit_song_dialog.dart';
import '../widgets/glass_container.dart';
import '../widgets/online_candidate_dialog.dart';
import '../widgets/song_artwork.dart';
import '../widgets/ui_helpers.dart';
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

  void _animateToPage(int page) {
    if (!_pageController.hasClients) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pageController.jumpToPage(page);
      return;
    }
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
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
        res.success ? '封面已保存至 AquaMoon 文件夹' : res.message,
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
        res.success ? '歌词文件已保存至 AquaMoon 文件夹' : res.message,
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
      AppToast.show(context, '歌词已复制到剪贴板', icon: Icons.copy_rounded);
    }
  }

  Future<void> _toggleFavorite(Song song) async {
    final res = await ref
        .read(qqMusicFavoritesProvider.notifier)
        .toggleFavorite(song);
    if (mounted && res.toastMessage != null) {
      AppToast.show(
        context,
        res.toastMessage!,
        icon: res.isFavorite
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
      );
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
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isSplitStudio = size.width >= 720 && size.height >= 500;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
        children: [
          // 三段式水墨宣纸渐变底幕
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.46, 1.0],
                colors: appColors.playerGradient,
              ),
            ),
          ),
          // 柔和晕染光晕（跟随主题主色，随宽窄屏自适应定位）
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: isSplitStudio
                        ? const Alignment(-0.52, -0.15)
                        : const Alignment(0.0, -0.32),
                    radius: isSplitStudio ? 0.78 : 0.85,
                    colors: [
                      colorScheme.primary.withValues(
                        alpha: isLight ? 0.09 : 0.14,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: isSplitStudio
                ? _buildSplitStudioLayout(
                    context: context,
                    song: song,
                    isPlaying: isPlaying,
                    isBuffering: isBuffering,
                    playbackMode: playbackMode,
                    screenSize: size,
                  )
                : _buildMobileLayout(
                    context: context,
                    song: song,
                    isPlaying: isPlaying,
                    isBuffering: isBuffering,
                    playbackMode: playbackMode,
                    screenSize: size,
                  ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  /// 桌面/平板分栏播放舞台：左侧封面与播控，右侧常驻水墨渐隐滚动歌词。
  Widget _buildSplitStudioLayout({
    required BuildContext context,
    required Song song,
    required bool isPlaying,
    required bool isBuffering,
    required PlaybackMode playbackMode,
    required Size screenSize,
  }) {
    final theme = Theme.of(context);
    final coverSize = min(
      min(screenSize.width * 0.30, screenSize.height * 0.42),
      320.0,
    ).clamp(180.0, 320.0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 30,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                tooltip: '收起播放页',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              AquaMoonMark(size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  song.album.isNotEmpty ? song.album : '正在聆听',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _buildMoreMenuButton(context, song),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildArtworkFrame(
                            context,
                            song: song,
                            size: coverSize,
                            isPlaying: isPlaying,
                          ),
                          const SizedBox(height: 28),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: coverSize + 40),
                            child: _buildTrackMetaRow(context, song),
                          ),
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: coverSize + 88),
                            child: const _FullPlayerProgressBar(),
                          ),
                          const _SleepTimerChip(),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: coverSize + 56),
                            child: _buildControlsRow(
                              context,
                              isPlaying: isPlaying,
                              isBuffering: isBuffering,
                              playbackMode: playbackMode,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 6,
                      child: LyricsView(song: song),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 手机端沉浸播放页：顶部「封面 / 歌词」轻胶囊切换，封面页下置标题收藏触手可及。
  Widget _buildMobileLayout({
    required BuildContext context,
    required Song song,
    required bool isPlaying,
    required bool isBuffering,
    required PlaybackMode playbackMode,
    required Size screenSize,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverSize = min(
      min(screenSize.width * 0.76, screenSize.height * 0.37),
      320.0,
    ).clamp(190.0, 320.0);

    return Column(
      children: [
        // 顶部栏：返回 | 封面 / 歌词 胶囊 | 更多菜单
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 30,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: '收起播放页',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                _buildPageModePill(context),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildMoreMenuButton(context, song),
                ),
              ],
            ),
          ),
        ),

        // 中部滑动区：封面舞台 ↔ 滚动歌词
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
            children: [
              // Page 0: 封面 + 歌曲信息 + 收藏 + 双行歌词预览
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _buildArtworkFrame(
                      context,
                      song: song,
                      size: coverSize,
                      isPlaying: isPlaying,
                    ),
                    const Spacer(flex: 2),
                    _buildTrackMetaRow(context, song),
                    const SizedBox(height: 16),
                    _FullPlayerLyricPreview(
                      primaryTextColor: colorScheme.onSurface,
                      secondaryTextColor: colorScheme.onSurfaceVariant,
                      onTap: () => _animateToPage(1),
                    ),
                    const Spacer(flex: 1),
                  ],
                ),
              ),

              // Page 1: 紧凑曲目头 + 全屏滚动歌词
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 16, 4),
                    child: Row(
                      children: [
                        SongArtwork(song: song, size: 36, borderRadius: 8),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildFavoriteButton(context, song),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TickerMode(
                      enabled: _currentPage == 1,
                      child: LyricsView(
                        song: song,
                        onTapBackground: () => _animateToPage(0),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // 进度条（局部重绘隔离）
        const _FullPlayerProgressBar(),

        // 睡眠定时器徽标
        const _SleepTimerChip(),

        const SizedBox(height: 10),

        // 底部五键控制舱
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: _buildControlsRow(
            context,
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            playbackMode: playbackMode,
          ),
        ),

        const SizedBox(height: 22),
      ],
    );
  }

  Widget _buildPageModePill(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;

    Widget tabButton(String label, int index) {
      final selected = _currentPage == index;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _animateToPage(index),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: motionDuration(
                context,
                const Duration(milliseconds: 220),
              ),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.surface.withValues(
                        alpha: isLight ? 0.92 : 0.85,
                      )
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isLight ? 0.06 : 0.25,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(
          alpha: isLight ? 0.06 : 0.10,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: appColors.glassBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [tabButton('封面', 0), tabButton('歌词', 1)],
      ),
    );
  }

  /// 带轻盈播放呼吸缩放与宣纸微框的唱片封面。
  Widget _buildArtworkFrame(
    BuildContext context, {
    required Song song,
    required double size,
    required bool isPlaying,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return RepaintBoundary(
      child: AnimatedScale(
        scale: (isPlaying || reduceMotion) ? 1.0 : 0.935,
        duration: motionDuration(context, const Duration(milliseconds: 420)),
        curve: Curves.easeOutCubic,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: isLight ? 0.55 : 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.14 : 0.48),
                blurRadius: isPlaying ? 36 : 20,
                offset: Offset(0, isPlaying ? 18 : 10),
              ),
              BoxShadow(
                color: theme.colorScheme.primary.withValues(
                  alpha: isLight ? 0.11 : 0.22,
                ),
                blurRadius: 42,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Hero(
            tag: 'player_artwork',
            child: SongArtwork(song: song, size: size, borderRadius: 19),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackMetaRow(BuildContext context, Song song) {
    final theme = Theme.of(context);
    final subtitle =
        song.album.isNotEmpty &&
            song.album != song.title &&
            song.album != song.artist
        ? '${song.artist} · ${song.album}'
        : song.artist;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildFavoriteButton(context, song),
      ],
    );
  }

  Widget _buildFavoriteButton(BuildContext context, Song song) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    return IconButton(
      tooltip: song.isFavorite ? '取消收藏' : '收藏',
      icon: AnimatedSwitcher(
        duration: motionDuration(context, const Duration(milliseconds: 220)),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          song.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          key: ValueKey(song.isFavorite),
          size: 24,
          color: song.isFavorite
              ? appColors.favorite
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onPressed: () => _toggleFavorite(song),
    );
  }

  Widget _buildControlsRow(
    BuildContext context, {
    required bool isPlaying,
    required bool isBuffering,
    required PlaybackMode playbackMode,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isModeHighlighted = playbackMode != PlaybackMode.sequence;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. 循环模式（Stack 置底小圆点，保持五键中轴严格水平对齐）
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _getModeIcon(playbackMode),
                  size: 23,
                  color: isModeHighlighted
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.72),
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
              Positioned(
                bottom: 5,
                child: AnimatedContainer(
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 200),
                  ),
                  width: isModeHighlighted ? 4 : 0,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. 上一首
        IconButton(
          icon: Icon(
            Icons.skip_previous_rounded,
            size: 34,
            color: colorScheme.onSurface,
          ),
          tooltip: '上一首',
          onPressed: () => ref.read(audioControllerProvider).previous(),
        ),

        // 3. 印章雕塑感主播放/暂停圆钮
        Tooltip(
          message: isPlaying ? '暂停' : '播放',
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: colorScheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () =>
                    ref.read(audioControllerProvider).togglePlayPause(),
                child: Center(
                  child: isBuffering
                      ? SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.8,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: motionDuration(
                            context,
                            const Duration(milliseconds: 180),
                          ),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey(isPlaying),
                            size: 36,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),

        // 4. 下一首
        IconButton(
          icon: Icon(
            Icons.skip_next_rounded,
            size: 34,
            color: colorScheme.onSurface,
          ),
          tooltip: '下一首',
          onPressed: () => ref.read(audioControllerProvider).next(),
        ),

        // 5. 播放队列
        IconButton(
          icon: Icon(
            Icons.playlist_play_rounded,
            size: 27,
            color: colorScheme.onSurface.withValues(alpha: 0.82),
          ),
          tooltip: '播放队列',
          onPressed: () => _showQueueModal(context),
        ),
      ],
    );
  }

  Widget _buildMoreMenuButton(BuildContext context, Song song) {
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 22,
        color: secondaryTextColor,
      ),
      tooltip: '更多操作与下载',
      onSelected: (action) async {
        switch (action) {
          case 'sleep_timer':
            _showSleepTimerSheet();
            break;
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
            final selected = await OnlineCandidateSelectDialog.show(
              context,
              song,
            );
            if (selected != null) {
              // Hoist every provider access above the await-heavy section:
              // the page can be popped while the cover downloads, and
              // riverpod throws on ref use after dispose.
              final library = ref.read(libraryNotifierProvider.notifier);
              final handler = ref.read(audioHandlerProvider);
              final lyricsNotifier = ref.read(lyricsNotifierProvider.notifier);
              final onlineService = ref.read(onlineMetadataServiceProvider);
              String? newArtUri = song.albumArtUri;
              if (selected.coverUrl != null && selected.coverUrl!.isNotEmpty) {
                newArtUri = await onlineService.cacheOnlineImage(
                  selected.coverUrl!,
                );
              }
              final newLrc = selected.syncedLyrics ?? selected.plainLyrics;

              final applied = await library.updateSongMerged(song.id, (
                current,
              ) {
                return current.copyWith(
                  title: selected.title,
                  artist: selected.artist,
                  album: selected.album.isNotEmpty
                      ? selected.album
                      : current.album,
                  albumArtUri: newArtUri,
                  lrcContent: newLrc,
                );
              });
              if (applied == null) break;
              final updated = applied;

              handler.updateCurrentSongMetadata(
                title: updated.title,
                artist: updated.artist,
                album: updated.album,
                albumArtUri: updated.albumArtUri,
                lrcContent: updated.lrcContent,
              );
              lyricsNotifier.loadLyricsForSong(updated);
              if (context.mounted) {
                AppToast.show(
                  context,
                  '已应用来自 ${selected.source} 的元数据',
                  icon: Icons.check_circle_outline_rounded,
                );
              }
            }
            break;
          case 'global_online_search':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    OnlineSearchPage(initialQuery: '${song.title} ${song.artist}'),
              ),
            );
            break;
          case 'edit_song':
            EditSongDialog.show(context, song);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'sleep_timer',
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 18),
              SizedBox(width: 10),
              Text('睡眠定时器'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'save_cover',
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: 18),
              SizedBox(width: 10),
              Text('保存当前封面图片'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export_lyrics',
          child: Row(
            children: [
              Icon(Icons.lyrics_outlined, size: 18),
              SizedBox(width: 10),
              Text('导出当前歌词 (.lrc)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_lyrics',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18),
              SizedBox(width: 10),
              Text('复制歌词文本'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'online_calibrate',
          child: Row(
            children: [
              Icon(Icons.saved_search_rounded, size: 18),
              SizedBox(width: 10),
              Text('在线检索与更换数据'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'global_online_search',
          child: Row(
            children: [
              Icon(Icons.cloud_download_rounded, size: 18),
              SizedBox(width: 10),
              Text('全网在线歌曲检索'),
            ],
          ),
        ),
        PopupMenuItem(
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

  void _showSleepTimerSheet() {
    final options = [
      (label: '15 分钟', duration: const Duration(minutes: 15)),
      (label: '30 分钟', duration: const Duration(minutes: 30)),
      (label: '60 分钟', duration: const Duration(minutes: 60)),
      (label: '90 分钟', duration: const Duration(minutes: 90)),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return GlassContainer(
          enableBlur: false,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            top: false,
            child: Consumer(
              builder: (context, sheetRef, _) {
                final remaining = sheetRef.watch(
                  sleepTimerStreamProvider.select((v) => v.valueOrNull),
                );
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ModalSheetHeader(
                        leading: Icon(
                          Icons.bedtime_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text(
                          '睡眠定时器',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailingActions: [
                          if (remaining != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '${remaining.inMinutes}分${(remaining.inSeconds % 60).toString().padLeft(2, '0')}秒后停止',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Divider(height: 1),
                    ...List.generate(options.length, (i) {
                      final option = options[i];
                      return ListTile(
                        leading: const Icon(Icons.timelapse_rounded, size: 20),
                        title: Text(
                          option.label,
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: () {
                          ref
                              .read(audioControllerProvider)
                              .startSleepTimer(option.duration);
                          Navigator.pop(sheetContext);
                          AppToast.show(
                            context,
                            '将在${option.label}后停止播放',
                            icon: Icons.bedtime_outlined,
                          );
                        },
                      );
                    }),
                    ListTile(
                      enabled: remaining != null,
                      leading: Icon(
                        Icons.cancel_outlined,
                        size: 20,
                        color: remaining != null
                            ? theme.colorScheme.error
                            : null,
                      ),
                      title: Text(
                        '关闭定时器',
                        style: TextStyle(
                          fontSize: 14,
                          color: remaining != null
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                      onTap: remaining == null
                          ? null
                          : () {
                              ref
                                  .read(audioControllerProvider)
                                  .cancelSleepTimer();
                              Navigator.pop(sheetContext);
                              AppToast.show(
                                context,
                                '已关闭睡眠定时器',
                                icon: Icons.cancel_outlined,
                              );
                            },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showQueueModal(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final queueAsync = ref.watch(playlistQueueStreamProvider);
          final currentSongAsync = ref.watch(currentSongProvider);
          final isPlaying = ref.watch(
            playbackStateStreamProvider.select(
              (s) => s.valueOrNull?.playing ?? false,
            ),
          );
          final queue = queueAsync.valueOrNull ?? [];
          final currentSong = currentSongAsync.valueOrNull;

          return DraggableScrollableSheet(
            initialChildSize: 0.62,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (context, scrollController) {
              return GlassContainer(
                enableBlur: false,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Column(
                  children: [
                    ModalSheetHeader(
                      title: Text(
                        '当前播放队列 (${queue.length})',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      trailingActions: [
                        TextButton(
                          onPressed: queue.isEmpty
                              ? null
                              : () async {
                                  final confirmed =
                                      await showDestructiveConfirmDialog(
                                    context,
                                    title: '清空播放队列？',
                                    message: '将移除队列中的全部歌曲并停止播放，此操作不可撤销。',
                                    confirmLabel: '清空',
                                  );
                                  if (confirmed && context.mounted) {
                                    ref
                                        .read(audioControllerProvider)
                                        .clearQueue();
                                    Navigator.of(context).pop();
                                  }
                                },
                          child: Text(
                            '清空队列',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: queue.isEmpty
                          ? Center(
                              child: Text(
                                '队列为空',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
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
                                  // key 不含 index：拖拽重排时行号会变，
                                  // 含 index 的 key 会让拖拽中的条目身份跳变。
                                  key: ValueKey('queue_song_${s.id}'),
                                  leading: SongArtwork(
                                    song: s,
                                    size: 42,
                                    borderRadius: 8,
                                  ),
                                  title: Row(
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
                                          s.title,
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
                                  subtitle: Text(
                                    s.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: '从队列移除',
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 19,
                                      color: theme.colorScheme.onSurfaceVariant,
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 睡眠定时器倒计时小徽标；未启用时不占位。
class _SleepTimerChip extends ConsumerWidget {
  const _SleepTimerChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(
      sleepTimerStreamProvider.select((v) => v.valueOrNull),
    );
    if (remaining == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    final label = remaining.inHours > 0
        ? '${remaining.inHours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: true,
        label: '睡眠定时器 $label 后停止，点击取消',
        child: Tooltip(
          message: '点击取消睡眠定时器',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => ref.read(audioControllerProvider).cancelSleepTimer(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bedtime_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$label 后停止',
                        style: TextStyle(
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面页底部双行同步歌词预览：当前句清朗、下句微淡，轻点即切换完整歌词。
class _FullPlayerLyricPreview extends ConsumerWidget {
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final VoidCallback onTap;

  const _FullPlayerLyricPreview({
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final activeLyricIndex = ref.watch(currentLyricIndexProvider);

    String activeLyricText = '纯音乐，静心聆听';
    String? nextLyricText;

    if (lyricsState.lines.isNotEmpty) {
      final resolvedIndex = activeLyricIndex >= 0 &&
              activeLyricIndex < lyricsState.lines.length
          ? activeLyricIndex
          : 0;
      activeLyricText = lyricsState.lines[resolvedIndex].text;
      if (resolvedIndex + 1 < lyricsState.lines.length) {
        nextLyricText = lyricsState.lines[resolvedIndex + 1].text;
      }
    } else if (lyricsState.plainText != null &&
        lyricsState.plainText!.trim().isNotEmpty) {
      final raw = lyricsState.plainText!;
      String? first;
      String? second;
      var lineStart = 0;
      while (lineStart <= raw.length) {
        final nl = raw.indexOf('\n', lineStart);
        final lineEnd = nl == -1 ? raw.length : nl;
        final line = raw.substring(lineStart, lineEnd).trim();
        if (line.isNotEmpty) {
          if (first == null) {
            first = line;
          } else {
            second = line;
            break;
          }
        }
        if (nl == -1) break;
        lineStart = nl + 1;
      }
      if (first != null) {
        activeLyricText = first;
        nextLyricText = second;
      }
    }

    return Semantics(
      button: true,
      label: '切换到歌词视图',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: motionDuration(
                      context,
                      const Duration(milliseconds: 260),
                    ),
                    child: Text(
                      activeLyricText,
                      key: ValueKey(activeLyricText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor.withValues(alpha: 0.94),
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(
                    duration: motionDuration(
                      context,
                      const Duration(milliseconds: 260),
                    ),
                    child: Text(
                      nextLyricText ?? '轻触查看完整歌词',
                      key: ValueKey(nextLyricText ?? '__hint__'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: secondaryTextColor.withValues(alpha: 0.82),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    // RepaintBoundary keeps the per-tick progress repaints from dirtying the
    // cover / lyrics / controls above.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: RepaintBoundary(
        child: CustomProgressBar(
          progress: progress,
          onSeek: (pos) => ref.read(audioControllerProvider).seek(pos),
        ),
      ),
    );
  }
}
