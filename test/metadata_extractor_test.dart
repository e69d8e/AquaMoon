import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/core/utils/metadata_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataExtractor Tests', () {
    test('extracts metadata from fallback filename properly', () async {
      final res = await MetadataExtractor.extractFromFile('/fake/path/Jay Chou - Nocturne.flac');
      expect(res.artist, equals('Jay Chou'));
      expect(res.title, equals('Nocturne'));
    });

    test('extracts metadata from simple filename without hyphen', () async {
      final res = await MetadataExtractor.extractFromFile('/fake/path/CanonInD.mp3');
      expect(res.title, equals('CanonInD'));
      expect(res.artist, equals('未知歌手'));
    });

    test('correctly parses FLAC mock stream data', () async {
      // Build a minimal FLAC structure in memory
      final flacBytes = <int>[
        0x66, 0x4C, 0x61, 0x43, // 'fLaC'
        // Block 1: VORBIS_COMMENT (type 4, isLast = 1)
        0x84, // bit 7 = 1 (isLast), bits 0-6 = 4 (VORBIS_COMMENT)
        0x00, 0x00, 0x36, // Length = 54 bytes
        // Vendor length: 4 bytes (little endian)
        0x04, 0x00, 0x00, 0x00,
        // Vendor string: "test"
        0x74, 0x65, 0x73, 0x74,
        // Comment count: 2 (little endian)
        0x02, 0x00, 0x00, 0x00,
        // Comment 1: "TITLE=FLAC Song" (len = 15)
        0x0F, 0x00, 0x00, 0x00,
        ...utf8.encode('TITLE=FLAC Song'),
        // Comment 2: "ARTIST=FLAC Artist" (len = 18)
        0x12, 0x00, 0x00, 0x00,
        ...utf8.encode('ARTIST=FLAC Artist'),
      ];

      final tempDir = await Directory.systemTemp.createTemp('flac_test');
      final tempFile = File('${tempDir.path}/test_audio.flac');
      await tempFile.writeAsBytes(flacBytes);

      final result = await MetadataExtractor.extractFromFile(tempFile.path);
      expect(result.title, equals('FLAC Song'));
      expect(result.artist, equals('FLAC Artist'));

      await tempDir.delete(recursive: true);
    });

    test('parses ID3v2 tag with embedded APIC artwork through the background isolate', () async {
      // Minimal ID3v2.3 tag: TIT2 + APIC frame with fake JPEG payload.
      const title = 'Isolate Song';
      final titleBytes = utf8.encode(title);
      final jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x01, 0xFF, 0xD9];

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

      final mime = utf8.encode('image/jpeg');
      final apicBody = <int>[0x00, ...mime, 0x00, 0x03, ...utf8.encode(''), 0x00, ...jpegBytes];
      final apicFrame = <int>[
        ...utf8.encode('APIC'),
        apicBody.length >> 24 & 0xFF,
        apicBody.length >> 16 & 0xFF,
        apicBody.length >> 8 & 0xFF,
        apicBody.length & 0xFF,
        0x00, 0x00, // flags
        ...apicBody,
      ];

      final tagSize = tit2Frame.length + apicFrame.length;
      final tag = <int>[
        ...utf8.encode('ID3'),
        0x03, 0x00, // version 2.3
        0x00, // flags
        (tagSize >> 21) & 0x7F,
        (tagSize >> 14) & 0x7F,
        (tagSize >> 7) & 0x7F,
        tagSize & 0x7F,
        ...tit2Frame,
        ...apicFrame,
      ];

      final tempDir = await Directory.systemTemp.createTemp('id3_test');
      final tempFile = File('${tempDir.path}/test_audio.mp3');
      await tempFile.writeAsBytes(tag);

      final result = await MetadataExtractor.extractFromFile(tempFile.path);
      expect(result.title, equals(title));
      // Cover cache is skipped when the platform temp dir is unavailable, but
      // the raw artwork bytes must still be returned.
      expect(result.albumArtBytes, isNotNull);
      expect(result.albumArtBytes, jpegBytes);

      await tempDir.delete(recursive: true);
    });
  });
}
