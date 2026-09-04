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
}
