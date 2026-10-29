import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/models/playlist.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('封面缓存迁移（临时目录 → 应用支持目录）', () {
    late Directory hiveDir;
    late Directory fakeTempDir;
    late Directory fakeSupportDir;
    late StorageService storage;

    Song song(String id, {String? artUri}) => Song(
          id: id,
          title: 'T-$id',
          artist: 'A',
          album: 'Al',
          durationMs: 60000,
          filePath: '/music/$id.mp3',
          albumArtUri: artUri,
          dateAdded: DateTime(2026, 1, 1),
        );

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('hive_cover_migration_');
      fakeTempDir = await Directory.systemTemp.createTemp('fake_temp_covers_');
      fakeSupportDir =
          await Directory.systemTemp.createTemp('fake_support_covers_');
      storage = StorageService();
      await storage.init(hiveDir.path);
    });

    tearDown(() async {
      await Hive.close();
      for (final dir in [hiveDir, fakeTempDir, fakeSupportDir]) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('临时目录里仍存在的封面被搬到支持目录并改写记录', () async {
      final coversDir =
          Directory('${fakeTempDir.path}${Platform.pathSeparator}covers');
      await coversDir.create(recursive: true);
      final coverFile =
          File('${coversDir.path}${Platform.pathSeparator}cover_abc.jpg');
      await coverFile.writeAsBytes([1, 2, 3, 4]);

      await storage.saveSong(song('s1', artUri: coverFile.uri.toString()));
      await storage.saveSong(song('s2')); // 无封面，不应受影响

      final changed = await storage.migrateTempCoverCaches(
        tempDir: fakeTempDir,
        supportDir: fakeSupportDir,
      );

      expect(changed, 1);
      final migrated = storage.getSong('s1')!;
      expect(migrated.albumArtUri, isNotNull);
      expect(migrated.albumArtUri!.startsWith('file://'), isTrue);
      final migratedPath = Uri.parse(migrated.albumArtUri!).toFilePath();
      expect(migratedPath.startsWith(fakeSupportDir.path), isTrue);
      expect(migratedPath.endsWith('cover_abc.jpg'), isTrue);
      // 文件内容随迁移复制到位。
      final copied = File(migratedPath);
      expect(await copied.exists(), isTrue);
      expect(await copied.readAsBytes(), [1, 2, 3, 4]);
      // 原标题等其他字段不丢。
      expect(migrated.title, 'T-s1');
      expect(storage.getSong('s2')!.albumArtUri, isNull);
    });

    test('临时目录里已丢失的封面：记录被清空而不是保留失效 URI', () async {
      final goneUri = File(
        '${fakeTempDir.path}${Platform.pathSeparator}covers'
        '${Platform.pathSeparator}cover_gone.jpg',
      ).uri.toString();
      await storage.saveSong(song('s1', artUri: goneUri));

      final changed = await storage.migrateTempCoverCaches(
        tempDir: fakeTempDir,
        supportDir: fakeSupportDir,
      );

      expect(changed, 1);
      expect(storage.getSong('s1')!.albumArtUri, isNull);
    });

    test('指向临时目录之外（在线 https）的封面不受影响', () async {
      await storage.saveSong(
        song('s1', artUri: 'https://example.com/cover.jpg'),
      );

      final changed = await storage.migrateTempCoverCaches(
        tempDir: fakeTempDir,
        supportDir: fakeSupportDir,
      );

      expect(changed, 0);
      expect(
        storage.getSong('s1')!.albumArtUri,
        'https://example.com/cover.jpg',
      );
    });

    test('歌单封面同样迁移 / 清空', () async {
      final coverFile = File(
        '${fakeTempDir.path}${Platform.pathSeparator}online_covers'
        '${Platform.pathSeparator}cover_pl.jpg',
      );
      await coverFile.parent.create(recursive: true);
      await coverFile.writeAsBytes([9, 9]);

      await storage.savePlaylist(Playlist(
        id: 'p1',
        name: 'PL1',
        songIds: const [],
        createdAt: DateTime(2026, 1, 1),
        coverArtUri: coverFile.uri.toString(),
      ));
      await storage.savePlaylist(Playlist(
        id: 'p2',
        name: 'PL2',
        songIds: const [],
        createdAt: DateTime(2026, 1, 1),
        coverArtUri: File(
          '${fakeTempDir.path}${Platform.pathSeparator}covers'
          '${Platform.pathSeparator}missing.jpg',
        ).uri.toString(),
      ));

      final changed = await storage.migrateTempCoverCaches(
        tempDir: fakeTempDir,
        supportDir: fakeSupportDir,
      );

      expect(changed, 2);
      final p1 = storage.getAllPlaylists().firstWhere((p) => p.id == 'p1');
      expect(
        Uri.parse(p1.coverArtUri!).toFilePath().startsWith(fakeSupportDir.path),
        isTrue,
      );
      final p2 = storage.getAllPlaylists().firstWhere((p) => p.id == 'p2');
      expect(p2.coverArtUri, isNull);
    });

    test('重复执行无新增变更（幂等）', () async {
      final coverFile = File(
        '${fakeTempDir.path}${Platform.pathSeparator}covers'
        '${Platform.pathSeparator}cover_x.jpg',
      );
      await coverFile.parent.create(recursive: true);
      await coverFile.writeAsBytes([7]);
      await storage.saveSong(song('s1', artUri: coverFile.uri.toString()));

      final first = await storage.migrateTempCoverCaches(
        tempDir: fakeTempDir,
        supportDir: fakeSupportDir,
      );
      final second = await storage.migrateTempCoverCaches(
        tempDir: fakeTempDir,
        supportDir: fakeSupportDir,
      );

      expect(first, 1);
      expect(second, 0);
    });

    test('Song.copyWith clearAlbumArtUri 只清封面，其余字段保留', () {
      final s = song('s1', artUri: 'file:///tmp/a.jpg');
      final cleared = s.copyWith(clearAlbumArtUri: true);
      expect(cleared.albumArtUri, isNull);
      expect(cleared.title, 'T-s1');
      expect(cleared.lrcContent, s.lrcContent);

      // 普通赋值路径不受影响。
      final replaced = s.copyWith(albumArtUri: 'file:///new/b.jpg');
      expect(replaced.albumArtUri, 'file:///new/b.jpg');
    });

    test('Playlist.copyWith clearCoverArtUri 只清封面', () {
      final pl = Playlist(
        id: 'p1',
        name: 'PL',
        songIds: const ['a', 'b'],
        createdAt: DateTime(2026, 1, 1),
        coverArtUri: 'file:///tmp/c.jpg',
      );
      final cleared = pl.copyWith(clearCoverArtUri: true);
      expect(cleared.coverArtUri, isNull);
      expect(cleared.songIds, ['a', 'b']);
      expect(cleared.name, 'PL');
    });
  });
}
