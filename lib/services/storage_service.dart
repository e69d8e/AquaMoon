import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/utils/formatters.dart';
import '../models/listening_stats.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../models/playback_mode.dart';
import '../models/lyrics_display_settings.dart';

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
    final boxes = await Future.wait([
      Hive.openBox(_songsBoxName),
      Hive.openBox(_playlistsBoxName),
      Hive.openBox(_historyBoxName),
      Hive.openBox(_settingsBoxName),
      Hive.openBox(_statsBoxName),
    ]);
    _songsBox = boxes[0];
    _playlistsBox = boxes[1];
    _historyBox = boxes[2];
    _settingsBox = boxes[3];
    _statsBox = boxes[4];
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

  Future<void> deleteSong(String songId) async {
    await _songsBox.delete(songId);
    // Remove from history as well
    final history = getHistoryIds();
    if (history.contains(songId)) {
      history.remove(songId);
      await _historyBox.put('recent_song_ids', history);
    }
    await scrubSongIdsFromAllPlaylists({songId});
  }

  /// Bulk-removes songs by id. History entries pointing at removed songs are
  /// purged as well (dedup deletion historically left them; harmless there,
  /// wrong for real removals). Dangling ids are also scrubbed from every
  /// playlist, otherwise the playlist detail page (which renders only songs
  /// that still exist) would reorder against mismatched indices.
  Future<void> deleteSongs(List<String> songIds) async {
    if (songIds.isEmpty) return;
    await _songsBox.deleteAll(songIds);
    final idSet = songIds.toSet();
    final history = getHistoryIds();
    if (history.any(idSet.contains)) {
      history.removeWhere(idSet.contains);
      await _historyBox.put('recent_song_ids', history);
    }
    await scrubSongIdsFromAllPlaylists(idSet);
  }

  /// Removes every id in [songIds] from all playlists' songIds lists.
  Future<void> scrubSongIdsFromAllPlaylists(Set<String> songIds) async {
    if (songIds.isEmpty) return;
    for (final key in _playlistsBox.keys) {
      final raw = _playlistsBox.get(key);
      if (raw is! Map) continue;
      final playlist = Playlist.fromMap(raw);
      final newIds = playlist.songIds.where((id) => !songIds.contains(id));
      if (newIds.length == playlist.songIds.length) continue;
      final updated = playlist.copyWith(songIds: newIds.toList());
      await _playlistsBox.put(key, updated.toMap());
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

  // --- Settings Operations ---

  ThemeMode getSavedThemeMode() {
    switch (_settingsBox.get('theme_mode')) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final name = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      _ => 'light',
    };
    await _settingsBox.put('theme_mode', name);
  }

  /// 配色方案 id 原始值;解析与未知 id 的回退由 themePaletteProvider 处理。
  String? getSavedThemeId() {
    final v = _settingsBox.get('theme_id');
    return v is String ? v : null;
  }

  Future<void> saveThemeId(String id) async {
    await _settingsBox.put('theme_id', id);
  }

  LyricsDisplaySettings getSavedLyricsDisplaySettings() {
    return LyricsDisplaySettings.fromMap(
      _settingsBox.get('lyrics_display_settings'),
    );
  }

  Future<void> saveLyricsDisplaySettings(LyricsDisplaySettings settings) {
    return _settingsBox.put(
      'lyrics_display_settings',
      settings.toMap(),
    );
  }

  // --- History Operations ---

  List<String> getHistoryIds() {
    final list = _historyBox.get('recent_song_ids');
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> clearHistory() async {
    await _historyBox.put('recent_song_ids', <String>[]);
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
    final name = _settingsBox.get(
      'playback_mode',
      defaultValue: PlaybackMode.sequence.name,
    );
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
    final v = _settingsBox.get('last_position_ms', defaultValue: 0);
    return v is num ? v.toInt() : 0;
  }

  Future<void> saveLastPositionMs(int ms) async {
    await _settingsBox.put('last_position_ms', ms);
  }

  // --- Playback Session (queue persistence across restarts) ---

  /// Returns the persisted queue as raw song maps plus the active index, or
  /// `null` when no session was saved (never played / queue cleared). The
  /// index is clamped to the (type-filtered) queue length so a stale index
  /// can't crash session restore.
  ({List<Map> songMaps, int index})? getPlaybackSession() {
    final maps = _settingsBox.get('playback_queue');
    if (maps is! List || maps.isEmpty) return null;
    final songMaps = maps.whereType<Map>().toList();
    if (songMaps.isEmpty) return null;
    final rawIndex = _settingsBox.get('playback_queue_index', defaultValue: 0);
    final index = rawIndex is num ? rawIndex.toInt() : 0;
    return (songMaps: songMaps, index: index.clamp(0, songMaps.length - 1));
  }

  Future<void> savePlaybackSession(List<Song> queue, int index) async {
    if (queue.isEmpty) {
      await _settingsBox.delete('playback_queue');
      await _settingsBox.delete('playback_queue_index');
      return;
    }
    await _settingsBox.put('playback_queue', [
      for (final song in queue) song.toMap(),
    ]);
    await _settingsBox.put(
      'playback_queue_index',
      index.clamp(0, queue.length - 1),
    );
  }

  // --- Audio Effects (fade in/out, equalizer) ---

  // 每个 getter 都做类型防御：一份手改/损坏的备份写进错误类型的值时，
  // 退回默认值而不是在 main() 构造 handler 时抛 TypeError（启动崩溃循环）。
  bool getFadeEnabled() {
    final v = _settingsBox.get('fade_enabled', defaultValue: false);
    return v is bool ? v : false;
  }

  Future<void> saveFadeEnabled(bool enabled) async {
    await _settingsBox.put('fade_enabled', enabled);
  }

  bool getEqualizerEnabled() {
    final v = _settingsBox.get('equalizer_enabled', defaultValue: false);
    return v is bool ? v : false;
  }

  Future<void> saveEqualizerEnabled(bool enabled) async {
    await _settingsBox.put('equalizer_enabled', enabled);
  }

  /// Persisted equalizer band gains in dB, index-aligned with the device's
  /// band list. Empty when never tuned.
  List<double> getEqualizerGains() {
    final raw = _settingsBox.get('equalizer_gains');
    if (raw is! List) return const [];
    return [for (final v in raw) if (v is num) v.toDouble()];
  }

  Future<void> saveEqualizerGains(List<double> gains) async {
    await _settingsBox.put('equalizer_gains', gains);
  }

  double getSavedVolume() {
    final v = _settingsBox.get('volume', defaultValue: 1.0);
    return v is num ? v.toDouble() : 1.0;
  }

  Future<void> saveVolume(double volume) async {
    await _settingsBox.put('volume', volume);
  }

  bool getAutoCheckUpdates() {
    final v = _settingsBox.get('auto_check_updates', defaultValue: true);
    return v is bool ? v : true;
  }

  Future<void> saveAutoCheckUpdates(bool enabled) async {
    await _settingsBox.put('auto_check_updates', enabled);
  }

  /// 水墨专属通知栏（自定义 RemoteViews 通知）开关，默认开启。
  /// 关闭后仅保留系统原生媒体通知（锁屏/控制中心/蓝牙）。
  bool getCustomNotificationEnabled() {
    final v = _settingsBox.get('custom_notification_enabled', defaultValue: true);
    return v is bool ? v : true;
  }

  Future<void> saveCustomNotificationEnabled(bool enabled) async {
    await _settingsBox.put('custom_notification_enabled', enabled);
  }

  DateTime? getLastUpdateCheckTime() {
    final v = _settingsBox.get('last_update_check_ms');
    if (v is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(v);
  }

  Future<void> saveLastUpdateCheckTime(DateTime time) async {
    await _settingsBox.put('last_update_check_ms', time.millisecondsSinceEpoch);
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

    final updatedSongDurations = Map<String, int>.from(
      current.songDurationSeconds,
    );
    updatedSongDurations[song.id] =
        (updatedSongDurations[song.id] ?? 0) + seconds;

    final updatedHourly = Map<int, int>.from(current.hourlyDurationSeconds);
    updatedHourly[timestamp.hour] =
        (updatedHourly[timestamp.hour] ?? 0) + seconds;

    final updatedMetaCache = Map<String, SongMetaSnapshot>.from(
      current.songMetaCache,
    );
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

    final updatedMetaCache = Map<String, SongMetaSnapshot>.from(
      current.songMetaCache,
    );
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
  List<DailyListeningRecord> getDailyRecordsInRange(
    DateTime startDate,
    DateTime endDate,
  ) {
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

  // --- Backup & Restore ---

  /// Serializes every box into a plain JSON-encodable map. Values are the raw
  /// Hive maps, so restore needs no model-aware parsing.
  Map<String, dynamic> exportBackup() {
    Map<String, dynamic> dumpBox(Box box) => {
      for (final key in box.keys)
        if (box.get(key) != null) key.toString(): box.get(key),
    };
    return {
      'format': 'aquamoon-backup',
      'backupVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'songs': dumpBox(_songsBox),
      'playlists': dumpBox(_playlistsBox),
      'history': dumpBox(_historyBox),
      'settings': dumpBox(_settingsBox),
      'stats': dumpBox(_statsBox),
    };
  }

  /// Overwrites every box with the contents of a backup produced by
  /// [exportBackup]. Throws [FormatException] when the payload is not an
  /// AquaMoon backup. Entries that don't survive their model's `fromMap`
  /// are dropped instead of persisted, so a corrupted / hand-edited backup
  /// degrades gracefully instead of crashing the next app start.
  Future<void> restoreBackup(Map<String, dynamic> data) async {
    if (data['format'] != 'aquamoon-backup') {
      throw const FormatException('不是水月音备份文件');
    }
    Future<void> restoreBox(
      Box box,
      Map<String, dynamic>? section,
    ) async {
      if (section == null) return;
      await box.clear();
      await box.putAll(section);
    }

    await restoreBox(_songsBox, _validatedSection(data['songs'], _parseSong));
    await restoreBox(
      _playlistsBox,
      _validatedSection(data['playlists'], _parsePlaylist),
    );
    await restoreBox(_historyBox, _validatedHistory(data['history']));
    await restoreBox(_settingsBox, _asSection(data['settings']));
    await restoreBox(
      _statsBox,
      _validatedSection(data['stats'], _parseDailyRecord),
    );
  }

  static Song? _parseSong(Object? raw) {
    if (raw is! Map) return null;
    try {
      final song = Song.fromMap(raw);
      return song.id.isEmpty ? null : song;
    } catch (_) {
      return null;
    }
  }

  static Playlist? _parsePlaylist(Object? raw) {
    if (raw is! Map) return null;
    try {
      return Playlist.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  static DailyListeningRecord? _parseDailyRecord(Object? raw) {
    if (raw is! Map) return null;
    try {
      return DailyListeningRecord.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// Keeps only the entries whose value parses via [parse]; keys survive as-is.
  static Map<String, dynamic>? _validatedSection(
    Object? raw,
    Object? Function(Object?) parse,
  ) {
    final section = _asSection(raw);
    if (section == null) return null;
    return {
      for (final e in section.entries)
        if (parse(e.value) != null) e.key.toString(): e.value,
    };
  }

  /// 历史区只有一个列表键；写入前确保是干净的 String 列表。
  static Map<String, dynamic>? _validatedHistory(Object? raw) {
    final section = _asSection(raw);
    if (section == null) return null;
    final ids = section['recent_song_ids'];
    return {
      'recent_song_ids': ids is List
          ? [for (final e in ids) if (e != null) e.toString()]
          : const <String>[],
    };
  }

  static Map<String, dynamic>? _asSection(Object? raw) {
    if (raw is Map) {
      return {for (final e in raw.entries) e.key.toString(): e.value};
    }
    return null;
  }
}
