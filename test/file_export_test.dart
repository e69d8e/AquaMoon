import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/services/file_export_service.dart';
import 'package:aquamoon/services/online_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileExportService Tests', () {
    test('sanitizeFileName removes illegal characters', () {
      expect(FileExportService.sanitizeFileName('Song / Title : Test * ? " < > |'),
          'Song _ Title _ Test _ _ _ _ _ _');
      expect(FileExportService.sanitizeFileName('Normal Song - Artist'),
          'Normal Song - Artist');
    });

    test('saveLyricFile generates valid lrc file', () async {
      final tempDir = Directory.systemTemp.createTempSync('aquamoon_test');
      final content = '[00:01.00]Hello world\n[00:05.00]AquaMoon Music';
      final res = await FileExportService.saveLyricFile(
        lyricContent: content,
        title: 'Test Song',
        artist: 'Test Artist',
      );

      expect(res.success, isTrue);
      expect(res.filePath, isNotNull);
      expect(File(res.filePath!).existsSync(), isTrue);

      final readContent = await File(res.filePath!).readAsString();
      expect(readContent, contains('AquaMoon Music'));

      // Cleanup
      try {
        File(res.filePath!).deleteSync();
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('copyToClipboard handles empty content safely', () async {
      final emptyRes = await FileExportService.copyToClipboard('');
      expect(emptyRes, isFalse);
    });
  });

  group('OnlineMetadataService Tests', () {
    test('cleanSongTitle removes audio format extensions and noise brackets', () {
      expect(OnlineMetadataService.cleanSongTitle('01. 晴天 [FLAC_96kHz_24bit].flac'), '晴天');
      expect(OnlineMetadataService.cleanSongTitle('周杰伦 - 稻香 (Official MV) [无损品质].mp3'), '周杰伦 - 稻香');
    });

    test('cleanArtistName removes tags', () {
      expect(OnlineMetadataService.cleanArtistName('周杰伦 [flac]'), '周杰伦');
      expect(OnlineMetadataService.cleanArtistName('kw 林俊杰'), '林俊杰');
    });
  });
}
