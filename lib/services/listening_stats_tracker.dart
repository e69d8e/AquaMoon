import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/song.dart';
import 'storage_service.dart';

/// Service responsible for tracking music playback duration at 1-minute intervals
/// and persisting statistics to StorageService.
class ListeningStatsTracker {
  final StorageService _storageService;

  Timer? _ticker;
  Song? _activeSong;
  DateTime? _lastTickTime;
  int _bufferedSeconds = 0;
  bool _isTracking = false;

  final BehaviorSubject<int> _liveTickSubject = BehaviorSubject<int>.seeded(0);

  /// Stream that emits whenever listening minutes are recorded (for live UI update)
  Stream<int> get liveTickStream => _liveTickSubject.stream;

  ListeningStatsTracker(this._storageService);

  /// Called when playback starts or resumes
  void onPlay(Song song) {
    if (_activeSong?.id != song.id) {
      // Switching song: flush previous full minutes
      _flushMinutes();
      _bufferedSeconds = 0;
      _activeSong = song;
      // Record song play count on startup
      _storageService.recordSongPlayCount(
        song: song,
        timestamp: DateTime.now(),
      );
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
    _flushMinutes();
  }

  /// Called when playback stops
  void onStop() {
    _accumulateCurrentElapsed();
    _isTracking = false;
    _stopTicker();
    _flushMinutes();
    _bufferedSeconds = 0;
    _activeSong = null;
  }

  /// Called when the current song completes or skips
  void onSongChanged(Song? newSong) {
    _accumulateCurrentElapsed();
    _flushMinutes();
    _bufferedSeconds = 0;
    _activeSong = newSong;
    if (newSong != null && _isTracking) {
      _storageService.recordSongPlayCount(
        song: newSong,
        timestamp: DateTime.now(),
      );
      _lastTickTime = DateTime.now();
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

    // Record once every 1 minute (60 seconds)
    if (_bufferedSeconds >= 60) {
      _flushMinutes();
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

  /// Write accumulated full minutes into StorageService (1-minute intervals)
  void _flushMinutes() {
    if (_bufferedSeconds < 60 || _activeSong == null) {
      return;
    }

    final minutesToRecord = _bufferedSeconds ~/ 60;
    final secondsToRecord = minutesToRecord * 60;
    _bufferedSeconds %= 60;

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
    _flushMinutes();
    _stopTicker();
    _liveTickSubject.close();
  }
}
