import 'package:hive_flutter/hive_flutter.dart';
import '../core/utils/formatters.dart';
import '../models/listening_stats.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../models/playback_mode.dart';

class StorageService {
  static const String _songsBoxName = 'soundcraft_songs';
  static const String _playlistsBoxName = 'soundcraft_playlists';
  static const String _historyBoxName = 'soundcraft_history';
  static const String _settingsBoxName = 'soundcraft_settings';
  static const String _statsBoxName = 'soundcraft_stats';

  late Box _songsBox;
  late Box _playlistsBox;
  late Box _historyBox;
  late Box _settingsBox;
  late Box _statsBox;

  Future<void> init([String? customPath]) async {
    if (customPath != null) {
      Hive.init(customPath);
    } else {
      await Hive.initFlutter();
    }
    _songsBox = await Hive.openBox(_songsBoxName);
    _playlistsBox = await Hive.openBox(_playlistsBoxName);
    _historyBox = await Hive.openBox(_historyBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);
    _statsBox = await Hive.openBox(_statsBoxName);
  }

  // --- Song Operations ---

  List<Song> getAllSongs() {
    return _songsBox.values
        .whereType<Map>()
        .map((map) => Song.fromMap(map))
        .toList();
  }

  Song? getSong(String songId) {
    final songData = _songsBox.get(songId);
    if (songData != null && songData is Map) {
      return Song.fromMap(songData);
    }
    return null;
  }

  Future<void> saveSong(Song song) async {
    await _songsBox.put(song.id, song.toMap());
  }

  Future<void> saveSongs(List<Song> songs) async {
    final Map<String, dynamic> entries = {
      for (final song in songs) song.id: song.toMap(),
    };
    await _songsBox.putAll(entries);
  }

  Future<void> overwriteAllSongs(List<Song> songs) async {
    await _songsBox.clear();
    final Map<String, dynamic> entries = {
      for (final song in songs) song.id: song.toMap(),
    };
    await _songsBox.putAll(entries);
  }

  Future<void> deleteSong(String songId) async {
    await _songsBox.delete(songId);
    // Remove from history as well
    final history = getHistoryIds();
    if (history.contains(songId)) {
      history.remove(songId);
      await _historyBox.put('recent_song_ids', history);
    }
  }

  Future<Song?> toggleFavorite(String songId) async {
    final songData = _songsBox.get(songId);
    if (songData != null && songData is Map) {
      final song = Song.fromMap(songData);
      final updated = song.copyWith(isFavorite: !song.isFavorite);
      await _songsBox.put(songId, updated.toMap());
      return updated;
    }
    return null;
  }

  // --- Playlist Operations ---

  List<Playlist> getAllPlaylists() {
    return _playlistsBox.values
        .whereType<Map>()
        .map((map) => Playlist.fromMap(map))
        .toList();
  }

  Future<void> savePlaylist(Playlist playlist) async {
    await _playlistsBox.put(playlist.id, playlist.toMap());
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _playlistsBox.delete(playlistId);
  }

  // --- History Operations ---

  List<String> getHistoryIds() {
    final list = _historyBox.get('recent_song_ids');
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> addToHistory(String songId) async {
    final list = getHistoryIds();
    list.remove(songId);
    list.insert(0, songId);
    if (list.length > 100) {
      list.removeRange(100, list.length);
    }
    await _historyBox.put('recent_song_ids', list);

    // Increment playCount
    final songData = _songsBox.get(songId);
    if (songData != null && songData is Map) {
      final song = Song.fromMap(songData);
      final updated = song.copyWith(playCount: song.playCount + 1);
      await _songsBox.put(songId, updated.toMap());
    }
  }

  // --- Settings / State Persistence ---

  PlaybackMode getSavedPlaybackMode() {
    final name = _settingsBox.get('playback_mode', defaultValue: PlaybackMode.sequence.name);
    return PlaybackMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PlaybackMode.sequence,
    );
  }

  Future<void> savePlaybackMode(PlaybackMode mode) async {
    await _settingsBox.put('playback_mode', mode.name);
  }

  String? getLastPlayedSongId() {
    return _settingsBox.get('last_played_song_id') as String?;
  }

  Future<void> saveLastPlayedSongId(String songId) async {
    await _settingsBox.put('last_played_song_id', songId);
  }

  int getLastPositionMs() {
    return (_settingsBox.get('last_position_ms', defaultValue: 0) as num).toInt();
  }

  Future<void> saveLastPositionMs(int ms) async {
    await _settingsBox.put('last_position_ms', ms);
  }

  double getSavedVolume() {
    return (_settingsBox.get('volume', defaultValue: 1.0) as num).toDouble();
  }

  Future<void> saveVolume(double volume) async {
    await _settingsBox.put('volume', volume);
  }

  // --- Listening Statistics Operations ---

  DailyListeningRecord getDailyListeningRecord(String dateStr) {
    final raw = _statsBox.get('daily:$dateStr');
    if (raw != null && raw is Map) {
      return DailyListeningRecord.fromMap(raw);
    }
    return DailyListeningRecord(dateStr: dateStr);
  }

  Future<void> saveDailyListeningRecord(DailyListeningRecord record) async {
    await _statsBox.put('daily:${record.dateStr}', record.toMap());
  }

  /// Add listening duration for a song in a single step (with snapshot caching)
  Future<void> recordListeningDuration({
    required Song song,
    required int seconds,
    required DateTime timestamp,
  }) async {
    if (seconds <= 0) return;

    final dateStr = Formatters.formatDateKey(timestamp);
    final current = getDailyListeningRecord(dateStr);

    final updatedSongDurations = Map<String, int>.from(current.songDurationSeconds);
    updatedSongDurations[song.id] = (updatedSongDurations[song.id] ?? 0) + seconds;

    final updatedHourly = Map<int, int>.from(current.hourlyDurationSeconds);
    updatedHourly[timestamp.hour] = (updatedHourly[timestamp.hour] ?? 0) + seconds;

    final updatedMetaCache = Map<String, SongMetaSnapshot>.from(current.songMetaCache);
    if (!updatedMetaCache.containsKey(song.id)) {
      updatedMetaCache[song.id] = SongMetaSnapshot.fromSong(song);
    }

    final updatedRecord = current.copyWith(
      totalDurationSeconds: current.totalDurationSeconds + seconds,
      songDurationSeconds: updatedSongDurations,
      hourlyDurationSeconds: updatedHourly,
      songMetaCache: updatedMetaCache,
    );

    await saveDailyListeningRecord(updatedRecord);
  }

  /// Increment play count for a song on a specific date in stats
  Future<void> recordSongPlayCount({
    required Song song,
    required DateTime timestamp,
  }) async {
    final dateStr = Formatters.formatDateKey(timestamp);
    final current = getDailyListeningRecord(dateStr);

    final updatedPlayCounts = Map<String, int>.from(current.songPlayCounts);
    updatedPlayCounts[song.id] = (updatedPlayCounts[song.id] ?? 0) + 1;

    final updatedMetaCache = Map<String, SongMetaSnapshot>.from(current.songMetaCache);
    if (!updatedMetaCache.containsKey(song.id)) {
      updatedMetaCache[song.id] = SongMetaSnapshot.fromSong(song);
    }

    final updatedRecord = current.copyWith(
      songPlayCounts: updatedPlayCounts,
      songMetaCache: updatedMetaCache,
    );

    await saveDailyListeningRecord(updatedRecord);
  }

  /// Retrieve all records within the [startDate, endDate] range (inclusive of days)
  List<DailyListeningRecord> getDailyRecordsInRange(DateTime startDate, DateTime endDate) {
    final results = <DailyListeningRecord>[];
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);

    var current = startDay;
    while (!current.isAfter(endDay)) {
      final dateKey = Formatters.formatDateKey(current);
      final raw = _statsBox.get('daily:$dateKey');
      if (raw != null && raw is Map) {
        results.add(DailyListeningRecord.fromMap(raw));
      }
      current = current.add(const Duration(days: 1));
    }

    return results;
  }

  /// Retrieve all recorded daily statistics
  List<DailyListeningRecord> getAllDailyRecords() {
    final records = <DailyListeningRecord>[];
    for (final key in _statsBox.keys) {
      if (key is String && key.startsWith('daily:')) {
        final raw = _statsBox.get(key);
        if (raw is Map) {
          records.add(DailyListeningRecord.fromMap(raw));
        }
      }
    }
    records.sort((a, b) => a.dateStr.compareTo(b.dateStr));
    return records;
  }

  /// Get total listening time across all dates in seconds
  int getTotalLifetimeListeningSeconds() {
    int total = 0;
    for (final record in getAllDailyRecords()) {
      total += record.totalDurationSeconds;
    }
    return total;
  }
}
