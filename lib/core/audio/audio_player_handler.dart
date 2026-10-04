import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../models/song.dart';
import '../../models/audio_effects.dart';
import '../../models/playback_mode.dart';
import '../../models/playback_progress.dart';
import '../../services/listening_stats_tracker.dart';
import '../../services/storage_service.dart';
import 'audio_session_coordinator.dart';
import 'custom_notification_service.dart';

class SoundCraftAudioHandler extends BaseAudioHandler with SeekHandler {
  // The Android equalizer must be created before the player and passed into
  // its audio pipeline; on other platforms it stays null and playback runs
  // untouched.
  static final AndroidEqualizer? _equalizer = !kIsWeb && Platform.isAndroid
      ? AndroidEqualizer()
      : null;

  static final AudioPipeline? _audioPipeline = () {
    final eq = _equalizer;
    return eq == null ? null : AudioPipeline(androidAudioEffects: [eq]);
  }();

  late final AudioPlayer _player = AudioPlayer(audioPipeline: _audioPipeline);
  final StorageService _storageService;
  late final ListeningStatsTracker _statsTracker;
  AudioSessionCoordinator? _sessionCoordinator;

  List<Song> _playlist = [];
  int _currentIndex = -1;
  PlaybackMode _playbackMode = PlaybackMode.sequence;
  final List<int> _shuffleHistory = [];
  double _volume = 1.0;
  // Loaded synchronously in the constructor, before any listener can fire
  // _syncCustomNotification (Hive reads are synchronous).
  bool _customNotificationEnabled = true;
  bool _fadeEnabled = false;

  // True once an audio source is actually loaded into the player. A restored
  // session rebuilds the queue metadata without touching the file system, so
  // the first play() after a restart must load the file (with the resume
  // position) instead of just unpausing.
  bool _audioLoaded = false;
  Duration? _pendingResumePosition;

  // Session persistence debounce: queue mutations coalesce into one Hive
  // write instead of serializing the whole queue per tap.
  Timer? _persistSessionDebounce;

  // Sleep timer state.
  Timer? _sleepTicker;
  DateTime _sleepDeadline = DateTime.now();
  final BehaviorSubject<Duration?> _sleepRemainingSubject =
      BehaviorSubject<Duration?>.seeded(null);

  // Volume fade animation generation; bumping it cancels the running ramp.
  int _volumeAnimationGeneration = 0;
  // Pause-intent generation: play() bumps it so a fade-out pause that is
  // still ramping aborts instead of pausing a song the user just started.
  int _pauseGeneration = 0;
  // Consecutive playAtIndex failures (file missing / corrupt). Once every
  // song in the queue has failed, auto-skip stops instead of looping forever
  // under repeatAll/shuffle.
  int _consecutiveFailures = 0;
  // Bumped on every playAtIndex; async load steps bail out when superseded
  // by a newer song switch.
  int _loadGeneration = 0;

  final BehaviorSubject<Song?> _currentSongSubject =
      BehaviorSubject<Song?>.seeded(null);
  final BehaviorSubject<PlaybackMode> _playbackModeSubject =
      BehaviorSubject<PlaybackMode>.seeded(PlaybackMode.sequence);
  final BehaviorSubject<List<Song>> _playlistSubject =
      BehaviorSubject<List<Song>>.seeded([]);
  final StreamController<String> _playbackErrorController =
      StreamController<String>.broadcast();

  /// Emits a user-facing message whenever a song fails to load (file missing,
  /// unsupported format, ...). The UI listens and shows a toast.
  Stream<String> get playbackErrorStream => _playbackErrorController.stream;

  ListeningStatsTracker get statsTracker => _statsTracker;

  /// Emits the remaining sleep-timer time while counting down, `null` when
  /// no timer is active.
  Stream<Duration?> get sleepTimerStream => _sleepRemainingSubject.stream;
  Duration? get sleepTimerRemaining => _sleepRemainingSubject.valueOrNull;

  /// The Android equalizer instance, `null` on non-Android platforms.
  AndroidEqualizer? get equalizer => _equalizer;

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

  /// Cached combined stream: building it is cheap but a fresh stream per
  /// getter call would mean every future subscriber spawns its own
  /// combineLatest + positionStream subscription pair.
  late final Stream<PlaybackProgress> progressStream =
      Rx.combineLatest3<Duration, Duration, Duration?, PlaybackProgress>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (pos, buf, dur) => PlaybackProgress(
          position: pos,
          bufferedPosition: buf,
          duration:
              dur ??
              (currentSong != null ? currentSong!.duration : Duration.zero),
        ),
      );

  SoundCraftAudioHandler(this._storageService) {
    _statsTracker = ListeningStatsTracker(_storageService);
    _customNotificationEnabled =
        _storageService.getCustomNotificationEnabled();
    _fadeEnabled = _storageService.getFadeEnabled();

    // Attach the player listeners synchronously, before any async gap. The
    // audio_service notification is only shown when `playing=true` propagates
    // through playbackState; if playback started before these listeners were
    // attached (or async init failed midway), the system media notification
    // would silently never appear while audio keeps playing in-app.
    _player.playbackEventStream.listen(_broadcastPlaybackState);

    _player.playerStateStream.listen((state) {
      _broadcastPlaybackState(_player.playbackEvent);
      if (state.playing &&
          currentSong != null &&
          (state.processingState == ProcessingState.ready ||
              state.processingState == ProcessingState.buffering)) {
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
    _player.positionStream.throttleTime(const Duration(seconds: 3)).listen((
      pos,
    ) {
      if (currentSong != null) {
        _storageService.saveLastPositionMs(pos.inMilliseconds);
      }
    });

    // Update custom notification progress bar every second during playback
    _player.positionStream.throttleTime(const Duration(seconds: 1)).listen((
      pos,
    ) {
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

      _restoreSession();
      await _applyPersistedEqualizer();

      // Audio Session Coordinator (Focus / Phone Interruption / Becoming Noisy)
      final sessionCoordinator = AudioSessionCoordinator(
        onPause: pause,
        onResume: play,
        onSetVolume: (vol) => _player.setVolume(vol),
        getCurrentVolume: () => _volume,
      );
      _sessionCoordinator = sessionCoordinator;
      await sessionCoordinator.init().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // Some OEM skins (e.g. HyperOS) can stall audio-session configuration;
          // never let it block handler readiness or playback start.
          debugPrint('[AquaMoon] audio session init timed out');
        },
      );
    } catch (e, st) {
      // An audio-session hiccup on an OEM skin (HyperOS etc.) must never
      // break playback or the media-notification bridge. Log and continue.
      debugPrint('[AquaMoon] init warning: $e\n$st');
    }
  }

  /// Rebuilds the last session's queue (metadata only — no file I/O) so the
  /// mini player shows the previous song before the user presses play. The
  /// audio source loads lazily in [play] at the persisted position.
  void _restoreSession() {
    try {
      final session = _storageService.getPlaybackSession();
      if (session == null) return;
      final songs = [
        for (final map in session.songMaps) Song.fromMap(map),
      ].where((s) => s.id.isNotEmpty && s.filePath.isNotEmpty).toList();
      if (songs.isEmpty) return;

      _playlist = songs;
      _currentIndex = session.index.clamp(0, songs.length - 1);
      final song = songs[_currentIndex];

      _playlistSubject.add(List.unmodifiable(_playlist));
      _currentSongSubject.add(song);
      queue.add(_playlist.map(_songToMediaItem).toList());
      mediaItem.add(_songToMediaItem(song));

      final savedMs = _storageService.getLastPositionMs();
      final durationMs = song.durationMs;
      _pendingResumePosition = durationMs > 0 && savedMs >= durationMs - 3000
          ? null // Song had effectively finished — restart from the top.
          : (savedMs > 0 ? Duration(milliseconds: savedMs) : null);
    } catch (e) {
      debugPrint('[AquaMoon] session restore failed: $e');
    }
  }

  /// Applies the persisted equalizer on/off state and band gains. Must run on
  /// Android only; `parameters` never completes elsewhere.
  Future<void> _applyPersistedEqualizer() async {
    final eq = _equalizer;
    if (eq == null) return;
    try {
      await eq.setEnabled(_storageService.getEqualizerEnabled());
      final gains = _storageService.getEqualizerGains();
      if (gains.isEmpty) return;
      final parameters = await eq.parameters;
      for (var i = 0; i < parameters.bands.length && i < gains.length; i++) {
        await parameters.bands[i].setGain(gains[i]);
      }
    } catch (e) {
      debugPrint('[AquaMoon] equalizer init failed: $e');
    }
  }

  bool _lastBroadcastPlaying = false;
  // playbackEventStream fires on every position tick during playback; the
  // custom-notification platform channel must only be hit when play/pause or
  // the processing state actually changes. Periodic progress updates are
  // handled by the 1s-throttled position listener below.
  bool _lastSyncedNotificationPlaying = false;
  ProcessingState? _lastSyncedNotificationProcessing;

  void _broadcastPlaybackState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _player.processingState;

    if (playing != _lastBroadcastPlaying) {
      // Diagnostic for the media-notification pipeline: audio_service only
      // shows the system notification when it receives playing=true.
      // Uses debugPrint so it shows in logcat under the "flutter" tag.
      debugPrint(
        '[AquaMoon] pushing playing=$playing (processingState=$processingState) -> '
        '${playing ? 'system notification should appear now' : 'paused'}',
      );
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
        processingState:
            const {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[processingState] ??
            AudioProcessingState.idle,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
      ),
    );

    if (playing != _lastSyncedNotificationPlaying ||
        processingState != _lastSyncedNotificationProcessing) {
      _lastSyncedNotificationPlaying = playing;
      _lastSyncedNotificationProcessing = processingState;
      _syncCustomNotification(playing: playing);
    }
  }

  void _syncCustomNotification({
    bool? playing,
    Song? overrideSong,
    Duration? position,
    Duration? duration,
  }) {
    if (!_customNotificationEnabled) return;
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

  /// 同步的“正在播放”状态。快速连点播放/暂停时 playbackState 的流式更新存在
  /// 滞后（淡出暂停先渐变 ~240ms 才真正 pause），用 just_audio 的同步值判断
  /// 才能保证按钮交替生效。
  bool get isPlaying => _player.playing;

  @override
  Future<void> play() async {
    await _ready;
    if (_playlist.isEmpty) return;
    if (_currentIndex < 0) {
      await playAtIndex(0);
      return;
    }
    // A restored session has queue metadata but no loaded audio source yet —
    // load the file now and resume at the persisted position.
    if (!_audioLoaded) {
      final resumeAt = _pendingResumePosition;
      _pendingResumePosition = null;
      await playAtIndex(_currentIndex, autoPlay: true, initialPosition: resumeAt);
      return;
    }
    // Cancel a fade-out pause still in flight, then start (and fade in from
    // the silenced volume pause() left behind).
    _pauseGeneration++;
    await _player.play();
    _restoreVolumeForPlay();
  }

  /// 播放开始后的音量处理：开启淡入淡出时从当前音量（暂停后为 0）渐变回
  /// [_volume]；未开启时直接恢复，防止暂停残留的 0 音量导致“静音播放”。
  void _restoreVolumeForPlay() {
    if (_fadeEnabled) {
      unawaited(_animateVolume(_volume, const Duration(milliseconds: 320)));
    } else {
      unawaited(_player.setVolume(_volume));
    }
  }

  @override
  Future<void> pause() async {
    final pauseToken = ++_pauseGeneration;
    if (_fadeEnabled && _player.playing) {
      await _animateVolume(0.0, const Duration(milliseconds: 240));
      if (pauseToken != _pauseGeneration) {
        // 淡出期间用户按了播放（play() 会顶掉 pause 代号）——
        // 不能真的暂停，否则会吞掉播放指令。
        return;
      }
    }
    await _player.pause();
    // 音量保持在 0（静音态），play() 恢复时从 0 渐变回 [_volume]；
    // setFadeEnabled(false) 与 setVolume 都会无条件恢复实际音量。
    if (currentSong != null) {
      _storageService.saveLastPositionMs(_player.position.inMilliseconds);
    }
  }

  /// Ramps the player volume from the current value to [target]. Bumping
  /// [_volumeAnimationGeneration] (setVolume / another ramp) cancels any
  /// in-flight animation.
  Future<void> _animateVolume(double target, Duration duration) async {
    final generation = ++_volumeAnimationGeneration;
    if (duration <= Duration.zero) {
      await _player.setVolume(target);
      return;
    }
    final from = _player.volume;
    if ((from - target).abs() < 0.01) {
      await _player.setVolume(target);
      return;
    }
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(duration ~/ steps);
      if (generation != _volumeAnimationGeneration) return;
      await _player.setVolume(from + (target - from) * i / steps);
    }
  }

  // --- Sleep Timer ---

  /// Starts (or restarts) the sleep timer. When it elapses, playback pauses
  /// — with a fade-out when the fade setting is on.
  void startSleepTimer(Duration duration) {
    _sleepTicker?.cancel();
    _sleepDeadline = DateTime.now().add(duration);
    _sleepRemainingSubject.add(duration);
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _sleepDeadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        timer.cancel();
        _sleepTicker = null;
        _sleepRemainingSubject.add(null);
        unawaited(_onSleepTimerExpired());
      } else {
        _sleepRemainingSubject.add(remaining);
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepRemainingSubject.add(null);
  }

  Future<void> _onSleepTimerExpired() async {
    if (_player.playing) {
      await pause();
    }
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
    // A manual volume change cancels any in-flight fade ramp.
    _volumeAnimationGeneration++;
    await _player.setVolume(_volume);
    await _storageService.saveVolume(_volume);
  }

  /// 淡入淡出开关：暂停/恢复与睡眠定时器到点时对音量做短促渐变，
  /// 而非硬切。仅影响应用内音量曲线，不改变系统音量。
  Future<void> setFadeEnabled(bool enabled) async {
    if (_fadeEnabled == enabled) return;
    _fadeEnabled = enabled;
    _volumeAnimationGeneration++;
    await _storageService.saveFadeEnabled(enabled);
    if (!enabled) {
      await _player.setVolume(_volume);
    }
  }

  bool get fadeEnabled => _fadeEnabled;

  /// 把 [song] 插到当前歌曲之后（"下一首播放"）。队列空闲时等价于直接播放。
  Future<void> playNext(Song song) async {
    if (_playlist.isEmpty || _currentIndex < 0) {
      await playSong(song);
      return;
    }
    // Replace a stale queued copy first so it doesn't appear twice. Removals
    // before the current song shift its index — adjust as we go.
    for (var i = _playlist.length - 1; i >= 0; i--) {
      if (_playlist[i].id == song.id && i != _currentIndex) {
        _playlist.removeAt(i);
        _onQueueItemRemoved(i);
      }
    }
    final insertAt = _currentIndex + 1;
    _playlist.insert(insertAt.clamp(0, _playlist.length), song);
    _playlistSubject.add(List.unmodifiable(_playlist));
    queue.add(_playlist.map(_songToMediaItem).toList());
    _persistSessionSoon();
  }

  /// Applies equalizer enable/disable at runtime (Android only).
  Future<void> setEqualizerEnabled(bool enabled) async {
    final eq = _equalizer;
    if (eq == null) return;
    await eq.setEnabled(enabled);
    await _storageService.saveEqualizerEnabled(enabled);
  }

  /// 读取均衡器参数快照（频段、增益范围、当前增益），非 Android 返回 null。
  Future<EqualizerSnapshot?> loadEqualizerSnapshot() async {
    final eq = _equalizer;
    if (eq == null) return null;
    try {
      final parameters = await eq.parameters;
      return EqualizerSnapshot(
        minDb: parameters.minDecibels,
        maxDb: parameters.maxDecibels,
        bands: [
          for (final band in parameters.bands)
            EqualizerBandInfo(
              index: band.index,
              centerHz: band.centerFrequency,
              minDb: parameters.minDecibels,
              maxDb: parameters.maxDecibels,
              gainDb: band.gain,
            ),
        ],
      );
    } catch (e) {
      debugPrint('[AquaMoon] equalizer snapshot failed: $e');
      return null;
    }
  }

  /// 调整单个频段增益（dB），并更新持久化的整组增益。
  Future<void> setEqualizerBandGain(int index, double gain) async {
    final eq = _equalizer;
    if (eq == null) return;
    try {
      final parameters = await eq.parameters;
      if (index < 0 || index >= parameters.bands.length) return;
      await parameters.bands[index].setGain(gain);

      final gains = _storageService.getEqualizerGains();
      final padded = List<double>.generate(
        parameters.bands.length,
        (i) => i < gains.length ? gains[i] : 0.0,
      );
      padded[index] = gain;
      await _storageService.saveEqualizerGains(padded);
    } catch (e) {
      debugPrint('[AquaMoon] equalizer setGain failed: $e');
    }
  }

  /// Persists and applies band gains (dB, band-index aligned, Android only).
  Future<void> setEqualizerGains(List<double> gains) async {
    final eq = _equalizer;
    if (eq == null) return;
    await _storageService.saveEqualizerGains(gains);
    try {
      final parameters = await eq.parameters;
      for (var i = 0; i < parameters.bands.length && i < gains.length; i++) {
        await parameters.bands[i].setGain(gains[i]);
      }
    } catch (e) {
      debugPrint('[AquaMoon] equalizer setGain failed: $e');
    }
  }

  bool get customNotificationEnabled => _customNotificationEnabled;

  /// 水墨专属通知栏（自定义 RemoteViews 通知）开关。系统原生媒体通知不受影响
  /// ——它是前台服务的载体，关闭会破坏后台播放。立即生效：关闭时撤下现有
  /// 卡片；开启时若正在播放则按当前状态立刻重建。
  Future<void> setCustomNotificationEnabled(bool enabled) async {
    if (_customNotificationEnabled == enabled) return;
    _customNotificationEnabled = enabled;
    await _storageService.saveCustomNotificationEnabled(enabled);
    if (enabled) {
      _syncCustomNotification();
    } else {
      await CustomNotificationService.cancel();
    }
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

  Future<void> loadPlaylist(
    List<Song> songs, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    if (songs.isEmpty) return;
    _playlist = List.from(songs);
    _playlistSubject.add(List.unmodifiable(_playlist));
    _shuffleHistory.clear();
    _pendingResumePosition = null;

    // Map to audio_service queue
    final mediaItems = _playlist.map(_songToMediaItem).toList();
    queue.add(mediaItems);

    await playAtIndex(initialIndex, autoPlay: autoPlay);
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((s) => s.id == song.id);
      if (index < 0) {
        // 歌曲不在给定队列里：退回“单独加入并播放”，而不是错放第 0 首。
        await playSong(song);
        return;
      }
      await loadPlaylist(
        contextQueue,
        initialIndex: index,
        autoPlay: true,
      );
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

  Future<void> playAtIndex(
    int index, {
    bool autoPlay = true,
    Duration? initialPosition,
  }) async {
    await _ready;
    if (index < 0 || index >= _playlist.length) return;

    // 快速切歌时，上一次加载的后续 await 完成后不得再覆盖新歌的状态。
    final generation = ++_loadGeneration;
    _currentIndex = index;
    final song = _playlist[index];
    _shuffleHistory.add(index);

    // Persist play history & count BEFORE announcing the current song, so
    // listeners that read the songs box on song change see the incremented
    // play count.
    await _storageService.addToHistory(song.id);
    await _storageService.saveLastPlayedSongId(song.id);
    if (generation != _loadGeneration) return;

    _currentSongSubject.add(song);

    // Update audio_service MediaItem (Notification, lockscreen info)
    final mediaItem = _songToMediaItem(song);
    this.mediaItem.add(mediaItem);

    try {
      if (song.source == SongSource.local) {
        await _player.setFilePath(song.filePath);
      } else {
        await _player.setUrl(song.filePath);
      }
      if (generation != _loadGeneration) return;
      _audioLoaded = true;
      _consecutiveFailures = 0;
      _persistSessionSoon();

      if (initialPosition != null && initialPosition > Duration.zero) {
        await _player.seek(initialPosition);
        _storageService.saveLastPositionMs(initialPosition.inMilliseconds);
      }

      if (autoPlay) {
        _pauseGeneration++;
        await _player.play();
        if (generation != _loadGeneration) return;
        _restoreVolumeForPlay();
      }
    } catch (e) {
      if (generation != _loadGeneration) return;
      // Audio playback failed (e.g. file missing or unreadable format)
      debugPrint('[AquaMoon] playback failed for "${song.title}": $e');
      _playbackErrorController.add('无法播放「${song.title}」，文件可能已移动或损坏');
      _consecutiveFailures++;
      if (_consecutiveFailures >= _playlist.length) {
        // 整个队列都放不出来：停下并提示，避免 repeatAll/shuffle 无限重试。
        _consecutiveFailures = 0;
        await pause();
        return;
      }
      // Automatically attempt next song if available
      if (_playlist.length > 1) {
        unawaited(skipToNext());
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
    _persistSessionSoon();
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
    _onQueueItemRemoved(index);
    _playlistSubject.add(List.unmodifiable(_playlist));
    queue.add(_playlist.map(_songToMediaItem).toList());
    _persistSessionSoon();

    if (isCurrent) {
      if (_playlist.isNotEmpty) {
        _currentIndex = _currentIndex.clamp(0, _playlist.length - 1);
        playAtIndex(_currentIndex);
      } else {
        _currentIndex = -1;
        _currentSongSubject.add(null);
        _player.stop();
        CustomNotificationService.cancel();
        _storageService.savePlaybackSession(const [], -1);
      }
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;
    final clampedNewIndex = newIndex.clamp(0, _playlist.length - 1);
    if (oldIndex == clampedNewIndex) return;

    final item = _playlist.removeAt(oldIndex);
    _playlist.insert(clampedNewIndex, item);
    _onQueueItemReordered(oldIndex, clampedNewIndex);

    _playlistSubject.add(List.unmodifiable(_playlist));
    queue.add(_playlist.map(_songToMediaItem).toList());
    _persistSessionSoon();
  }

  /// 队列删除 [removedIndex] 处条目后，同步 [_currentIndex] 与
  /// [_shuffleHistory]：被删的随机播放历史失效，其后的索引全部前移。
  /// 否则随机模式下“上一首”会按旧索引弹出到错误的歌。
  void _onQueueItemRemoved(int removedIndex) {
    if (_currentIndex > removedIndex) _currentIndex--;
    _shuffleHistory.removeWhere((i) => i == removedIndex);
    for (var i = 0; i < _shuffleHistory.length; i++) {
      if (_shuffleHistory[i] > removedIndex) _shuffleHistory[i]--;
    }
  }

  /// 队列把条目从 [oldIndex] 移到 [newIndex]（先删后插的最终位置）后，
  /// 同步 [_currentIndex] 与 [_shuffleHistory] 中所有观察到的索引。
  void _onQueueItemReordered(int oldIndex, int newIndex) {
    int adjust(int index) {
      if (index == oldIndex) return newIndex;
      if (oldIndex < index && newIndex >= index) return index - 1;
      if (oldIndex > index && newIndex <= index) return index + 1;
      return index;
    }

    _currentIndex = adjust(_currentIndex);
    for (var i = 0; i < _shuffleHistory.length; i++) {
      _shuffleHistory[i] = adjust(_shuffleHistory[i]);
    }
  }

  void clearQueue() {
    _persistSessionDebounce?.cancel();
    _persistSessionDebounce = null;
    _playlist.clear();
    _currentIndex = -1;
    _playlistSubject.add(const []);
    _currentSongSubject.add(null);
    _audioLoaded = false;
    _pendingResumePosition = null;
    queue.add([]);
    _player.stop();
    CustomNotificationService.cancel();
    _storageService.savePlaybackSession(const [], -1);
  }

  // --- Session Persistence ---

  /// Coalesces queue mutations into a single Hive write ~1s after the last
  /// change, so rapid taps (reorder drag, skip) don't serialize the queue
  /// repeatedly.
  void _persistSessionSoon() {
    if (_playlist.isEmpty || _currentIndex < 0) return;
    _persistSessionDebounce?.cancel();
    _persistSessionDebounce = Timer(const Duration(seconds: 1), () {
      if (_playlist.isNotEmpty && _currentIndex >= 0) {
        _storageService.savePlaybackSession(_playlist, _currentIndex);
      }
    });
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
      duration: song.durationMs > 0
          ? Duration(milliseconds: song.durationMs)
          : null,
      artUri: artUri,
    );
  }

  Future<void> disposeHandler() async {
    await _ready;
    _persistSessionDebounce?.cancel();
    _sleepTicker?.cancel();
    _sleepRemainingSubject.close();
    _statsTracker.dispose();
    _sessionCoordinator?.dispose();
    await _player.dispose();
    await _currentSongSubject.close();
    await _playbackModeSubject.close();
    await _playlistSubject.close();
    await _playbackErrorController.close();
  }
}
