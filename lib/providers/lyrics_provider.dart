import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_player_handler.dart';
import '../core/utils/lrc_parser.dart';
import '../models/lyric_line.dart';
import '../models/song.dart';
import '../services/online_metadata_service.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

final onlineMetadataServiceProvider = Provider<OnlineMetadataService>((ref) {
  final service = OnlineMetadataService();
  ref.onDispose(() => service.dispose());
  return service;
});

class LyricsState {
  final List<LyricLine> lines;
  final String? plainText;
  final bool isLoading;
  final String? error;
  final bool isSynced;
  final String? songId;

  const LyricsState({
    this.lines = const [],
    this.plainText,
    this.isLoading = false,
    this.error,
    this.isSynced = false,
    this.songId,
  });

  LyricsState copyWith({
    List<LyricLine>? lines,
    String? plainText,
    bool? isLoading,
    String? error,
    bool? isSynced,
    String? songId,
  }) {
    return LyricsState(
      lines: lines ?? this.lines,
      plainText: plainText ?? this.plainText,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isSynced: isSynced ?? this.isSynced,
      songId: songId ?? this.songId,
    );
  }
}

class LyricsNotifier extends StateNotifier<LyricsState> {
  final OnlineMetadataService _onlineService;
  final Ref _ref;

  LyricsNotifier(this._onlineService, this._ref) : super(const LyricsState()) {
    _ref.listen<AsyncValue<Song?>>(currentSongProvider, (prev, next) {
      final song = next.valueOrNull;
      if (song != null && song.id != state.songId) {
        loadLyricsForSong(song);
      } else if (song == null) {
        state = const LyricsState();
      }
    });
  }

  Future<void> loadLyricsForSong(Song song, {bool forceOnline = false}) async {
    state = state.copyWith(isLoading: true, songId: song.id, error: null);

    // 1. If song already has cached LRC content and not forcing online refresh
    if (!forceOnline &&
        song.lrcContent != null &&
        song.lrcContent!.trim().isNotEmpty) {
      final parsed = LrcParser.parse(song.lrcContent);
      if (parsed.isNotEmpty) {
        state = LyricsState(
          lines: parsed,
          isLoading: false,
          isSynced: true,
          songId: song.id,
        );
        return;
      } else {
        // May be plain lyrics
        state = LyricsState(
          plainText: song.lrcContent,
          isLoading: false,
          isSynced: false,
          songId: song.id,
        );
        return;
      }
    }

    // 2. Fetch online
    try {
      final result = await _onlineService.fetchMetadata(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
      );

      if (result != null) {
        String? lrcContent = result.syncedLyrics ?? result.plainLyrics;

        // Cache online cover art if local song lacks cover. Skipped when the
        // user already moved on to another song — don't pay for the download.
        String? newArtUri = song.albumArtUri;
        if (state.songId == song.id &&
            (newArtUri == null || newArtUri.isEmpty) &&
            result.coverUrl != null) {
          newArtUri = await _onlineService.cacheOnlineImage(result.coverUrl!);
        }

        // Persist whatever this fetch produced even if the user switched
        // songs mid-request: a match already paid for with a network round
        // trip must land in the library record, otherwise the next playback
        // silently repeats the same online lookup.
        final hasNewData =
            lrcContent != null ||
            (newArtUri != null && newArtUri != song.albumArtUri);
        if (hasNewData) {
          _ref
              .read(libraryNotifierProvider.notifier)
              .updateSong(
                song.copyWith(lrcContent: lrcContent, albumArtUri: newArtUri),
              );
        }

        // The UI state (and handler metadata) only follows the fetch while
        // this song is still the one being displayed. state.songId moves on
        // as soon as another song starts loading.
        if (state.songId != song.id) {
          return;
        }

        SoundCraftAudioHandler? handler;
        try {
          handler = _ref.read(audioHandlerProvider);
        } catch (_) {}
        final currentActive = _ref.read(currentSongProvider).valueOrNull;
        if (currentActive?.id == song.id) {
          handler?.updateCurrentSongMetadata(
            albumArtUri: newArtUri,
            lrcContent: lrcContent,
          );
        }

        if (result.syncedLyrics != null) {
          final parsed = LrcParser.parse(result.syncedLyrics);
          state = LyricsState(
            lines: parsed,
            isLoading: false,
            isSynced: true,
            songId: song.id,
          );
          return;
        } else if (result.plainLyrics != null) {
          state = LyricsState(
            plainText: result.plainLyrics,
            isLoading: false,
            isSynced: false,
            songId: song.id,
          );
          return;
        }
      }

      if (state.songId == song.id) {
        state = LyricsState(
          lines: const [],
          isLoading: false,
          error: '暂无歌词',
          songId: song.id,
        );
      }
    } catch (_) {
      if (state.songId == song.id) {
        state = LyricsState(
          lines: const [],
          isLoading: false,
          error: '网络异常，获取歌词失败',
          songId: song.id,
        );
      }
    }
  }
}

final lyricsNotifierProvider =
    StateNotifierProvider<LyricsNotifier, LyricsState>((ref) {
      final onlineService = ref.watch(onlineMetadataServiceProvider);
      return LyricsNotifier(onlineService, ref);
    });

/// autoDispose: only the full-player lyrics UI watches this. Keeping it
/// non-autoDispose would pin a playbackProgressStream subscription for the
/// whole app lifetime and re-run the binary search on every position tick
/// (~3x/second) even when no lyrics are visible.
final currentLyricIndexProvider = Provider.autoDispose<int>((ref) {
  final lyricsState = ref.watch(lyricsNotifierProvider);
  if (!lyricsState.isSynced || lyricsState.lines.isEmpty) {
    return -1;
  }

  final progressAsync = ref.watch(playbackProgressStreamProvider);
  final position = progressAsync.valueOrNull?.position ?? Duration.zero;

  return LrcParser.findCurrentIndex(lyricsState.lines, position);
});
