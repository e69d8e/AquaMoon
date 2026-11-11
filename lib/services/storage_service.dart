import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils/formatters.dart';
import '../models/listening_stats.dart';
import '../models/qq_music_config.dart';
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

    // QQ 音乐 PC 私有通道需要稳定的设备标识：在启动时 await 落盘，
    // 避开在 provider 构造/widget build 里做 fire-and-forget 的箱写盘。
    await _ensureQQMusicDesktopGuid();
  }

  Future<void> _ensureQQMusicDesktopGuid() async {
    final existing =
        (_settingsBox.get('qq_music_desktop_guid') as String?)?.trim() ?? '';
    if (existing.isNotEmpty) return;
    await _settingsBox.put(
      'qq_music_desktop_guid',
      _generateQQMusicDesktopGuid(),
    );
  }

  static String _generateQQMusicDesktopGuid() {
    const hex = '0123456789ABCDEF';
    final rnd = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buf.write(hex[rnd.nextInt(16)]);
    }
    return buf.toString();
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

  // --- QQ Music Favorites Config & Cache ---

  QQMusicConfig getQQMusicConfig() {
    return QQMusicConfig.fromMap(_settingsBox.get('qq_music_config'));
  }

  /// PC 私有通道（最近播放读写）使用的设备标识；首次启动时已落盘，
  /// 之后只做同步读取，避免每次启动换 guid 导致云端行为异常。
  String getQQMusicDesktopGuid() {
    final existing =
        (_settingsBox.get('qq_music_desktop_guid') as String?)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    // 理论上不会走到（init 已落盘）；兵底生成一个稳定值但不做写盘，
    // 避开在 widget build 期间发起异步 I/O。
    return _generateQQMusicDesktopGuid();
  }

  Future<void> saveQQMusicConfig(QQMusicConfig config) async {
    await _settingsBox.put('qq_music_config', config.toMap());
  }

  Future<void> clearQQMusicConfig() async {
    await _settingsBox.delete('qq_music_config');
    await _settingsBox.delete('qq_favorites_cache');
    await _settingsBox.delete('qq_cloud_imported_counts');
    await _settingsBox.delete('qq_cloud_today_listen_seconds');
    await _settingsBox.delete('qq_cloud_stats_summary');
    await _settingsBox.delete('qq_manual_links');
    await _settingsBox.delete('qq_manual_exclusions');
  }

  // --- QQ Music 手动关联（云端曲目 <-> 本地文件） ---

  /// 用户手动指定的关联：`qqSongMid -> 本地 songId`。
  ///
  /// 自动匹配靠标题/歌手，难免有匹配不上或匹配错的情况；手动关联优先级
  /// 高于自动匹配，且写回本地曲库的 `qqSongMid` 后重新同步也不会丢。
  Map<String, String> getQQMusicManualLinks() {
    final raw = _settingsBox.get('qq_manual_links');
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((k, v) {
      if (k != null && v != null) {
        result[k.toString()] = v.toString();
      }
    });
    return result;
  }

  Future<void> saveQQMusicManualLink({
    required String songMid,
    required String songId,
  }) async {
    if (songMid.isEmpty || songId.isEmpty) return;
    final links = Map<String, String>.from(getQQMusicManualLinks());
    links[songMid] = songId;
    await _settingsBox.put('qq_manual_links', links);
    // 手动指定后不再是「排除」状态
    final exclusions = getQQMusicManualExclusions();
    if (exclusions.contains(songMid)) {
      await _settingsBox.put(
        'qq_manual_exclusions',
        exclusions.difference({songMid}).toList(),
      );
    }
  }

  Future<void> removeQQMusicManualLink(String songMid) async {
    if (songMid.isEmpty) return;
    final links = Map<String, String>.from(getQQMusicManualLinks());
    links.remove(songMid);
    await _settingsBox.put('qq_manual_links', links);
  }

  /// 用户显式取消关联的 `qqSongMid`：后续同步不再自动匹配到任何本地文件，
  /// 否则一取消就被自动匹配重新接上，用户会觉得「取消不掉」。
  Set<String> getQQMusicManualExclusions() {
    final raw = _settingsBox.get('qq_manual_exclusions');
    if (raw is! List) return const {};
    return raw.map((e) => e.toString()).toSet();
  }

  Future<void> addQQMusicManualExclusion(String songMid) async {
    if (songMid.isEmpty) return;
    final exclusions = {...getQQMusicManualExclusions(), songMid};
    await _settingsBox.put('qq_manual_exclusions', exclusions.toList());
  }

  Future<void> removeQQMusicManualExclusion(String songMid) async {
    if (songMid.isEmpty) return;
    final exclusions = getQQMusicManualExclusions().difference({songMid});
    await _settingsBox.put('qq_manual_exclusions', exclusions.toList());
  }

  List<Song> getQQMusicFavoritesCache() {
    final raw = _settingsBox.get('qq_favorites_cache');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Song.fromMap(item),
    ];
  }

  Future<void> saveQQMusicFavoritesCache(List<Song> songs) async {
    await _settingsBox.put('qq_favorites_cache', [
      for (final song in songs) song.toMap(),
    ]);
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
      return;
    }

    // Also increment playCount in QQ Music favorites cache if it's an online track
    final qqCacheRaw = _settingsBox.get('qq_favorites_cache');
    if (qqCacheRaw is List) {
      var changed = false;
      final updatedList = <Map<String, dynamic>>[];
      for (final item in qqCacheRaw) {
        if (item is Map) {
          final s = Song.fromMap(item);
          if (s.id == songId) {
            updatedList.add(s.copyWith(playCount: s.playCount + 1).toMap());
            changed = true;
          } else {
            updatedList.add(s.toMap());
          }
        }
      }
      if (changed) {
        await _settingsBox.put('qq_favorites_cache', updatedList);
      }
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
    updatedMetaCache[song.id] = SongMetaSnapshot.fromSong(song);

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
    updatedMetaCache[song.id] = SongMetaSnapshot.fromSong(song);

    final updatedRecord = current.copyWith(
      songPlayCounts: updatedPlayCounts,
      songMetaCache: updatedMetaCache,
    );

    await saveDailyListeningRecord(updatedRecord);
  }

  /// 获取 QQ 音乐云端听歌统计同步与上报摘要。
  QQMusicCloudStatsSummary getQQMusicCloudStatsSummary() {
    return QQMusicCloudStatsSummary.fromMap(
      _settingsBox.get('qq_cloud_stats_summary'),
    );
  }

  /// 记录一次向 QQ 音乐云端成功上报的播放。
  Future<void> recordQQMusicPlaybackReport() async {
    final current = getQQMusicCloudStatsSummary();
    final updated = current.copyWith(
      reportedPlayCount: current.reportedPlayCount + 1,
      lastSyncTime: DateTime.now(),
    );
    await _settingsBox.put('qq_cloud_stats_summary', updated.toMap());
  }

  /// 幂等合并 QQ 音乐云端听歌历史与今日有效听歌时长。
  ///
  /// - 每首曲目的云端累计播放次数 ([QQMusicCloudHistoryEntry.playCount]，即
  ///   接口的 `listenCnt`) 只升不降地写回本地曲库与「我喜欢」缓存的
  ///   [Song.playCount]，同时补齐缺失的数字 [Song.qqSongId]；
  /// - [todayListenSeconds] 是云端「今日累计有效听歌时间」，按日期基准做差值，
  ///   只把新增部分并入当天统计，因此反复同步不会重复累加；
  /// - 云端「最近播放」是累计历史，不能当作当天播放次数灌进当天统计，否则
  ///   每日榜与今日时长会被历史数据污染。
  ///
  /// 返回本次播放次数有所提升（或补齐了 songId）的曲目数。
  Future<int> mergeQQMusicCloudListeningSongs(
    List<QQMusicCloudHistoryEntry> entries, {
    DateTime? timestamp,
    int? todayListenSeconds,
  }) async {
    final now = timestamp ?? DateTime.now();
    final dateStr = Formatters.formatDateKey(now);

    // 本地曲库按 qqSongMid / id 建索引，云端曲目对到本地时沿用本地 id。
    final localByMid = <String, Song>{};
    final localById = <String, Song>{};
    for (final s in getAllSongs()) {
      localById[s.id] = s;
      final mid = s.qqSongMid;
      if (mid != null && mid.isNotEmpty) localByMid[mid] = s;
    }

    var updatedSongCount = 0;

    // 1) 每首曲目的云端累计播放次数
    final favCache = getQQMusicFavoritesCache();
    final favIndexById = <String, int>{};
    final favIndexByMid = <String, int>{};
    for (var i = 0; i < favCache.length; i++) {
      favIndexById[favCache[i].id] = i;
      final mid = favCache[i].qqSongMid;
      if (mid != null && mid.isNotEmpty) favIndexByMid[mid] = i;
    }
    var cacheChanged = false;
    final updatedCache = [...favCache];

    for (final entry in entries) {
      final cloudSong = entry.song;
      final mid = entry.songMid;
      final targetPlays = entry.playCount > 0 ? entry.playCount : 1;
      final cloudSongId = cloudSong.qqSongId;

      final local = (mid.isNotEmpty ? localByMid[mid] : null) ?? localById[cloudSong.id];
      if (local != null) {
        final needsPlays = local.playCount < targetPlays;
        final needsId = (local.qqSongId ?? 0) <= 0 && (cloudSongId ?? 0) > 0;
        if (needsPlays || needsId) {
          final updated = local.copyWith(
            playCount: needsPlays ? targetPlays : local.playCount,
            qqSongId: needsId ? cloudSongId : local.qqSongId,
          );
          await saveSong(updated);
          localByMid[mid] = updated;
          localById[updated.id] = updated;
          updatedSongCount++;
        }
      }

      final idx = favIndexById[cloudSong.id] ?? (mid.isNotEmpty ? favIndexByMid[mid] : null);
      if (idx != null) {
        final cached = updatedCache[idx];
        final needsPlays = cached.playCount < targetPlays;
        final needsId = (cached.qqSongId ?? 0) <= 0 && (cloudSongId ?? 0) > 0;
        if (needsPlays || needsId) {
          updatedCache[idx] = cached.copyWith(
            playCount: needsPlays ? targetPlays : cached.playCount,
            qqSongId: needsId ? cloudSongId : cached.qqSongId,
          );
          cacheChanged = true;
          updatedSongCount++;
        }
      }
    }
    if (cacheChanged) {
      await saveQQMusicFavoritesCache(updatedCache);
    }

    // 2) 今日有效听歌时长：按日期基准做增量，避免重复累加
    final rawBaseline = _settingsBox.get('qq_cloud_today_listen_seconds');
    final baseline = <String, int>{};
    if (rawBaseline is Map) {
      rawBaseline.forEach((k, v) {
        if (v is num) baseline[k.toString()] = v.toInt();
      });
    }

    final currentRecord = getDailyListeningRecord(dateStr);
    var addedSeconds = 0;
    var addedPlays = 0;
    final updatedSongDurations = Map<String, int>.from(
      currentRecord.songDurationSeconds,
    );
    final updatedPlayCounts = Map<String, int>.from(
      currentRecord.songPlayCounts,
    );
    final updatedHourly = Map<int, int>.from(currentRecord.hourlyDurationSeconds);
    final updatedMetaCache = Map<String, SongMetaSnapshot>.from(
      currentRecord.songMetaCache,
    );

    // 今天（按云端 lastTime）听过的曲目：无论本次时长增量是否为 0 都要收集，
    // 否则会出现「收听曲目 N 首但播放次数为 0」的自相矛盾统计。
    final todayEntries = <({String songId, Song song})>[];
    for (final entry in entries) {
      final playedAt = entry.lastPlayedAt;
      if (playedAt == null) continue;
      if (Formatters.formatDateKey(playedAt) != dateStr) continue;
      final mid = entry.songMid;
      final local =
          (mid.isNotEmpty ? localByMid[mid] : null) ?? localById[entry.song.id];
      final song = local ?? entry.song;
      todayEntries.add((songId: song.id, song: song));
    }

    if (todayListenSeconds != null) {
      final previous = baseline[dateStr] ?? 0;
      final delta = todayListenSeconds - previous;
      if (delta > 0) {
        addedSeconds = delta;
        updatedHourly[now.hour] = (updatedHourly[now.hour] ?? 0) + delta;

        // 今天在云端听过的曲目平分这段时长，让当天歌曲榜也能看到它们。
        if (todayEntries.isNotEmpty) {
          final share = delta ~/ todayEntries.length;
          var remainder = delta - share * todayEntries.length;
          for (final item in todayEntries) {
            var extra = share;
            if (remainder > 0) {
              extra += 1;
              remainder -= 1;
            }
            if (extra <= 0) continue;
            updatedSongDurations[item.songId] =
                (updatedSongDurations[item.songId] ?? 0) + extra;
          }
        }
      }
      baseline[dateStr] = todayListenSeconds;

      // 只保留最近 14 天的基准，避免设置项无限增长。
      if (baseline.length > 14) {
        final keep = baseline.keys.toList()..sort();
        for (final key in keep.take(baseline.length - 14)) {
          baseline.remove(key);
        }
      }
      await _settingsBox.put('qq_cloud_today_listen_seconds', baseline);
    }

    // 云端「最近播放」只提供累计 listenCnt，没有「今日单曲次数」，
    // 因此今天在云端听过的曲目按「至少一次」计入，保证
    // 「收听曲目 N 首」与「播放次数」自洽。已存在计数（本地播放或上次同步
    // 已记）的曲目不重复累加，因此反复同步仍然幂等。
    for (final item in todayEntries) {
      updatedMetaCache[item.songId] = SongMetaSnapshot.fromSong(item.song);
      if (updatedPlayCounts[item.songId] == null) {
        updatedPlayCounts[item.songId] = 1;
        addedPlays++;
      }
    }

    if (addedSeconds > 0 || addedPlays > 0) {
      await saveDailyListeningRecord(
        currentRecord.copyWith(
          totalDurationSeconds:
              currentRecord.totalDurationSeconds + addedSeconds,
          songDurationSeconds: updatedSongDurations,
          songPlayCounts: updatedPlayCounts,
          hourlyDurationSeconds: updatedHourly,
          songMetaCache: updatedMetaCache,
        ),
      );
    }

    // 3) 同步摘要（展示云端累计次数与今日时长）
    var cloudPlays = 0;
    for (final entry in entries) {
      cloudPlays += entry.playCount > 0 ? entry.playCount : 1;
    }
    final prevSummary = getQQMusicCloudStatsSummary();
    final nextSummary = prevSummary.copyWith(
      importedSongCount: entries.length,
      importedPlayCount: cloudPlays,
      importedDurationSeconds:
          prevSummary.importedDurationSeconds + addedSeconds,
      todayListenSeconds: todayListenSeconds ?? prevSummary.todayListenSeconds,
      lastSyncTime: now,
    );
    await _settingsBox.put('qq_cloud_stats_summary', nextSummary.toMap());

    return updatedSongCount;
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

  // --- Cover Cache Migration (temp dir → application support dir) ---

  /// 历史版本把封面缓存写进系统临时目录（covers/ 与 online_covers/）。系统
  /// 清理应用缓存后，持久化记录里的 file:// URI 会永久失效且无从自愈。
  /// 这里把仍存在的封面文件搬到应用支持目录并改写歌曲与歌单记录；已丢失
  /// 的封面直接清空字段，交给“重新扫描曲库 / 智能补齐封面”重新获取。
  /// 返回发生变更的记录数。
  ///
  /// [tempDir] / [supportDir] 可注入（测试用）；缺省时经 path_provider 解析，
  /// 平台通道不可用时直接返回 0。
  Future<int> migrateTempCoverCaches({
    Directory? tempDir,
    Directory? supportDir,
  }) async {
    tempDir ??= await _resolveDirOrNull(getTemporaryDirectory);
    supportDir ??= await _resolveDirOrNull(getApplicationSupportDirectory);
    if (tempDir == null || supportDir == null) {
      // 平台通道不可用（如单元测试）且未注入目录——无事可做。
      return 0;
    }
    // 闭包内做不了空提升（参数可能被重赋值），先固化成 final 局部量。
    final tempRoot = tempDir;
    final supportRoot = supportDir;
    final tempPrefix = '${tempRoot.path}${Platform.pathSeparator}';

    /// 返回 (是否有变动, 新 URI)；`touched && uri == null` 表示源文件已
    /// 丢失、应清空字段。
    Future<(bool, String?)> migrateCover(String? uri) async {
      if (uri == null || !uri.startsWith('file://')) return (false, null);
      final sourcePath = Uri.tryParse(uri)?.toFilePath();
      if (sourcePath == null || !sourcePath.startsWith(tempPrefix)) {
        return (false, null);
      }
      final source = File(sourcePath);
      if (!await source.exists()) return (true, null);
      final target = File(
        p.join(
          supportRoot.path,
          p.relative(sourcePath, from: tempRoot.path),
        ),
      );
      if (!await target.exists()) {
        await target.create(recursive: true);
        await source.copy(target.path);
      }
      return (true, target.uri.toString());
    }

    var changed = 0;
    final changedSongs = <Song>[];
    for (final raw in _songsBox.values) {
      if (raw is! Map) continue;
      final song = Song.fromMap(raw);
      final (touched, newUri) = await migrateCover(song.albumArtUri);
      if (!touched) continue;
      changedSongs.add(
        newUri == null
            ? song.copyWith(clearAlbumArtUri: true)
            : song.copyWith(albumArtUri: newUri),
      );
      changed++;
    }
    if (changedSongs.isNotEmpty) {
      await saveSongs(changedSongs);
    }

    for (final raw in _playlistsBox.values) {
      if (raw is! Map) continue;
      final playlist = Playlist.fromMap(raw);
      final (touched, newUri) = await migrateCover(playlist.coverArtUri);
      if (!touched) continue;
      await savePlaylist(
        newUri == null
            ? playlist.copyWith(clearCoverArtUri: true)
            : playlist.copyWith(coverArtUri: newUri),
      );
      changed++;
    }
    return changed;
  }

  static Future<Directory?> _resolveDirOrNull(
    Future<Directory> Function() resolve,
  ) async {
    try {
      return await resolve();
    } catch (_) {
      return null;
    }
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
