import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/models/playlist.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('播放会话持久化（队列跨重启）', () {
    late Directory tempDir;
    late StorageService storage;

    final songA = Song(
      id: 'q-a',
      title: 'A',
      artist: 'X',
      album: 'Al',
      durationMs: 100000,
      filePath: '/m/a.mp3',
      dateAdded: DateTime(2026, 1, 1),
    );
    final songB = Song(
      id: 'q-b',
      title: 'B',
      artist: 'X',
      album: 'Al',
      durationMs: 90000,
      filePath: '/m/b.mp3',
      dateAdded: DateTime(2026, 1, 2),
      lrcContent: '[00:01.00]lyric',
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_session_test_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('保存后可恢复队列与索引，歌曲字段完整', () async {
      await storage.savePlaybackSession([songA, songB], 1);

      final session = storage.getPlaybackSession();
      expect(session, isNotNull);
      expect(session!.songMaps, hasLength(2));
      expect(session.index, 1);

      final restored = Song.fromMap(session.songMaps[1]);
      expect(restored.id, 'q-b');
      expect(restored.title, 'B');
      expect(restored.lrcContent, '[00:01.00]lyric');
    });

    test('索引越界时钳制', () async {
      await storage.savePlaybackSession([songA], 7);
      expect(storage.getPlaybackSession()!.index, 0);
    });

    test('清空后返回 null（不再恢复旧会话）', () async {
      await storage.savePlaybackSession([songA, songB], 0);
      expect(storage.getPlaybackSession(), isNotNull);
      await storage.savePlaybackSession(const [], -1);
      expect(storage.getPlaybackSession(), isNull);
    });
  });

  group('历史与批量删除', () {
    late Directory tempDir;
    late StorageService storage;

    final songs = [
      for (var i = 0; i < 3; i++)
        Song(
          id: 'h-$i',
          title: 'T$i',
          artist: 'A',
          album: 'Al',
          durationMs: 1000,
          filePath: '/m/$i.mp3',
          dateAdded: DateTime(2026, 1, 1 + i),
        ),
    ];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_history_test_');
      storage = StorageService();
      await storage.init(tempDir.path);
      await storage.saveSongs(songs);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('clearHistory 清空最近播放', () async {
      await storage.addToHistory('h-0');
      await storage.addToHistory('h-1');
      expect(storage.getHistoryIds(), isNotEmpty);

      await storage.clearHistory();
      expect(storage.getHistoryIds(), isEmpty);
    });

    test('deleteSongs 同步清理历史中的失效引用', () async {
      await storage.addToHistory('h-0');
      await storage.addToHistory('h-1');

      await storage.deleteSongs(['h-0']);

      expect(storage.getHistoryIds(), ['h-1']);
      expect(storage.getSong('h-0'), isNull);
    });
  });

  group('音效设置持久化', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_fx_test_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('淡入淡出与均衡器开关默认关闭且可写回', () async {
      expect(storage.getFadeEnabled(), isFalse);
      expect(storage.getEqualizerEnabled(), isFalse);

      await storage.saveFadeEnabled(true);
      await storage.saveEqualizerEnabled(true);
      expect(storage.getFadeEnabled(), isTrue);
      expect(storage.getEqualizerEnabled(), isTrue);
    });

    test('均衡器增益列表可写回', () async {
      expect(storage.getEqualizerGains(), isEmpty);
      await storage.saveEqualizerGains([1.5, -2.0, 0.0, 3.0, 4.0]);
      expect(storage.getEqualizerGains(), [1.5, -2.0, 0.0, 3.0, 4.0]);
    });
  });

  group('数据备份与恢复', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_backup_test_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('导出 → 破坏 → 恢复 往返一致', () async {
      final song = Song(
        id: 'bk-1',
        title: '备份曲',
        artist: '歌手',
        album: '专辑',
        durationMs: 123000,
        filePath: '/m/bk.mp3',
        dateAdded: DateTime(2026, 2, 3),
        isFavorite: true,
        playCount: 7,
      );
      // 先写历史再入曲库：addToHistory 只对已存在的歌曲累加播放次数。
      await storage.addToHistory('bk-1');
      await storage.saveSongs([song]);
      await storage.savePlaylist(
        Playlist(
          id: 'pl-1',
          name: '禅音',
          songIds: ['bk-1'],
          createdAt: DateTime(2026, 2, 3),
        ),
      );
      await storage.saveFadeEnabled(true);

      final backup = storage.exportBackup();
      final encoded = jsonEncode(backup);

      // 破坏现场。
      await storage.deleteSong('bk-1');
      await storage.deletePlaylist('pl-1');
      await storage.clearHistory();
      await storage.saveFadeEnabled(false);
      expect(storage.getAllSongs(), isEmpty);

      // 恢复。
      await storage.restoreBackup(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );

      final restored = storage.getSong('bk-1');
      expect(restored, isNotNull);
      expect(restored!.title, '备份曲');
      expect(restored.isFavorite, isTrue);
      expect(restored.playCount, 7);

      final playlists = storage.getAllPlaylists();
      expect(playlists, hasLength(1));
      expect(playlists.first.name, '禅音');
      expect(playlists.first.songIds, ['bk-1']);

      expect(storage.getHistoryIds(), ['bk-1']);
      expect(storage.getFadeEnabled(), isTrue);
    });

    test('非水月音备份抛 FormatException', () async {
      expect(
        () => storage.restoreBackup({'format': 'other'}),
        throwsFormatException,
      );
    });
  });
}
