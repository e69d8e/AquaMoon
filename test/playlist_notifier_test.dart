import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/playlist_provider.dart';
import 'package:aquamoon/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaylistNotifier & Favorites/History Providers Unit Tests', () {
    late Directory tempDir;
    late StorageService storageService;

    final song1 = Song(
      id: 'song-1',
      title: '高山流水',
      artist: '古琴名家',
      album: '国乐大典',
      durationMs: 200000,
      filePath: '/music/gaoshan.mp3',
      dateAdded: DateTime(2026, 1, 1),
      isFavorite: true,
    );

    final song2 = Song(
      id: 'song-2',
      title: '渔舟唱晚',
      artist: '筝曲大师',
      album: '江南丝竹',
      durationMs: 180000,
      filePath: '/music/yuzhou.mp3',
      dateAdded: DateTime(2026, 1, 2),
      isFavorite: false,
    );

    final song3 = Song(
      id: 'song-3',
      title: '梅花三弄',
      artist: '古筝名家',
      album: '琴韵禅心',
      durationMs: 220000,
      filePath: '/music/meihua.mp3',
      dateAdded: DateTime(2026, 1, 3),
      isFavorite: true,
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_playlist_test_');
      storageService = StorageService();
      await storageService.init(tempDir.path);
      await storageService.saveSongs([song1, song2, song3]);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('createPlaylist adds a new playlist and saves to storage', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playlistNotifierProvider.notifier);
      final pl = await notifier.createPlaylist('我的古琴集', description: '幽静悠远');

      expect(pl.name, '我的古琴集');
      expect(pl.description, '幽静悠远');
      expect(pl.songIds, isEmpty);

      final state = container.read(playlistNotifierProvider);
      expect(state.length, 1);
      expect(state.first.id, pl.id);

      final fromStorage = storageService.getAllPlaylists();
      expect(fromStorage.length, 1);
      expect(fromStorage.first.name, '我的古琴集');
    });

    test('addSongToPlaylist and addSongsToPlaylist handle single and batch additions with deduplication', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playlistNotifierProvider.notifier);
      final pl = await notifier.createPlaylist('茶道配乐');

      // 1. Add single song
      await notifier.addSongToPlaylist(pl.id, 'song-1');
      var state = container.read(playlistNotifierProvider);
      expect(state.first.songIds, ['song-1']);

      // 2. Prevent adding same song again
      await notifier.addSongToPlaylist(pl.id, 'song-1');
      state = container.read(playlistNotifierProvider);
      expect(state.first.songIds, ['song-1']);

      // 3. Batch add songs with duplicate
      await notifier.addSongsToPlaylist(pl.id, ['song-1', 'song-2', 'song-3']);
      state = container.read(playlistNotifierProvider);
      expect(state.first.songIds, ['song-1', 'song-2', 'song-3']);
    });

    test('removeSongFromPlaylist removes specific song accurately', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playlistNotifierProvider.notifier);
      final pl = await notifier.createPlaylist('禅修音乐');
      await notifier.addSongsToPlaylist(pl.id, ['song-1', 'song-2', 'song-3']);

      await notifier.removeSongFromPlaylist(pl.id, 'song-2');
      final state = container.read(playlistNotifierProvider);
      expect(state.first.songIds, ['song-1', 'song-3']);

      final fromStorage = storageService.getAllPlaylists().first;
      expect(fromStorage.songIds, ['song-1', 'song-3']);
    });

    test('toggleSongInPlaylist correctly adds and removes song', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playlistNotifierProvider.notifier);
      final pl = await notifier.createPlaylist('动态切换测试');

      // Initially not in playlist -> toggle adds it
      final added = await notifier.toggleSongInPlaylist(pl.id, 'song-1');
      expect(added, isTrue);
      expect(container.read(playlistNotifierProvider).first.songIds, contains('song-1'));

      // In playlist -> toggle removes it
      final removed = await notifier.toggleSongInPlaylist(pl.id, 'song-1');
      expect(removed, isFalse);
      expect(container.read(playlistNotifierProvider).first.songIds, isNot(contains('song-1')));
    });

    test('setPlaylistCover updates playlist cover URI in memory and storage', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playlistNotifierProvider.notifier);
      final pl = await notifier.createPlaylist('视觉歌单');

      await notifier.setPlaylistCover(pl.id, 'file:///covers/custom.jpg');
      final state = container.read(playlistNotifierProvider);
      expect(state.first.coverArtUri, 'file:///covers/custom.jpg');

      final fromStorage = storageService.getAllPlaylists().first;
      expect(fromStorage.coverArtUri, 'file:///covers/custom.jpg');
    });

    test('deletePlaylist removes playlist from state and storage', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playlistNotifierProvider.notifier);
      final pl = await notifier.createPlaylist('待删除歌单');
      expect(container.read(playlistNotifierProvider).length, 1);

      await notifier.deletePlaylist(pl.id);
      expect(container.read(playlistNotifierProvider), isEmpty);
      expect(storageService.getAllPlaylists(), isEmpty);
    });

    test('favoritesSongsProvider returns only favorite songs', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final favorites = container.read(favoritesSongsProvider);
      expect(favorites.length, 2);
      expect(favorites.map((s) => s.id).toSet(), {'song-1', 'song-3'});
    });

    test('historySongsProvider returns songs in history order', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      await storageService.addToHistory('song-2');
      await storageService.addToHistory('song-1');

      final history = container.read(historySongsProvider);
      expect(history.length, 2);
      expect(history[0].id, 'song-1');
      expect(history[1].id, 'song-2');
    });
  });
}
