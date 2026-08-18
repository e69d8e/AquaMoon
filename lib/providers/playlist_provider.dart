import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

class PlaylistNotifier extends StateNotifier<List<Playlist>> {
  final StorageService _storageService;
  static const _uuid = Uuid();

  PlaylistNotifier(this._storageService) : super([]) {
    _loadPlaylists();
  }

  void _loadPlaylists() {
    state = _storageService.getAllPlaylists();
  }

  Future<Playlist> createPlaylist(String name, {String description = ''}) async {
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? '新建歌单' : name.trim(),
      description: description.trim(),
      songIds: [],
      createdAt: DateTime.now(),
    );
    await _storageService.savePlaylist(playlist);
    _loadPlaylists();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    await _storageService.deletePlaylist(id);
    _loadPlaylists();
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final index = state.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = state[index];
      if (!playlist.songIds.contains(songId)) {
        final updated = playlist.copyWith(
          songIds: [...playlist.songIds, songId],
        );
        await _storageService.savePlaylist(updated);
        _loadPlaylists();
      }
    }
  }

  Future<void> addSongsToPlaylist(String playlistId, List<String> songIds) async {
    final index = state.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = state[index];
      final currentSet = playlist.songIds.toSet();
      final toAdd = songIds.where((id) => !currentSet.contains(id)).toList();
      if (toAdd.isNotEmpty) {
        final updated = playlist.copyWith(
          songIds: [...playlist.songIds, ...toAdd],
        );
        await _storageService.savePlaylist(updated);
        _loadPlaylists();
      }
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final index = state.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = state[index];
      final newIds = List<String>.from(playlist.songIds)..remove(songId);
      final updated = playlist.copyWith(songIds: newIds);
      await _storageService.savePlaylist(updated);
      _loadPlaylists();
    }
  }

  Future<bool> toggleSongInPlaylist(String playlistId, String songId) async {
    final index = state.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = state[index];
      final contains = playlist.songIds.contains(songId);
      if (contains) {
        await removeSongFromPlaylist(playlistId, songId);
        return false;
      } else {
        await addSongToPlaylist(playlistId, songId);
        return true;
      }
    }
    return false;
  }

  Future<void> setPlaylistCover(String playlistId, String? coverArtUri) async {
    final index = state.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = state[index];
      final updated = playlist.copyWith(coverArtUri: coverArtUri);
      await _storageService.savePlaylist(updated);
      _loadPlaylists();
    }
  }
}

final playlistNotifierProvider = StateNotifierProvider<PlaylistNotifier, List<Playlist>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return PlaylistNotifier(storage);
});

final favoritesSongsProvider = Provider<List<Song>>((ref) {
  final library = ref.watch(libraryNotifierProvider);
  return library.songs.where((s) => s.isFavorite).toList();
});

final historySongsProvider = Provider<List<Song>>((ref) {
  final library = ref.watch(libraryNotifierProvider);
  final storage = ref.watch(storageServiceProvider);
  final historyIds = storage.getHistoryIds();

  final songMap = {for (final s in library.songs) s.id: s};
  final result = <Song>[];

  for (final id in historyIds) {
    final song = songMap[id];
    if (song != null) {
      result.add(song);
    }
  }

  return result;
});
