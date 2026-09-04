import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../../models/song.dart';
import '../../models/playback_mode.dart';
import '../../models/playback_progress.dart';
import '../../services/listening_stats_tracker.dart';
import '../../services/storage_service.dart';
import 'audio_session_coordinator.dart';
import 'custom_notification_service.dart';

class SoundCraftAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final StorageService _storageService;
  late final ListeningStatsTracker _statsTracker;
  AudioSessionCoordinator? _sessionCoordinator;

  List<Song> _playlist = [];
  int _currentIndex = -1;
  PlaybackMode _playbackMode = PlaybackMode.sequence;
  final List<int> _shuffleHistory = [];
  double _volume = 1.0;

  final BehaviorSubject<Song?> _currentSongSubject = BehaviorSubject<Song?>.seeded(null);
  final BehaviorSubject<PlaybackMode> _playbackModeSubject =
      BehaviorSubject<PlaybackMode>.seeded(PlaybackMode.sequence);
  final BehaviorSubject<List<Song>> _playlistSubject = BehaviorSubject<List<Song>>.seeded([]);

  ListeningStatsTracker get statsTracker => _statsTracker;

  /// Completes once the async part of handler initialisation has finished.
  /// Playback entry points await this so that the audio_service state bridge
  /// (and with it the system media notification) is fully armed before any
  /// song can start playing.
  late final Future<void> _ready;

  Stream<Song?> get currentSongStream => _currentSongSubject.stream;
  Song? get currentSong => _currentSongSubject.valueOrNull;

  Stream<PlaybackMode> get playbackModeStream => _playbackModeSubject.stream;
  PlaybackMode get playbackMode => _playbackMode;

  Stream<List<Song>> get playlistStream => _playlistSubject.stream;
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;

  Stream<PlaybackProgress> get progressStream => Rx.combineLatest3<Duration, Duration, Duration?, PlaybackProgress>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (pos, buf, dur) => PlaybackProgress(
          position: pos,
          bufferedPosition: buf,
          duration: dur ?? (currentSong != null ? currentSong!.duration : Duration.zero),
        ),
      );

  SoundCraftAudioHandler(this._storageService) {
    _statsTracker = ListeningStatsTracker(_storageService);

    // Attach the player listeners synchronously, before any async gap. The
    // audio_service notification is only shown when `playing=true` propagates
    // through playbackState; if playback started before these listeners were
    // attached (or async init failed midway), the system media notification
    // would silently never appear while audio keeps playing in-app.
    _player.playbackEventStream.listen(_broadcastPlaybackState);

    _player.playerStateStream.listen((state) {
      _broadcastPlaybackState(_player.playbackEvent);
      if (state.playing && currentSong != null &&
          (state.processingState == ProcessingState.ready || state.processingState == ProcessingState.buffering)) {
        _statsTracker.onPlay(currentSong!);
      } else if (!state.playing) {
        _statsTracker.onPause();
      }
      if (state.processingState == ProcessingState.completed) {
        _statsTracker.onPause();
        _handlePlaybackCompleted();
      }
    });

    // Save position periodically on pause/stop
    _player.positionStream.throttleTime(const Duration(seconds: 3)).listen((pos) {
      if (currentSong != null) {
        _storageService.saveLastPositionMs(pos.inMilliseconds);
      }
    });

    // Update custom notification progress bar every second during playback
    _player.positionStream.throttleTime(const Duration(seconds: 1)).listen((pos) {
      if (_player.playing && currentSong != null) {
        _syncCustomNotification(position: pos);
      }
    });

    // Initialize Custom Notification Service for Xiaomi/OEM Rom notification center
    CustomNotificationService.init(
      playPauseHandler: () {
        if (_player.playing) {
          pause();
        } else {
          play();
        }
      },
      prevHandler: skipToPrevious,
      nextHandler: skipToNext,
      closeHandler: stop,
    );

    _ready = _initAsync();
  }

  Future<void> _initAsync() async {
    try {
      _playbackMode = _storageService.getSavedPlaybackMode();
      _playbackModeSubject.add(_playbackMode);
      _volume = _storageService.getSavedVolume();
      await _player.setVolume(_volume);

      // Audio Session Coordinator (Focus / Phone Interruption / Becoming Noisy)
      final sessionCoordinator = AudioSessionCoordinator(
        onPause: pause,
        onResume: play,
        onSetVolume: (vol) => _player.setVolume(vol),
        getCurrentVolume: () => _volume,
      );
      _sessionCoordinator = sessionCoordinator;
      await sessionCoordinator.init().timeout(const Duration(seconds: 5), onTimeout: () {
        // Some OEM skins (e.g. HyperOS) can stall audio-session configuration;
        // never let it block handler readiness or playback start.
        // ignore: avoid_print
        print('[SoundCraft] audio session init timed out');
      });
    } catch (e, st) {
      // An audio-session hiccup on an OEM skin (HyperOS etc.) must never
      // break playback or the media-notification bridge. Log and continue.
      // ignore: avoid_print
      print('[SoundCraft] init warning: $e\n$st');
    }
  }

  bool _lastBroadcastPlaying = false;

  void _broadcastPlaybackState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _player.processingState;

    if (playing != _lastBroadcastPlaying) {
      // Diagnostic for the media-notification pipeline: audio_service only
      // shows the system notification when it receives playing=true.
      // Uses print() because debugPrint is compiled out in release builds;
      // shows in logcat under the "flutter" tag.
      // ignore: avoid_print
      print('[SoundCraft] pushing playing=$playing (processingState=$processingState) -> '
          '${playing ? 'system notification should appear now' : 'paused'}');
      _lastBroadcastPlaying = playing;
    }

    final controls = [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[processingState] ?? AudioProcessingState.idle,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
      ),
    );

    _syncCustomNotification(playing: playing);
  }

  void _syncCustomNotification({bool? playing, Song? overrideSong, Duration? position, Duration? duration}) {
    final isPlaying = playing ?? _player.playing;
    final song = overrideSong ?? currentSong;
    if (song != null) {
      final pos = position ?? _player.position;
      final dur = duration ?? _player.duration ?? song.duration;
      CustomNotificationService.update(
        title: song.title,
        artist: song.artist,
        albumArtUri: song.albumArtUri,
        isPlaying: isPlaying,
        positionMs: pos.inMilliseconds,
        durationMs: dur.inMilliseconds,
      );
    } else {
      CustomNotificationService.cancel();
    }
  }

  // --- Playback Control Implementation ---

  @override
  Future<void> play() async {
    await _ready;
    if (_playlist.isEmpty) return;
    if (_currentIndex < 0) {
      await playAtIndex(0);
      return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _statsTracker.onStop();
    await _player.stop();
    await CustomNotificationService.cancel();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _syncCustomNotification(position: position);
  }

  @override
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;

    if (_playbackMode == PlaybackMode.shuffle) {
      final nextIndex = _getRandomIndex();
      await playAtIndex(nextIndex);
      return;
    }

    if (_currentIndex + 1 < _playlist.length) {
      await playAtIndex(_currentIndex + 1);
    } else if (_playbackMode == PlaybackMode.repeatAll) {
      await playAtIndex(0);
    } else {
      // End of sequence playlist
      await seek(Duration.zero);
      await pause();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;

    // If more than 3 seconds into the song, restart it
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_playbackMode == PlaybackMode.shuffle && _shuffleHistory.length > 1) {
      _shuffleHistory.removeLast(); // current
      final prevIndex = _shuffleHistory.removeLast();
      await playAtIndex(prevIndex);
      return;
    }

    if (_currentIndex - 1 >= 0) {
      await playAtIndex(_currentIndex - 1);
    } else if (_playbackMode == PlaybackMode.repeatAll) {
      await playAtIndex(_playlist.length - 1);
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  Future<void> setVolume(double volume) async {
    await _ready;
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    await _storageService.saveVolume(_volume);
  }

  void setPlaybackMode(PlaybackMode mode) {
    _playbackMode = mode;
    _playbackModeSubject.add(_playbackMode);
    _storageService.savePlaybackMode(mode);
  }

  void togglePlaybackMode() {
    setPlaybackMode(_playbackMode.next());
  }

  // --- Queue & Playlist Management ---

  Future<void> loadPlaylist(List<Song> songs, {int initialIndex = 0, bool autoPlay = true}) async {
    if (songs.isEmpty) return;
    _playlist = List.from(songs);
    _playlistSubject.add(List.unmodifiable(_playlist));
    _shuffleHistory.clear();

    // Map to audio_service queue
    final mediaItems = _playlist.map(_songToMediaItem).toList();
    queue.add(mediaItems);

    await playAtIndex(initialIndex, autoPlay: autoPlay);
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((s) => s.id == song.id);
      await loadPlaylist(contextQueue, initialIndex: index >= 0 ? index : 0, autoPlay: true);
    } else {
      final existingIndex = _playlist.indexWhere((s) => s.id == song.id);
      if (existingIndex >= 0) {
        await playAtIndex(existingIndex, autoPlay: true);
      } else {
        _playlist.add(song);
        _playlistSubject.add(List.unmodifiable(_playlist));
        queue.add(_playlist.map(_songToMediaItem).toList());
        await playAtIndex(_playlist.length - 1, autoPlay: true);
      }
    }
  }

  Future<void> playAtIndex(int index, {bool autoPlay = true}) async {
    await _ready;
    if (index < 0 || index >= _playlist.length) return;

    _currentIndex = index;
    final song = _playlist[index];
    _currentSongSubject.add(song);
    _shuffleHistory.add(index);

    // ignore: avoid_print
    print('[SoundCraft] playAtIndex($index) autoPlay=$autoPlay source=${song.source} path=${song.filePath}');

    // Update audio_service MediaItem (Notification, lockscreen info)
    final mediaItem = _songToMediaItem(song);
    this.mediaItem.add(mediaItem);

    // Save to history & persistence
    await _storageService.addToHistory(song.id);
    await _storageService.saveLastPlayedSongId(song.id);

    try {
      if (song.source == SongSource.local) {
        await _player.setFilePath(song.filePath);
      } else {
        await _player.setUrl(song.filePath);
      }

      if (autoPlay) {
        await _player.play();
      }
    } catch (e) {
      // Audio playback failed (e.g. file missing or unreadable format)
      // Automatically attempt next song if available
      if (_playlist.length > 1) {
        skipToNext();
      }
    }
  }

  void updateCurrentSongMetadata({
    String? title,
    String? artist,
    String? album,
    String? albumArtUri,
    String? lrcContent,
  }) {
    if (currentSong == null) return;
    final updated = currentSong!.copyWith(
      title: title,
      artist: artist,
      album: album,
      albumArtUri: albumArtUri,
      lrcContent: lrcContent,
    );
    _playlist[_currentIndex] = updated;
    _playlistSubject.add(List.unmodifiable(_playlist));
    _currentSongSubject.add(updated);

    final item = _songToMediaItem(updated);
    mediaItem.add(item);
    _storageService.saveSong(updated);
    _syncCustomNotification(overrideSong: updated);
  }

  void syncSong(Song song) {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index >= 0) {
      _playlist[index] = song;
      _playlistSubject.add(List.unmodifiable(_playlist));
    }
    if (_currentSongSubject.valueOrNull?.id == song.id) {
      _currentSongSubject.add(song);
      final item = _songToMediaItem(song);
      mediaItem.add(item);
      _syncCustomNotification(overrideSong: song);
    }
  }

  void removeSongFromQueue(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final isCurrent = index == _currentIndex;

    _playlist.removeAt(index);
    if (_currentIndex > index) {
      _currentIndex--;
    }
    _playlistSubject.add(List.unmodifiable(_playlist));
    queue.add(_playlist.map(_songToMediaItem).toList());

    if (isCurrent) {
      if (_playlist.isNotEmpty) {
        _currentIndex = _currentIndex.clamp(0, _playlist.length - 1);
        playAtIndex(_currentIndex);
      } else {
        _currentIndex = -1;
        _currentSongSubject.add(null);
        _player.stop();
        CustomNotificationService.cancel();
      }
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;
    final clampedNewIndex = newIndex.clamp(0, _playlist.length - 1);
    if (oldIndex == clampedNewIndex) return;

    final item = _playlist.removeAt(oldIndex);
    _playlist.insert(clampedNewIndex, item);

    if (_currentIndex == oldIndex) {
      _currentIndex = clampedNewIndex;
    } else if (oldIndex < _currentIndex && clampedNewIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && clampedNewIndex <= _currentIndex) {
      _currentIndex++;
    }

    _playlistSubject.add(List.unmodifiable(_playlist));
    queue.add(_playlist.map(_songToMediaItem).toList());
  }

  void clearQueue() {
    _playlist.clear();
    _currentIndex = -1;
    _playlistSubject.add(const []);
    _currentSongSubject.add(null);
    queue.add([]);
    _player.stop();
    CustomNotificationService.cancel();
  }

  // --- Internal Helpers ---

  void _handlePlaybackCompleted() {
    switch (_playbackMode) {
      case PlaybackMode.repeatOne:
        seek(Duration.zero);
        play();
        break;
      case PlaybackMode.repeatAll:
        skipToNext();
        break;
      case PlaybackMode.shuffle:
        skipToNext();
        break;
      case PlaybackMode.sequence:
        if (_currentIndex + 1 < _playlist.length) {
          skipToNext();
        } else {
          seek(Duration.zero);
          pause();
        }
        break;
    }
  }

  int _getRandomIndex() {
    if (_playlist.length <= 1) return 0;
    final random = Random();
    int next;
    do {
      next = random.nextInt(_playlist.length);
    } while (next == _currentIndex && _playlist.length > 1);
    return next;
  }

  MediaItem _songToMediaItem(Song song) {
    Uri? artUri;
    if (song.albumArtUri != null && song.albumArtUri!.trim().isNotEmpty) {
      final raw = song.albumArtUri!.trim();
      if (raw.startsWith('http://') ||
          raw.startsWith('https://') ||
          raw.startsWith('file://') ||
          raw.startsWith('content://')) {
        artUri = Uri.tryParse(raw);
      } else {
        artUri = Uri.file(raw);
      }
    }

    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.durationMs > 0 ? Duration(milliseconds: song.durationMs) : null,
      artUri: artUri,
    );
  }

  Future<void> disposeHandler() async {
    await _ready;
    _statsTracker.dispose();
    _sessionCoordinator?.dispose();
    await _player.dispose();
    await _currentSongSubject.close();
    await _playbackModeSubject.close();
    await _playlistSubject.close();
  }
}
