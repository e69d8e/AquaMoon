import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/audio_provider.dart';
import '../widgets/song_artwork.dart';
import 'full_player_page.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSongAsync = ref.watch(currentSongProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);
    final progressAsync = ref.watch(playbackProgressStreamProvider);

    final song = currentSongAsync.valueOrNull;
    if (song == null) {
      return const SizedBox.shrink();
    }

    final isPlaying = playbackStateAsync.valueOrNull?.playing ?? false;
    final progress = progressAsync.valueOrNull;
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => const FullPlayerPage(),
            transitionsBuilder: (context, anim1, anim2, child) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              const curve = Curves.easeOutCubic;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(position: anim1.drive(tween), child: child);
            },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isLight
              ? theme.colorScheme.surface.withValues(alpha: 0.94)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLight ? const Color(0x0F000000) : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isLight ? const Color(0x14000000) : Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Hero(
                      tag: 'player_artwork',
                      child: SongArtwork(
                        song: song,
                        size: 46,
                        borderRadius: 10,
                      ),
                    ),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
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

                    // Controls row: Previous, Play/Pause, Next
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 26),
                      color: theme.colorScheme.onSurface,
                      tooltip: '上一首',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(audioControllerProvider).previous();
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                        size: 38,
                        color: theme.colorScheme.primary,
                      ),
                      tooltip: isPlaying ? '暂停' : '播放',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(audioControllerProvider).togglePlayPause();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 26),
                      color: theme.colorScheme.onSurface,
                      tooltip: '下一首',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(audioControllerProvider).next();
                      },
                    ),
                  ],
                ),
              ),
              // Bottom border thin progress indicator
              if (progress != null)
                LinearProgressIndicator(
                  value: progress.progressRatio,
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
