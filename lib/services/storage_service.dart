import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../models/playback_mode.dart';

class StorageService {
  static const String _songsBoxName = 'soundcraft_songs';
  static const String _playlistsBoxName = 'soundcraft_playlists';
  static const String _historyBoxName = 'soundcraft_history';
  static const String _settingsBoxName = 'soundcraft_settings';

  late Box _songsBox;
  late Box _playlistsBox;
  late Box _historyBox;
  late Box _settingsBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _songsBox = await Hive.openBox(_songsBoxName);
    _playlistsBox = await Hive.openBox(_playlistsBoxName);
    _historyBox = await Hive.openBox(_historyBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);
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

  Future<void> toggleFavorite(String songId) async {
    final songData = _songsBox.get(songId);
    if (songData != null && songData is Map) {
      final song = Song.fromMap(songData);
      final updated = song.copyWith(isFavorite: !song.isFavorite);
      await _songsBox.put(songId, updated.toMap());
    }
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
}
