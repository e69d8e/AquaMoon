import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/library_provider.dart';
import 'package:aquamoon/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryNotifier & filteredSongsProvider Unit Tests', () {
    late Directory tempDir;
    late StorageService storageService;

    final songA = Song(
      id: 's-a',
      title: 'A Song',
      artist: 'Artist Zebra',
      album: 'Album Beta',
      durationMs: 180000,
      filePath: '/music/a.mp3',
      dateAdded: DateTime(2026, 1, 1),
      playCount: 10,
      isFavorite: false,
    );

    final songB = Song(
      id: 's-b',
      title: 'B Melody',
      artist: 'Artist Alpha',
      album: 'Album Gamma',
      durationMs: 240000,
      filePath: '/music/b.mp3',
      dateAdded: DateTime(2026, 2, 1),
      playCount: 25,
      isFavorite: true,
    );

    final songC = Song(
      id: 's-c',
      title: 'C Harmony',
      artist: 'Artist Mike',
      album: 'Album Alpha',
      durationMs: 120000,
      filePath: '/music/c.mp3',
      dateAdded: DateTime(2026, 3, 1),
      playCount: 5,
      isFavorite: false,
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_library_test_');
      storageService = StorageService();
      await storageService.init(tempDir.path);
      await storageService.saveSongs([songA, songB, songC]);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('LibraryNotifier loads songs and deduplicates', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(libraryNotifierProvider);
      expect(state.songs.length, 3);
      expect(state.isScanning, isFalse);
    });

    test('refreshPlayCountFromStorage syncs handler-side count bumps into state', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(libraryNotifierProvider.notifier);
      expect(
        container
            .read(libraryNotifierProvider)
            .songs
            .firstWhere((s) => s.id == 's-a')
            .playCount,
        10,
      );

      // Simulate the audio handler bumping the persisted count as the song
      // starts playing (StorageService.addToHistory).
      final stored = storageService.getSong('s-a')!;
      storageService.saveSong(stored.copyWith(playCount: 11));

      notifier.refreshPlayCountFromStorage('s-a');

      expect(
        container
            .read(libraryNotifierProvider)
            .songs
            .firstWhere((s) => s.id == 's-a')
            .playCount,
        11,
      );

      // No-op when storage agrees with state (e.g. duplicate events).
      notifier.refreshPlayCountFromStorage('s-a');
      expect(
        container
            .read(libraryNotifierProvider)
            .songs
            .firstWhere((s) => s.id == 's-a')
            .playCount,
        11,
      );
    });

    test('toggleFavorite updates state in-memory and in storage', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(libraryNotifierProvider.notifier);
      await notifier.toggleFavorite(songA);

      final updatedState = container.read(libraryNotifierProvider);
      final updatedSongA = updatedState.songs.firstWhere((s) => s.id == 's-a');
      expect(updatedSongA.isFavorite, isTrue);

      final fromStorage = storageService.getSong('s-a');
      expect(fromStorage?.isFavorite, isTrue);

      // Toggle back
      await notifier.toggleFavorite(updatedSongA);
      final finalSongA = container.read(libraryNotifierProvider).songs.firstWhere((s) => s.id == 's-a');
      expect(finalSongA.isFavorite, isFalse);
    });

    test('updateSong updates state in-memory and in storage', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(libraryNotifierProvider.notifier);
      final edited = songA.copyWith(title: 'A Song (Remix)', artist: 'Artist Zebra feat. Alpha');
      await notifier.updateSong(edited);

      final state = container.read(libraryNotifierProvider);
      final found = state.songs.firstWhere((s) => s.id == 's-a');
      expect(found.title, 'A Song (Remix)');
      expect(found.artist, 'Artist Zebra feat. Alpha');

      final fromStorage = storageService.getSong('s-a');
      expect(fromStorage?.title, 'A Song (Remix)');
    });

    test('deleteSong removes song from memory and storage', () async {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(libraryNotifierProvider.notifier);
      await notifier.deleteSong(songC);

      final state = container.read(libraryNotifierProvider);
      expect(state.songs.any((s) => s.id == 's-c'), isFalse);
      expect(state.songs.length, 2);

      final fromStorage = storageService.getSong('s-c');
      expect(fromStorage, isNull);
    });

    test('filteredSongsProvider filters by title, artist, and album', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      // 1. Empty search returns all
      expect(container.read(filteredSongsProvider).length, 3);

      // 2. Search by title
      container.read(searchQueryProvider.notifier).state = 'melody';
      var filtered = container.read(filteredSongsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.id, 's-b');

      // 3. Search by artist
      container.read(searchQueryProvider.notifier).state = 'zebra';
      filtered = container.read(filteredSongsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.id, 's-a');

      // 4. Search by album
      container.read(searchQueryProvider.notifier).state = 'alpha';
      filtered = container.read(filteredSongsProvider);
      // Matches songB by artist Alpha, and songC by album Alpha
      expect(filtered.length, 2);
    });

    test('filteredSongsProvider sorts correctly by all SongSortType options', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).state = '';

      // 1. Sort by title ascending
      container.read(sortTypeProvider.notifier).state = SongSortType.title;
      container.read(sortAscendingProvider.notifier).state = true;
      var list = container.read(filteredSongsProvider);
      expect(list.map((s) => s.id).toList(), ['s-a', 's-b', 's-c']);

      // 2. Sort by title descending
      container.read(sortAscendingProvider.notifier).state = false;
      list = container.read(filteredSongsProvider);
      expect(list.map((s) => s.id).toList(), ['s-c', 's-b', 's-a']);

      // 3. Sort by artist ascending
      container.read(sortTypeProvider.notifier).state = SongSortType.artist;
      container.read(sortAscendingProvider.notifier).state = true;
      list = container.read(filteredSongsProvider);
      expect(list.map((s) => s.id).toList(), ['s-b', 's-c', 's-a']);

      // 4. Sort by duration ascending
      container.read(sortTypeProvider.notifier).state = SongSortType.duration;
      container.read(sortAscendingProvider.notifier).state = true;
      list = container.read(filteredSongsProvider);
      expect(list.map((s) => s.id).toList(), ['s-c', 's-a', 's-b']);

      // 5. Sort by playCount descending
      container.read(sortTypeProvider.notifier).state = SongSortType.playCount;
      container.read(sortAscendingProvider.notifier).state = false;
      list = container.read(filteredSongsProvider);
      expect(list.map((s) => s.id).toList(), ['s-b', 's-a', 's-c']);

      // 6. Sort by dateAdded ascending
      container.read(sortTypeProvider.notifier).state = SongSortType.dateAdded;
      container.read(sortAscendingProvider.notifier).state = true;
      list = container.read(filteredSongsProvider);
      expect(list.map((s) => s.id).toList(), ['s-a', 's-b', 's-c']);
    });

    test('filteredSongsProvider does NOT rebuild or re-filter when scanning progress updates', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
      );
      addTearDown(container.dispose);

      final initialFiltered = container.read(filteredSongsProvider);

      // Now simulate scan progress text and percent change on LibraryNotifier
      final notifier = container.read(libraryNotifierProvider.notifier);
      notifier.state = notifier.state.copyWith(
        isScanning: true,
        scanProgressText: 'Parsing file 1 of 100...',
        scanProgressPercent: 0.01,
      );

      final secondFiltered = container.read(filteredSongsProvider);
      // Because filteredSongsProvider uses .select((s) => s.songs), it should not have re-evaluated
      expect(identical(initialFiltered, secondFiltered), isTrue);

      notifier.state = notifier.state.copyWith(
        scanProgressText: 'Parsing file 50 of 100...',
        scanProgressPercent: 0.50,
      );

      final thirdFiltered = container.read(filteredSongsProvider);
      expect(identical(initialFiltered, thirdFiltered), isTrue);
    });
  });

  group('Duplicate record merging on startup dedup', () {
    late Directory tempDir;
    late StorageService storageService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_dedup_test_');
      storageService = StorageService();
      await storageService.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storageService)],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Dedup writes are scheduled fire-and-forget from the notifier
    /// constructor; poll until they land so assertions are deterministic and
    /// nothing outlives Hive.close().
    Future<void> waitUntilStorageSettled(bool Function() condition) async {
      for (var i = 0; i < 100; i++) {
        if (condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('storage did not settle in time');
    }

    test('matched lyrics on the dropped duplicate survive dedup', () async {
      // Hive box iteration is key-ordered, so ids encode which record comes
      // first: the copy WITHOUT lyrics is the one dedup keeps.
      await storageService.saveSongs([
        Song(
          id: 'a-no-lyrics',
          title: '同一首歌',
          artist: '同一位歌手',
          album: '专辑',
          durationMs: 200000,
          filePath: '/music/dup1.mp3',
          dateAdded: DateTime(2026, 1, 1),
          playCount: 3,
        ),
        Song(
          id: 'b-with-lyrics',
          title: '同一首歌',
          artist: '同一位歌手',
          album: '专辑',
          durationMs: 200500,
          filePath: '/music/dup2.mp3',
          dateAdded: DateTime(2026, 2, 1),
          lrcContent: '[00:01.00]匹配到的歌词',
          albumArtUri: 'https://cover.example/art.jpg',
          playCount: 7,
          isFavorite: true,
        ),
      ]);

      final state = buildContainer().read(libraryNotifierProvider);

      expect(state.songs.length, 1);
      final merged = state.songs.single;
      expect(merged.id, 'a-no-lyrics');
      expect(merged.lrcContent, '[00:01.00]匹配到的歌词');
      expect(merged.albumArtUri, 'https://cover.example/art.jpg');
      expect(merged.playCount, 7);
      expect(merged.isFavorite, isTrue);

      // The drop is persisted, and the kept record carries the merged data.
      await waitUntilStorageSettled(
        () => storageService.getSong('b-with-lyrics') == null,
      );
      expect(
        storageService.getSong('a-no-lyrics')!.lrcContent,
        '[00:01.00]匹配到的歌词',
      );
    });

    test('synced lyrics are preferred over plain text when merging', () async {
      await storageService.saveSongs([
        Song(
          id: 'a-plain',
          title: '纯文本',
          artist: '歌手',
          album: '专辑',
          durationMs: 180000,
          filePath: '/music/p1.mp3',
          dateAdded: DateTime(2026, 1, 1),
          lrcContent: '只是一段没有时间轴的纯文本歌词',
        ),
        Song(
          id: 'b-synced',
          title: '纯文本',
          artist: '歌手',
          album: '专辑',
          durationMs: 180000,
          filePath: '/music/p2.mp3',
          dateAdded: DateTime(2026, 1, 2),
          lrcContent: '[00:01.00]带时间轴的歌词',
        ),
      ]);

      final state = buildContainer().read(libraryNotifierProvider);
      expect(state.songs.single.lrcContent, '[00:01.00]带时间轴的歌词');
      await waitUntilStorageSettled(
        () => storageService.getSong('b-synced') == null,
      );
    });

    test('kept record keeps its synced lyrics when the duplicate has none better', () async {
      await storageService.saveSongs([
        Song(
          id: 'a-synced',
          title: '保留',
          artist: '歌手',
          album: '专辑',
          durationMs: 180000,
          filePath: '/music/s1.mp3',
          dateAdded: DateTime(2026, 1, 1),
          lrcContent: '[00:01.00]保留的同步歌词',
        ),
        Song(
          id: 'b-plain',
          title: '保留',
          artist: '歌手',
          album: '专辑',
          durationMs: 180000,
          filePath: '/music/s2.mp3',
          dateAdded: DateTime(2026, 1, 2),
          lrcContent: '纯文本歌词',
        ),
      ]);

      final state = buildContainer().read(libraryNotifierProvider);
      expect(state.songs.single.lrcContent, '[00:01.00]保留的同步歌词');
      await waitUntilStorageSettled(
        () => storageService.getSong('b-plain') == null,
      );
    });

    test('path duplicate upgrades placeholder identity fields', () async {
      await storageService.saveSongs([
        Song(
          id: 'a-untagged',
          title: '未知曲目',
          artist: '未知歌手',
          album: '未知专辑',
          durationMs: 180000,
          filePath: '/music/same.mp3',
          dateAdded: DateTime(2026, 1, 1),
        ),
        Song(
          id: 'b-tagged',
          title: '真实歌名',
          artist: '真实歌手',
          album: '真实专辑',
          durationMs: 180000,
          filePath: '/music/same.mp3',
          dateAdded: DateTime(2026, 1, 2),
          lrcContent: '[00:01.00]歌词',
        ),
      ]);

      final state = buildContainer().read(libraryNotifierProvider);
      expect(state.songs.length, 1);
      final merged = state.songs.single;
      expect(merged.id, 'a-untagged');
      expect(merged.title, '真实歌名');
      expect(merged.artist, '真实歌手');
      expect(merged.album, '真实专辑');
      expect(merged.lrcContent, '[00:01.00]歌词');
      await waitUntilStorageSettled(
        () => storageService.getSong('b-tagged') == null,
      );
    });

    test('distinct songs with same metadata but far durations are both kept',
        () async {
      await storageService.saveSongs([
        Song(
          id: 'live',
          title: '同一首歌',
          artist: '同一位歌手',
          album: '专辑',
          durationMs: 300000,
          filePath: '/music/live.mp3',
          dateAdded: DateTime(2026, 1, 1),
        ),
        Song(
          id: 'studio',
          title: '同一首歌',
          artist: '同一位歌手',
          album: '专辑',
          durationMs: 200000,
          filePath: '/music/studio.mp3',
          dateAdded: DateTime(2026, 1, 2),
        ),
      ]);

      final state = buildContainer().read(libraryNotifierProvider);
      expect(state.songs.length, 2);
    });
  });
}
