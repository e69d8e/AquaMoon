import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/services/online_metadata_service.dart';

void main() {
  group('OnlineMetadataService static helpers', () {
    group('neteaseCoverUrlFromPicId', () {
      test('derives the known CDN URL for a real picId', () {
        expect(
          OnlineMetadataService.neteaseCoverUrlFromPicId('109951170413587092'),
          'https://p3.music.126.net/-NVLOT5vt9I91LRiZV1TCQ==/109951170413587092.jpg',
        );
      });

      test('returns null for empty or missing picId', () {
        expect(OnlineMetadataService.neteaseCoverUrlFromPicId(null), isNull);
        expect(OnlineMetadataService.neteaseCoverUrlFromPicId(''), isNull);
      });
    });

    group('lrclibDurationToMs', () {
      test('converts LRCLIB seconds into milliseconds', () {
        expect(OnlineMetadataService.lrclibDurationToMs(270.0), 270000);
        expect(OnlineMetadataService.lrclibDurationToMs(270), 270000);
        expect(OnlineMetadataService.lrclibDurationToMs(269.5), 269500);
      });

      test('returns 0 for a missing duration', () {
        expect(OnlineMetadataService.lrclibDurationToMs(null), 0);
      });
    });
  });
}
