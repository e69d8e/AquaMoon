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
    state = [...state, playlist];
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    await _storageService.deletePlaylist(id);
    state = state.where((p) => p.id != id).toList();
  }

  /// 重命名歌单（顺带更新描述）；名称为空时静默忽略。
  Future<void> renamePlaylist(
    String id,
    String name, {
    String? description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = state.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = state[index].copyWith(
      name: trimmed,
      description: description?.trim() ?? state[index].description,
    );
    await _storageService.savePlaylist(updated);
    state = [
      for (final p in state)
        if (p.id == id) updated else p,
    ];
  }

  /// 歌单内拖拽排序。[oldIndex]/[newIndex] 遵循 ReorderableListView 的语义
  ///（目标位置按移除前的索引给出）。
  ///
  /// 详情页渲染的是“过滤掉曲库中已不存在的歌曲”后的列表，拖拽索引以它为准；
  /// 历史数据里 songIds 可能残留失效 id，所以这里先按曲库把失效 id 剔除，
  /// 再套用索引，否则拖拽会作用到错误的歌上（或看起来毫无效果）。
  Future<void> reorderPlaylistSongs(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final index = state.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = state[index];

    final existingIds = playlist.songIds
        .where((id) => _storageService.getSong(id) != null)
        .toList();
    if (oldIndex < 0 || oldIndex >= existingIds.length) return;
    final clampedNewIndex = newIndex.clamp(0, existingIds.length - 1);

    List<String> ids;
    if (existingIds.length == playlist.songIds.length) {
      ids = List<String>.from(playlist.songIds);
    } else {
      ids = existingIds;
    }
    if (oldIndex != clampedNewIndex) {
      final id = ids.removeAt(oldIndex);
      ids.insert(clampedNewIndex, id);
    }

    final updated = playlist.copyWith(songIds: ids);
    await _storageService.savePlaylist(updated);
    state = [
      for (final p in state)
        if (p.id == playlistId) updated else p,
    ];
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
        state = [
          for (final p in state)
            if (p.id == playlistId) updated else p,
        ];
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
        state = [
          for (final p in state)
            if (p.id == playlistId) updated else p,
        ];
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
      state = [
        for (final p in state)
          if (p.id == playlistId) updated else p,
      ];
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
      state = [
        for (final p in state)
          if (p.id == playlistId) updated else p,
      ];
    }
  }
}

final playlistNotifierProvider = StateNotifierProvider<PlaylistNotifier, List<Playlist>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return PlaylistNotifier(storage);
});

final favoritesSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(libraryNotifierProvider.select((s) => s.songs));
  return songs.where((s) => s.isFavorite).toList();
});

final historySongsProvider = Provider<List<Song>>((ref) {
  // Bumping this tick (e.g. after 清空历史) forces a re-read of the box;
  // normal playback already rebuilds this provider via playCount changes.
  ref.watch(historyRefreshTickProvider);
  final songs = ref.watch(libraryNotifierProvider.select((s) => s.songs));
  final storage = ref.watch(storageServiceProvider);
  final historyIds = storage.getHistoryIds();

  final songMap = {for (final s in songs) s.id: s};
  final result = <Song>[];

  for (final id in historyIds) {
    final song = songMap[id];
    if (song != null) {
      result.add(song);
    }
  }

  return result;
});

/// 手动触发最近播放列表重算的计数器（清空历史等不走 playCount 的操作）。
final historyRefreshTickProvider = StateProvider<int>((ref) => 0);
