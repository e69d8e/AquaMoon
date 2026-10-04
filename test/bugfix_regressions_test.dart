import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/core/utils/lrc_parser.dart';
import 'package:aquamoon/core/utils/metadata_extractor.dart';
import 'package:aquamoon/models/playlist.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/services/storage_service.dart';

Uint8List _le32(int value) {
  final b = ByteData(4)..setUint32(0, value, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _vorbisComment(String entry) =>
    [..._le32(utf8.encode(entry).length), ...utf8.encode(entry)];

/// 一段假的 OggS 页流：页头 junk + 注释头包（\x03vorbis / OpusTags）。
List<int> _oggStream({required bool opus, required List<String> comments}) {
  final marker = opus ? utf8.encode('OpusTags') : <int>[0x03, ...utf8.encode('vorbis')];
  return [
    ...utf8.encode('OggS'),
    ...List.filled(22, 0x00), // page header 剩余字段（解析器只当 junk）
    0x01,
    ...marker,
    ..._le32(4),
    ...utf8.encode('test'),
    ..._le32(comments.length),
    for (final c in comments) ..._vorbisComment(c),
    ...List.filled(16, 0x55), // 音频页 junk
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LrcParser 回归：offset 标签与超长时长', () {
    test('应用 [offset:+500] 到全部时间戳（正值整体后移）', () {
      const lrc = '''
[offset:+500]
[00:02.00]Line one
[00:04.00]Line two
''';
      final lines = LrcParser.parse(lrc);
      expect(lines, hasLength(2));
      expect(
        lines[0].time,
        const Duration(seconds: 2, milliseconds: 500),
      );
      expect(
        lines[1].time,
        const Duration(seconds: 4, milliseconds: 500),
      );
    });

    test('负 offset 前移并在 0 处钳制', () {
      const lrc = '''
[offset:-3000]
[00:01.00]Early line
[00:05.00]Later line
''';
      final lines = LrcParser.parse(lrc);
      expect(lines, hasLength(2));
      expect(lines[0].text, 'Early line');
      expect(lines[0].time, Duration.zero);
      expect(lines[1].time, const Duration(seconds: 2));
    });

    test('大写 [OFFSET:...] 同样生效', () {
      const lrc = '[OFFSET:1000]\n[00:03.00]Line';
      final lines = LrcParser.parse(lrc);
      expect(lines.single.time, const Duration(seconds: 4));
    });

    test('解析 ≥100 分钟的时间戳（长混音/有声书）', () {
      const lrc = '[100:30.50]Long mix';
      final lines = LrcParser.parse(lrc);
      expect(lines, hasLength(1));
      expect(
        lines.single.time,
        const Duration(hours: 1, minutes: 40, seconds: 30, milliseconds: 500),
      );
    });
  });

  group('MetadataExtractor 回归', () {
    test('OGG：从 OggS 页流中定位 \\x03vorbis 注释头并解析', () async {
      final tempDir = await Directory.systemTemp.createTemp('ogg_test');
      final tempFile = File('${tempDir.path}/song.ogg');
      await tempFile.writeAsBytes(
        _oggStream(opus: false, comments: ['TITLE=OGG Song', 'ARTIST=OGG Artist']),
      );

      final result = await MetadataExtractor.extractFromFile(tempFile.path);
      expect(result.title, 'OGG Song');
      expect(result.artist, 'OGG Artist');

      await tempDir.delete(recursive: true);
    });

    test('Opus：从 OpusTags 注释头解析', () async {
      final tempDir = await Directory.systemTemp.createTemp('opus_test');
      final tempFile = File('${tempDir.path}/song.opus');
      await tempFile.writeAsBytes(
        _oggStream(opus: true, comments: ['TITLE=Opus Song']),
      );

      final result = await MetadataExtractor.extractFromFile(tempFile.path);
      expect(result.title, 'Opus Song');

      await tempDir.delete(recursive: true);
    });

    test('内嵌标题以数字开头时不被当作曲目号剥掉（"7 Years"）', () async {
      const title = '7 Years';
      final titleBytes = utf8.encode(title);

      final tit2Frame = <int>[
        ...utf8.encode('TIT2'),
        (titleBytes.length + 1) >> 24 & 0xFF,
        (titleBytes.length + 1) >> 16 & 0xFF,
        (titleBytes.length + 1) >> 8 & 0xFF,
        (titleBytes.length + 1) & 0xFF,
        0x00, 0x00, // flags
        0x00, // encoding: ISO-8859-1
        ...titleBytes,
      ];
      final tagBody = <int>[...tit2Frame, 0x00]; // padding
      final id3 = <int>[
        ...utf8.encode('ID3'),
        0x03, 0x00, // v2.3
        0x00, // flags
        (tagBody.length >> 24) & 0x7F,
        (tagBody.length >> 16) & 0x7F,
        (tagBody.length >> 8) & 0x7F,
        tagBody.length & 0x7F,
        ...tagBody,
      ];

      final tempDir = await Directory.systemTemp.createTemp('id3_title_test');
      final tempFile = File('${tempDir.path}/song.mp3');
      await tempFile.writeAsBytes(id3);

      final result = await MetadataExtractor.extractFromFile(tempFile.path);
      expect(result.title, '7 Years');

      await tempDir.delete(recursive: true);
    });

    test('cleanTrackName 仍保留文件名回退的曲目号剥离行为', () {
      expect(MetadataExtractor.cleanTrackName('05. 稻香'), '稻香');
      expect(MetadataExtractor.cleanTrackName('01 - Sunrise'), 'Sunrise');
    });
  });

  group('Song.copyWith 显式清空回归', () {
    test('clearLrcContent / clearYear 真正清空字段', () {
      final song = Song(
        id: 's1',
        title: 'T',
        artist: 'A',
        album: 'Al',
        durationMs: 1000,
        filePath: '/m/s.mp3',
        dateAdded: DateTime(2026, 1, 1),
        lrcContent: '[00:01.00]x',
        year: 2001,
      );

      expect(song.copyWith(clearLrcContent: true).lrcContent, isNull);
      expect(song.copyWith(clearYear: true).year, isNull);
      // 未指定时保持旧值（既有语义不受影响）。
      expect(song.copyWith().lrcContent, '[00:01.00]x');
      expect(song.copyWith().year, 2001);
      expect(song.copyWith(lrcContent: 'new').lrcContent, 'new');
      expect(song.copyWith(year: 2020).year, 2020);
    });
  });

  group('StorageService 回归：备份恢复校验与失效 id 清理', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_bugfix_test_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('恢复备份时丢弃损坏条目，错误类型的设置值退回默认', () async {
      final goodSong = Song(
        id: 'good',
        title: 'Good',
        artist: 'A',
        album: 'Al',
        durationMs: 1000,
        filePath: '/m/good.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      await storage.restoreBackup({
        'format': 'aquamoon-backup',
        'songs': {
          'good': goodSong.toMap(),
          'junk': 'not-a-map',
          'bad': {'id': 1, 'title': 42},
        },
        'history': {'recent_song_ids': ['good', 42, null]},
        'settings': {'fade_enabled': 'yes', 'volume': 'loud'},
        'stats': {'daily:2026-01-01': 'garbage'},
      });

      expect(storage.getAllSongs().map((s) => s.id), ['good']);
      expect(storage.getHistoryIds(), ['good', '42']);
      // 启动时构造 handler 就会读这些值：类型错误必须退默认而不是抛 TypeError。
      expect(storage.getFadeEnabled(), isFalse);
      expect(storage.getSavedVolume(), 1.0);
      expect(storage.getPlaybackSession(), isNull);
    });

    test('deleteSongs 同步清理歌单中失效的 songIds', () async {
      final song = Song(
        id: 'gone',
        title: 'G',
        artist: 'A',
        album: 'Al',
        durationMs: 1000,
        filePath: '/m/g.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );
      await storage.saveSong(song);
      await storage.savePlaylist(
        Playlist(
          id: 'p1',
          name: 'P',
          songIds: ['gone', 'keep', 'gone'],
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await storage.deleteSongs(['gone']);

      final playlist = storage.getAllPlaylists().single;
      expect(playlist.songIds, ['keep']);
    });

    test('deleteSong 同步清理歌单引用', () async {
      await storage.savePlaylist(
        Playlist(
          id: 'p1',
          name: 'P',
          songIds: ['a', 'b'],
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await storage.deleteSong('a');

      expect(storage.getAllPlaylists().single.songIds, ['b']);
    });
  });
}
