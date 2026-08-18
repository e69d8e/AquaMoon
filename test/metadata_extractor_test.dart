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
  });
}
