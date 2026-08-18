import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/models/playlist.dart';
import 'package:aquamoon/services/online_metadata_service.dart';
import 'package:aquamoon/core/utils/metadata_extractor.dart';

void main() {
  group('OnlineMetadataService & MetadataExtractor Cleaner Tests', () {
    test('cleans song title stripping quality tags, extensions, and track numbers', () {
      expect(
        OnlineMetadataService.cleanSongTitle('01. 晴天 [320k].mp3'),
        equals('晴天'),
      );
      expect(
        OnlineMetadataService.cleanSongTitle('02 - 七里香 (FLAC) [Hi-Res].flac'),
        equals('七里香'),
      );
      expect(
        OnlineMetadataService.cleanSongTitle('Lemon 【无损官方版】(Official Audio).m4a'),
        equals('Lemon'),
      );
      expect(
        OnlineMetadataService.cleanSongTitle('夜曲_周杰伦[sq].wav'),
        equals('夜曲 周杰伦'),
      );
    });

    test('cleans artist names with prefix and quality watermarks', () {
      expect(
        OnlineMetadataService.cleanArtistName('kw_周杰伦 [320k]'),
        equals('周杰伦'),
      );
      expect(
        OnlineMetadataService.cleanArtistName('kuwo-林俊杰(FLAC)'),
        equals('林俊杰'),
      );
      expect(
        OnlineMetadataService.cleanArtistName('米津玄师'),
        equals('米津玄师'),
      );
    });

    test('cleanTrackName cleans track noise and quality badges', () {
      expect(
        MetadataExtractor.cleanTrackName('05. 稻香 [FLAC 24bit-96k]'),
        equals('稻香'),
      );
      expect(
        MetadataExtractor.cleanTrackName('kw_青花瓷【高音质】'),
        equals('青花瓷'),
      );
    });
  });

  group('Playlist Model & Equality Tests', () {
    test('creates and serializes Playlist correctly', () {
      final now = DateTime.now();
      final pl = Playlist(
        id: 'pl_123',
        name: '我的车载热歌',
        description: '好听的歌曲合集',
        songIds: ['s1', 's2', 's3'],
        createdAt: now,
        coverArtUri: 'file:///path/to/cover.jpg',
      );

      final map = pl.toMap();
      expect(map['id'], 'pl_123');
      expect(map['name'], '我的车载热歌');
      expect(map['songIds'], ['s1', 's2', 's3']);

      final restored = Playlist.fromMap(map);
      expect(restored.id, pl.id);
      expect(restored.name, pl.name);
      expect(restored.songIds, pl.songIds);
      expect(restored, equals(pl));
    });

    test('copyWith works for Playlist', () {
      final pl = Playlist(
        id: 'pl_1',
        name: '歌单A',
        songIds: ['s1'],
        createdAt: DateTime.now(),
      );

      final updated = pl.copyWith(
        name: '歌单B',
        songIds: ['s1', 's2'],
      );

      expect(updated.id, pl.id);
      expect(updated.name, '歌单B');
      expect(updated.songIds, ['s1', 's2']);
    });
  });

  group('Queue Reordering Math Simulation Tests', () {
    test('simulates reordering list items moving downwards and upwards', () {
      final list = ['Song A', 'Song B', 'Song C', 'Song D'];

      // Move Song A (index 0) to index 2
      final item = list.removeAt(0);
      list.insert(2, item);

      expect(list, ['Song B', 'Song C', 'Song A', 'Song D']);

      // Move Song D (index 3) to index 1
      final itemD = list.removeAt(3);
      list.insert(1, itemD);

      expect(list, ['Song B', 'Song D', 'Song C', 'Song A']);
    });
  });
}
