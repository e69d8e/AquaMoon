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

  /// Loads lyrics for [song]; when [forceOnline] is set, always fetches from
  /// the network and replaces cached lyrics.
  ///
  /// Returns an error message on failure, `null` on success — so callers
  /// triggering a manual match for a non-playing song can toast the outcome
  /// without reading (stale) shared state afterwards.
  Future<String?> loadLyricsForSong(Song song, {bool forceOnline = false}) async {
    // 只有正在播放（或尚未播放任何歌）时才接管共享的歌词状态；对曲库中
    // 其他歌手动“匹配歌词”不应把全屏播放器的歌词页换成那首歌的内容。
    final currentActive = _ref.read(currentSongProvider).valueOrNull;
    final isDisplayTarget = currentActive == null || currentActive.id == song.id;
    if (isDisplayTarget) {
      // copyWith 的 error: null 是 no-op，无法清掉上一首的错误/纯文本残留，
      // 这里直接用全新状态。
      state = LyricsState(isLoading: true, songId: song.id);
    }

    // 1. If song already has cached LRC content and not forcing online refresh
    if (!forceOnline &&
        song.lrcContent != null &&
        song.lrcContent!.trim().isNotEmpty) {
      final parsed = LrcParser.parse(song.lrcContent);
      if (parsed.isNotEmpty) {
        if (isDisplayTarget) {
          state = LyricsState(
            lines: parsed,
            isLoading: false,
            isSynced: true,
            songId: song.id,
          );
        }
        return null;
      } else {
        // May be plain lyrics
        if (isDisplayTarget) {
          state = LyricsState(
            plainText: song.lrcContent,
            isLoading: false,
            isSynced: false,
            songId: song.id,
          );
        }
        return null;
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
        // silently repeats the same online lookup. Merged onto the freshest
        // stored copy so the stale [song] snapshot can't revert playCount /
        // isFavorite / lyrics saved meanwhile.
        final hasNewData =
            lrcContent != null ||
            (newArtUri != null && newArtUri != song.albumArtUri);
        if (hasNewData) {
          await _ref
              .read(libraryNotifierProvider.notifier)
              .updateSongMerged(
                song.id,
                (current) => current.copyWith(
                  // 手动重新匹配用检索结果替换；自动补齐只填空缺，
                  // 不覆盖刚保存过的歌词。
                  lrcContent: forceOnline
                      ? lrcContent
                      : (current.lrcContent ?? lrcContent),
                  albumArtUri: current.albumArtUri ?? newArtUri,
                ),
              );
        }

        // The UI state (and handler metadata) only follows the fetch while
        // this song is still the one being displayed. state.songId moves on
        // as soon as another song starts loading.
        if (!isDisplayTarget || state.songId != song.id) {
          return null;
        }

        SoundCraftAudioHandler? handler;
        try {
          handler = _ref.read(audioHandlerProvider);
        } catch (_) {}
        final currentActiveNow = _ref.read(currentSongProvider).valueOrNull;
        if (currentActiveNow?.id == song.id) {
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
          return null;
        } else if (result.plainLyrics != null) {
          state = LyricsState(
            plainText: result.plainLyrics,
            isLoading: false,
            isSynced: false,
            songId: song.id,
          );
          return null;
        }
      }

      if (isDisplayTarget && state.songId == song.id) {
        state = LyricsState(
          lines: const [],
          isLoading: false,
          error: '暂无歌词',
          songId: song.id,
        );
      }
      return '暂无歌词';
    } catch (_) {
      if (isDisplayTarget && state.songId == song.id) {
        state = LyricsState(
          lines: const [],
          isLoading: false,
          error: '网络异常，获取歌词失败',
          songId: song.id,
        );
      }
      return '网络异常，获取歌词失败';
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

/// 当前行内已被"点亮"的文字比例（0.0–1.0），仅增强型逐字歌词返回非 null。
/// autoDispose 与 currentLyricIndexProvider 同生命周期。
final currentLyricLitFractionProvider = Provider.autoDispose<double?>((ref) {
  final lyricsState = ref.watch(lyricsNotifierProvider);
  final index = ref.watch(currentLyricIndexProvider);
  if (index < 0 || index >= lyricsState.lines.length) return null;

  final progressAsync = ref.watch(playbackProgressStreamProvider);
  final position = progressAsync.valueOrNull?.position ?? Duration.zero;

  return LrcParser.litFraction(lyricsState.lines[index], position);
});
