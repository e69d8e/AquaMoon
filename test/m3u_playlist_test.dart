import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/services/file_export_service.dart';

Song _song(String id, String title, String artist, String path) => Song(
  id: id,
  title: title,
  artist: artist,
  album: '专辑',
  durationMs: 180000,
  filePath: path,
  dateAdded: DateTime(2026, 1, 1),
);

void main() {
  final library = [
    _song('s1', '青花瓷', '周杰伦', '/music/青花瓷.flac'),
    _song('s2', '稻香', '周杰伦', '/music/sub/daoxiang.mp3'),
    _song('s3', '杭州幻听', '未闻花名', '/music/hangzhou.mp3'),
  ];

  group('M3uPlaylistParser.parse', () {
    test('按文件绝对路径精确匹配', () {
      final content = '#EXTM3U\n'
          '#EXTINF:180,周杰伦 - 青花瓷\n'
          '/music/青花瓷.flac\n'
          '#EXTINF:200,周杰伦 - 稻香\n'
          '/music/sub/daoxiang.mp3\n';

      final result = M3uPlaylistParser.parse(content, library);

      expect(result.matchedSongIds, ['s1', 's2']);
      expect(result.unmatchedEntries, 0);
    });

    test('路径不同但文件名相同 → 文件名匹配兜底', () {
      final content = '#EXTM3U\n'
          '#EXTINF:180,周杰伦 - 青花瓷\n'
          '/other/device/Music/青花瓷.flac\n';

      final result = M3uPlaylistParser.parse(content, library);
      expect(result.matchedSongIds, ['s1']);
      expect(result.unmatchedEntries, 0);
    });

    test('路径失效但 EXTINF 元数据可用 → 标题+歌手匹配', () {
      final content = '#EXTM3U\n'
          '#EXTINF:180,周杰伦 - 稻香\n'
          '/lost/path/somewhere.mp3\n'
          '#EXTINF:-1,未闻花名 - 杭州幻听\n'
          '/another/lost.mp3\n';

      final result = M3uPlaylistParser.parse(content, library);
      expect(result.matchedSongIds, ['s2', 's3']);
      expect(result.unmatchedEntries, 0);
    });

    test('EXTINF 仅标题（无歌手）也能匹配', () {
      final content = '#EXTM3U\n'
          '#EXTINF:180,稻香\n'
          '/unknown/file.mp3\n';

      final result = M3uPlaylistParser.parse(content, library);
      expect(result.matchedSongIds, ['s2']);
    });

    test('无法匹配的条目计入 unmatchedEntries', () {
      final content = '#EXTM3U\n'
          '#EXTINF:180,不存在 - 假歌\n'
          '/nope/missing.mp3\n'
          '#EXTINF:180,周杰伦 - 青花瓷\n'
          '/music/青花瓷.flac\n';

      final result = M3uPlaylistParser.parse(content, library);
      expect(result.matchedSongIds, ['s1']);
      expect(result.unmatchedEntries, 1);
    });

    test('匹配结果按文件内顺序去重', () {
      final content = '#EXTM3U\n'
          '/music/青花瓷.flac\n'
          '/dup/青花瓷.flac\n'
          '/music/sub/daoxiang.mp3\n';

      final result = M3uPlaylistParser.parse(content, library);
      expect(result.matchedSongIds, ['s1', 's2']);
    });

    test('忽略注释与 #PLAYLIST 头', () {
      final content = '#EXTM3U\n#PLAYLIST:我的最爱\n'
          '#EXTINF:180,周杰伦 - 青花瓷\n'
          '/music/青花瓷.flac\n';
      final result = M3uPlaylistParser.parse(content, library);
      expect(result.matchedSongIds, ['s1']);
      expect(result.unmatchedEntries, 0);
    });
  });

  group('M3U 导出格式', () {
    test('导出的内容可以被解析器读回', () async {
      final songs = [library[0], library[2]];
      // 直接构造与 FileExportService.exportPlaylistM3u 相同的格式，
      // 平台目录解析在单元测试环境不可用，故复刻其序列化逻辑验证互逆性。
      final buffer = StringBuffer('#EXTM3U\n#PLAYLIST:禅意歌单\n');
      for (final song in songs) {
        final seconds = (song.durationMs / 1000).round();
        buffer.writeln('#EXTINF:$seconds,${song.artist} - ${song.title}');
        buffer.writeln(song.filePath);
      }
      final exported = buffer.toString();
      expect(exported.startsWith('#EXTM3U'), isTrue);
      expect(utf8.encode(exported), isNotEmpty);

      final result = M3uPlaylistParser.parse(exported, library);
      expect(result.matchedSongIds, ['s1', 's3']);
      expect(result.unmatchedEntries, 0);
    });
  });
}
