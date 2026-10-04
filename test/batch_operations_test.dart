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

  group('曲库批量操作与失效文件清理', () {
    late Directory tempDir;
    late StorageService storage;
    late ProviderContainer container;

    late File fileA;
    late File fileC;

    Song makeSong(String id, String title, String path) => Song(
      id: id,
      title: title,
      artist: 'Artist',
      album: 'Album',
      durationMs: 100000,
      filePath: path,
      dateAdded: DateTime(2026, 1, 2),
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('batch_ops_test_');
      storage = StorageService();
      await storage.init(tempDir.path);

      fileA = File('${tempDir.path}/a.mp3');
      await fileA.writeAsBytes(List.filled(16, 1));
      fileC = File('${tempDir.path}/c.mp3');
      await fileC.writeAsBytes(List.filled(16, 2));

      final a = Song(
        id: 's-a',
        title: 'A Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 100000,
        filePath: fileA.path,
        dateAdded: DateTime(2026, 1, 1),
      );
      final b = makeSong('s-b', 'B Song', '${tempDir.path}/missing.mp3');
      final c = Song(
        id: 's-c',
        title: 'C Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 100000,
        filePath: fileC.path,
        dateAdded: DateTime(2026, 1, 3),
      );
      await storage.saveSongs([a, b, c]);

      container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      // LibraryNotifier 构造时同步载入并去重。
      container.listen(libraryNotifierProvider, (_, _) {});
    });

    tearDown(() async {
      container.dispose();
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('setFavorites 批量收藏', () async {
      final notifier = container.read(libraryNotifierProvider.notifier);
      final count = await notifier.setFavorites(['s-a', 's-c'], true);

      expect(count, 2);
      final state = container.read(libraryNotifierProvider);
      expect(
        state.songs.where((s) => s.isFavorite).map((s) => s.id).toSet(),
        {'s-a', 's-c'},
      );
      // 持久化同样生效。
      expect(storage.getSong('s-a')!.isFavorite, isTrue);
    });

    test('deleteSongsByIds 批量移除并清理历史', () async {
      await storage.addToHistory('s-b');
      final notifier = container.read(libraryNotifierProvider.notifier);

      final count = await notifier.deleteSongsByIds(['s-b', 's-a']);

      expect(count, 2);
      final ids = container
          .read(libraryNotifierProvider)
          .songs
          .map((s) => s.id)
          .toSet();
      expect(ids, {'s-c'});
      expect(storage.getHistoryIds(), isNot(contains('s-b')));
    });

    test('findMissingFiles 识别磁盘上不存在的歌曲', () async {
      final notifier = container.read(libraryNotifierProvider.notifier);
      final missing = await notifier.findMissingFiles();

      expect(missing.map((s) => s.id), ['s-b']);
    });

    test('removeMissingFiles 移除全部失效歌曲', () async {
      final notifier = container.read(libraryNotifierProvider.notifier);
      final count = await notifier.removeMissingFiles();

      expect(count, 1);
      final ids = container
          .read(libraryNotifierProvider)
          .songs
          .map((s) => s.id)
          .toSet();
      expect(ids, containsAll(['s-a', 's-c']));
      expect(ids, isNot(contains('s-b')));
    });

    test('scanSidecarLyrics 用同名 .lrc 补齐缺失歌词', () async {
      await File('${tempDir.path}/a.lrc').writeAsString(
        '[00:01.00]第一行\n[00:02.00]第二行\n',
      );

      final notifier = container.read(libraryNotifierProvider.notifier);
      final filled = await notifier.scanSidecarLyrics();

      expect(filled, 1);
      final a = container
          .read(libraryNotifierProvider)
          .songs
          .firstWhere((s) => s.id == 's-a');
      expect(a.lrcContent, contains('第一行'));
      // 已有歌词的歌不被覆盖；无侧车文件的不受影响。
      final c = container
          .read(libraryNotifierProvider)
          .songs
          .firstWhere((s) => s.id == 's-c');
      expect(c.lrcContent, isNull);
    });
  });
}
