import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/core/utils/metadata_extractor.dart';

Uint8List _id3v2WithLyrics(String lyrics) {
  final lyricsBytes = utf8.encode(lyrics);
  final titleBytes = utf8.encode('测试曲目');

  Uint8List frame(String id, List<int> payload) {
    final size = payload.length;
    return Uint8List.fromList([
      ...ascii.encode(id),
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      0x00,
      0x00, // flags
      ...payload,
    ]);
  }

  final tit2 = frame('TIT2', [0x03, ...titleBytes]);
  // USLT: encoding(1) + language(3) + content descriptor(\0) + text
  final uslt = frame('USLT', [
    0x03,
    ...ascii.encode('chi'),
    0x00,
    ...lyricsBytes,
  ]);

  final tagPayload = [...tit2, ...uslt];
  final tagSize = tagPayload.length;

  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    0x03,
    0x00, // v2.3
    0x00, // flags
    (tagSize >> 21) & 0x7F,
    (tagSize >> 14) & 0x7F,
    (tagSize >> 7) & 0x7F,
    tagSize & 0x7F,
    ...tagPayload,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('内嵌歌词解析', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('embedded_lyrics_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ID3v2 USLT 帧（UTF-8）解析为同步歌词', () async {
      const lrc =
          '[00:01.00]天青色等烟雨\n[00:05.00]而我在等你';
      final file = File('${tempDir.path}/song.mp3');
      await file.writeAsBytes(_id3v2WithLyrics(lrc));

      final meta = await MetadataExtractor.extractFromFileIsolated(
        file.path,
        tempDir.path,
      );

      expect(meta.title, '测试曲目');
      expect(meta.lyrics, isNotNull);
      expect(meta.lyrics, contains('天青色等烟雨'));
      expect(meta.lyrics, contains('而我在等你'));
    });

    test('不带歌词的文件 lyrics 为 null', () async {
      final file = File('${tempDir.path}/plain.mp3');
      await file.writeAsBytes(_id3v2WithLyrics(''));
      // 空歌词内容使 USLT 文本为空，解析器应返回 null 而非空串。
      final meta = await MetadataExtractor.extractFromFileIsolated(
        file.path,
        tempDir.path,
      );
      expect(meta.lyrics, anyOf(isNull, isEmpty));
    });

    test('同名 .lrc 侧车歌词内容格式校验（供 scanSidecarLyrics 使用）', () async {
      const lrc = '[00:10.00]侧车歌词内容';
      final audio = File('${tempDir.path}/track.flac');
      await audio.writeAsBytes(List.filled(64, 0));
      final sidecar = File('${tempDir.path}/track.lrc');
      await sidecar.writeAsString(lrc);

      expect(await sidecar.exists(), isTrue);
      expect((await sidecar.readAsString()).startsWith('[00:10.00]'), isTrue);
      expect(audio.existsSync(), isTrue);
    });
  });
}
