import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/song.dart';
import 'storage_service.dart';

/// Service responsible for tracking music playback duration (both local and
/// QQ Music online streams), persisting statistics to StorageService, and
/// optionally reporting playback segments to QQ Music cloud.
class ListeningStatsTracker {
  final StorageService _storageService;

  /// 一首曲目开始播放时触发一次（与本地播放计数同源）。
  /// 用于向 QQ 音乐云端上报「最近播放」——官方客户端也是每次播放开始
  /// 上报一次，而不是按收听时长分段上报。
  final void Function(Song song)? onSongPlayStarted;

  Timer? _ticker;
  Song? _activeSong;
  DateTime? _lastTickTime;
  int _bufferedSeconds = 0;
  bool _isTracking = false;

  final BehaviorSubject<int> _liveTickSubject = BehaviorSubject<int>.seeded(0);

  /// Stream that emits whenever listening seconds are recorded (for live UI update)
  Stream<int> get liveTickStream => _liveTickSubject.stream;

  ListeningStatsTracker(this._storageService, {this.onSongPlayStarted});

  /// Called when playback starts or resumes
  void onPlay(Song song) {
    if (_activeSong?.id != song.id) {
      // Switching song: flush all remaining buffered seconds for previous song
      _flushBufferedSeconds(minSeconds: 1);
      _bufferedSeconds = 0;
      _activeSong = song;
      // Record song play count on startup
      _storageService.recordSongPlayCount(
        song: song,
        timestamp: DateTime.now(),
      );
      onSongPlayStarted?.call(song);
    } else {
      _activeSong = song;
    }

    _lastTickTime = DateTime.now();
    _isTracking = true;

    _startTicker();
  }

  /// Called when playback is paused
  void onPause() {
    _accumulateCurrentElapsed();
    _isTracking = false;
    _stopTicker();
    _flushBufferedSeconds(minSeconds: 1);
  }

  /// Called when playback stops
  void onStop() {
    _accumulateCurrentElapsed();
    _isTracking = false;
    _stopTicker();
    _flushBufferedSeconds(minSeconds: 1);
    _bufferedSeconds = 0;
    _activeSong = null;
  }

  /// Called when the current song completes or skips
  void onSongChanged(Song? newSong) {
    _accumulateCurrentElapsed();
    _flushBufferedSeconds(minSeconds: 1);
    _bufferedSeconds = 0;
    _activeSong = newSong;
    if (newSong != null && _isTracking) {
      _storageService.recordSongPlayCount(
        song: newSong,
        timestamp: DateTime.now(),
      );
      onSongPlayStarted?.call(newSong);
      _lastTickTime = DateTime.now();
    }
  }

  /// Simulate elapsed seconds (used in unit tests to verify sub-minute flushing).
  void recordSimulatedSeconds(int seconds) {
    if (seconds <= 0 || _activeSong == null) return;
    _bufferedSeconds += seconds;
    if (_bufferedSeconds >= 15) {
      _flushBufferedSeconds(minSeconds: 15);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isTracking || _activeSong == null) return;
      _onTick();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    final now = DateTime.now();
    if (_lastTickTime == null || _activeSong == null) {
      _lastTickTime = now;
      return;
    }

    final elapsedMs = now.difference(_lastTickTime!).inMilliseconds;
    // Protect against abnormal sleeps/skips
    if (elapsedMs >= 900 && elapsedMs <= 3000) {
      final elapsedSec = (elapsedMs / 1000).round();
      if (elapsedSec > 0) {
        _bufferedSeconds += elapsedSec;
      }
    }

    _lastTickTime = now;

    // Periodically flush every 15 seconds for responsive live updates
    if (_bufferedSeconds >= 15) {
      _flushBufferedSeconds(minSeconds: 15);
    }
  }

  void _accumulateCurrentElapsed() {
    if (!_isTracking || _lastTickTime == null || _activeSong == null) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastTickTime!).inMilliseconds;
    if (elapsedMs >= 500 && elapsedMs <= 5000) {
      final elapsedSec = (elapsedMs / 1000).round();
      if (elapsedSec > 0) {
        _bufferedSeconds += elapsedSec;
      }
    }
    _lastTickTime = now;
  }

  /// Write accumulated seconds into StorageService.
  void _flushBufferedSeconds({required int minSeconds}) {
    if (_bufferedSeconds < minSeconds || _activeSong == null) {
      return;
    }

    final secondsToRecord = _bufferedSeconds;
    _bufferedSeconds = 0;

    final songToSave = _activeSong!;
    final timestamp = DateTime.now();

    _storageService.recordListeningDuration(
      song: songToSave,
      seconds: secondsToRecord,
      timestamp: timestamp,
    );

    _liveTickSubject.add(_liveTickSubject.value + secondsToRecord);
  }

  void dispose() {
    _accumulateCurrentElapsed();
    _flushBufferedSeconds(minSeconds: 1);
    _stopTicker();
    _liveTickSubject.close();
  }
}
