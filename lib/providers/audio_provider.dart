import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_player_handler.dart';
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

class AudioPlayerController {
  final SoundCraftAudioHandler _handler;

  AudioPlayerController(this._handler);

  Future<void> playSong(Song song, {List<Song>? queue}) =>
      _handler.playSong(song, contextQueue: queue);

  Future<void> playAtIndex(int index) => _handler.playAtIndex(index);

  Future<void> togglePlayPause() async {
    if (_handler.playbackState.value.playing) {
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
}

final audioControllerProvider = Provider<AudioPlayerController>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return AudioPlayerController(handler);
});
