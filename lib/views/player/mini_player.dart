import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../widgets/aquamoon_mark.dart';
import '../widgets/glass_container.dart';
import '../widgets/song_artwork.dart';
import 'full_player_page.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  void _openFullPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, anim1, anim2) => const FullPlayerPage(),
        transitionsBuilder: (context, anim1, anim2, child) {
          final slideTween = Tween(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: anim1.drive(slideTween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSongAsync = ref.watch(currentSongProvider);
    final song = currentSongAsync.valueOrNull;
    if (song == null) {
      return const SizedBox.shrink();
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 660 : double.infinity,
        ),
        child: GestureDetector(
          onTap: () => _openFullPlayer(context),
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -240) {
              _openFullPlayer(context);
            }
          },
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -260) {
              ref.read(audioControllerProvider).next();
            } else if (v > 260) {
              ref.read(audioControllerProvider).previous();
            }
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 24 : 12,
              6,
              isWide ? 24 : 12,
              isWide ? 14 : 8,
            ),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(18),
              blurSigma: 26,
              tint: theme.colorScheme.surface.withValues(
                alpha: isLight ? 0.84 : 0.76,
              ),
              shadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.34),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'player_artwork',
                          child: SongArtwork(
                            song: song,
                            size: 46,
                            borderRadius: 11,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (isPlaying) ...[
                                    PlayingWaveIndicator(
                                      isPlaying: true,
                                      size: 12,
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
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.15,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 24,
                          ),
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.85,
                          ),
                          tooltip: '上一首',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(audioControllerProvider).previous();
                          },
                        ),
                        const SizedBox(width: 2),
                        // 印章感圆钮：与全屏播放页主按钮形成视觉呼应。
                        Tooltip(
                          message: isPlaying ? '暂停' : '播放',
                          child: Material(
                            color: theme.colorScheme.primary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                ref
                                    .read(audioControllerProvider)
                                    .togglePlayPause();
                              },
                              child: SizedBox(
                                width: 38,
                                height: 38,
                                child: Center(
                                  child: isBuffering
                                      ? SizedBox(
                                          width: 17,
                                          height: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                        )
                                      : Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          size: 23,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 24),
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.85,
                          ),
                          tooltip: '下一首',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(audioControllerProvider).next();
                          },
                        ),
                      ],
                    ),
                  ),
                  const _MiniPlayerProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerProgressIndicator extends ConsumerWidget {
  const _MiniPlayerProgressIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressRatio = ref.watch(
      playbackProgressStreamProvider.select(
        (p) => p.valueOrNull?.progressRatio ?? 0.0,
      ),
    );
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    // RepaintBoundary keeps the ~3x/second progress repaints local to this
    // 2.5px indicator instead of dirtying the whole mini-player layer.
    return RepaintBoundary(
      child: LinearProgressIndicator(
        value: progressRatio,
        minHeight: 2.5,
        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
      ),
    );
  }
}
