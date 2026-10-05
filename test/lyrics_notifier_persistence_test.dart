import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/lyrics_provider.dart';
import 'package:aquamoon/providers/library_provider.dart';
import 'package:aquamoon/services/online_metadata_service.dart';
import 'package:aquamoon/services/storage_service.dart';

/// Online service stub whose single fetch is controlled by a completer, so
/// tests can resolve a match *after* the user has switched songs.
class _FakeOnlineService implements OnlineMetadataService {
  _FakeOnlineService(this._completer);
  final Completer<OnlineSearchResult?> _completer;

  @override
  Future<OnlineSearchResult?> fetchMetadata({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) {
    return _completer.future;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Regression tests for: matched lyrics must reach the library record even
/// when the online response arrives after the user skipped to another song.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsNotifier online match persistence', () {
    late Directory tempDir;
    late StorageService storageService;
    late StreamController<Song?> currentSongController;
    late Completer<OnlineSearchResult?> fetchCompleter;

    final songA = Song(
      id: 'lyr-a',
      title: '歌A',
      artist: '歌手A',
      album: '专辑A',
      durationMs: 200000,
      filePath: '/music/a.mp3',
      dateAdded: DateTime(2026),
    );

    final songB = Song(
      id: 'lyr-b',
      title: '歌B',
      artist: '歌手B',
      album: '专辑B',
      durationMs: 210000,
      filePath: '/music/b.mp3',
      dateAdded: DateTime(2026),
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_lyrics_test_');
      storageService = StorageService();
      await storageService.init(tempDir.path);
      await storageService.saveSongs([songA, songB]);
      currentSongController = StreamController<Song?>();
      fetchCompleter = Completer<OnlineSearchResult?>();
    });

    tearDown(() async {
      await currentSongController.close();
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
          currentSongProvider.overrideWith(
            (ref) => currentSongController.stream,
          ),
          lyricsNotifierProvider.overrideWith(
            (ref) => LyricsNotifier(_FakeOnlineService(fetchCompleter), ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Pumps microtasks so stream events / pending futures settle.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test(
      'match completed after switching songs is still persisted to its song',
      () async {
        final container = buildContainer();
        container.read(lyricsNotifierProvider); // construct & start listening

        // Song A starts playing; lyrics matching kicks off and stalls on the
        // pending fetch.
        currentSongController.add(songA);
        await settle();
        expect(container.read(lyricsNotifierProvider).songId, 'lyr-a');

        // User skips to song B before the fetch resolves.
        currentSongController.add(songB);
        await settle();
        expect(container.read(lyricsNotifierProvider).songId, 'lyr-b');

        fetchCompleter.complete(
          const OnlineSearchResult(
            title: '歌A',
            artist: '歌手A',
            album: '专辑A',
            syncedLyrics: '[00:01.00]A的歌词',
          ),
        );
        await settle();

        // Song A's record must carry the fetched lyrics even though the UI
        // has moved on — otherwise the next playback re-runs the match.
        expect(storageService.getSong('lyr-a')!.lrcContent, '[00:01.00]A的歌词');
        expect(
          container
              .read(libraryNotifierProvider)
              .songs
              .firstWhere((s) => s.id == 'lyr-a')
              .lrcContent,
          '[00:01.00]A的歌词',
        );
        // The displayed state belongs to song B (which resolved from the same
        // stub in this test), not to song A.
        expect(container.read(lyricsNotifierProvider).songId, 'lyr-b');
        expect(container.read(lyricsNotifierProvider).isSynced, isTrue);
      },
    );

    test('match while song stays current persists and shows the lyrics', () async {
      final container = buildContainer();
      container.read(lyricsNotifierProvider);

      currentSongController.add(songA);
      await settle();

      fetchCompleter.complete(
        const OnlineSearchResult(
          title: '歌A',
          artist: '歌手A',
          album: '专辑A',
          syncedLyrics: '[00:01.00]A的歌词',
        ),
      );
      await settle();

      final state = container.read(lyricsNotifierProvider);
      expect(state.songId, 'lyr-a');
      expect(state.isSynced, isTrue);
      expect(state.lines, isNotEmpty);
      expect(storageService.getSong('lyr-a')!.lrcContent, '[00:01.00]A的歌词');
    });

    test('empty match result keeps the 暂无歌词 error without writing records',
        () async {
      final container = buildContainer();
      container.read(lyricsNotifierProvider);

      currentSongController.add(songA);
      await settle();

      fetchCompleter.complete(null);
      await settle();

      final state = container.read(lyricsNotifierProvider);
      expect(state.songId, 'lyr-a');
      expect(state.error, '暂无歌词');
      expect(state.isSynced, isFalse);
      expect(state.lines, isEmpty);
      expect(storageService.getSong('lyr-a')!.lrcContent, isNull);
    });

    test(
      'restart-restored song starts loading on notifier creation without playback',
      () async {
        // 重启恢复的当前歌曲先于歌词 notifier 存在：mini player 等早已把
        // currentSongProvider 订阅成 AsyncData(songA)，之后用户才打开
        // 歌词页并首次创建 notifier —— ref.listen 对这个已有值不回调。
        currentSongController.add(songA);
        final container = buildContainer();
        container.read(currentSongProvider);
        await settle();
        expect(container.read(currentSongProvider).valueOrNull?.id, 'lyr-a');

        container.read(lyricsNotifierProvider);
        await settle();

        // 未按播放也必须立即开始加载，而不是停在空状态等播放重发触发。
        final loading = container.read(lyricsNotifierProvider);
        expect(loading.songId, 'lyr-a');
        expect(loading.isLoading, isTrue);

        fetchCompleter.complete(
          const OnlineSearchResult(
            title: '歌A',
            artist: '歌手A',
            album: '专辑A',
            syncedLyrics: '[00:01.00]A的歌词',
          ),
        );
        await settle();

        final state = container.read(lyricsNotifierProvider);
        expect(state.songId, 'lyr-a');
        expect(state.isSynced, isTrue);
        expect(state.lines, isNotEmpty);
        expect(storageService.getSong('lyr-a')!.lrcContent, '[00:01.00]A的歌词');
      },
    );
  });
}
