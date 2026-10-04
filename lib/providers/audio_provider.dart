import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_player_handler.dart';
import '../models/audio_effects.dart';
import '../models/playback_mode.dart';
import '../models/playback_progress.dart';
import '../models/song.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError(
    'StorageService must be overridden in ProviderScope',
  );
});

final audioHandlerProvider = Provider<SoundCraftAudioHandler>((ref) {
  throw UnimplementedError('AudioHandler must be overridden in ProviderScope');
});

final currentSongProvider = StreamProvider<Song?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.currentSongStream;
});

final playbackStateStreamProvider = StreamProvider<PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackState;
});

final playbackModeStreamProvider = StreamProvider<PlaybackMode>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackModeStream;
});

final playlistQueueStreamProvider = StreamProvider<List<Song>>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playlistStream;
});

final playbackProgressStreamProvider = StreamProvider<PlaybackProgress>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.progressStream;
});

final playbackErrorStreamProvider = StreamProvider<String>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackErrorStream;
});

/// 睡眠定时器剩余时间；`null` 表示未启用。
final sleepTimerStreamProvider = StreamProvider<Duration?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.sleepTimerStream;
});

class AudioPlayerController {
  final SoundCraftAudioHandler _handler;

  AudioPlayerController(this._handler);

  Future<void> playSong(Song song, {List<Song>? queue}) =>
      _handler.playSong(song, contextQueue: queue);

  Future<void> playAtIndex(int index) => _handler.playAtIndex(index);

  Future<void> togglePlayPause() async {
    // 用 handler 的同步播放状态判断：playbackState 的流式更新滞后
    // （开启淡入淡出时暂停会先渐变 ~240ms），快速连点会读到旧值。
    if (_handler.isPlaying) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> play() => _handler.play();
  Future<void> pause() => _handler.pause();
  Future<void> stop() => _handler.stop();
  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();
  Future<void> seek(Duration position) => _handler.seek(position);

  void togglePlaybackMode() => _handler.togglePlaybackMode();
  void setPlaybackMode(PlaybackMode mode) => _handler.setPlaybackMode(mode);
  Future<void> setVolume(double volume) => _handler.setVolume(volume);
  Future<void> setSpeed(double speed) => _handler.setSpeed(speed);

  void removeQueueItem(int index) => _handler.removeSongFromQueue(index);
  void reorderQueue(int oldIndex, int newIndex) =>
      _handler.reorderQueue(oldIndex, newIndex);
  void clearQueue() => _handler.clearQueue();

  /// 把歌曲插到当前歌曲之后播放。
  Future<void> playNext(Song song) => _handler.playNext(song);

  // --- Sleep timer ---

  Stream<Duration?> get sleepTimerStream => _handler.sleepTimerStream;
  Duration? get sleepTimerRemaining => _handler.sleepTimerRemaining;
  void startSleepTimer(Duration duration) =>
      _handler.startSleepTimer(duration);
  void cancelSleepTimer() => _handler.cancelSleepTimer();

  // --- Audio effects ---

  bool get fadeEnabled => _handler.fadeEnabled;
  Future<void> setFadeEnabled(bool enabled) =>
      _handler.setFadeEnabled(enabled);
  dynamic get equalizer => _handler.equalizer;
  Future<void> setEqualizerEnabled(bool enabled) =>
      _handler.setEqualizerEnabled(enabled);
  Future<void> setEqualizerGains(List<double> gains) =>
      _handler.setEqualizerGains(gains);
  Future<EqualizerSnapshot?> loadEqualizerSnapshot() =>
      _handler.loadEqualizerSnapshot();
  Future<void> setEqualizerBandGain(int index, double gain) =>
      _handler.setEqualizerBandGain(index, gain);

  /// 是否支持均衡器（仅 Android 构建了音频管线时为 true）。
  bool get equalizerSupported => _handler.equalizer != null;
}

final audioControllerProvider = Provider<AudioPlayerController>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return AudioPlayerController(handler);
});
