import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/models/qq_music_discovery.dart';
import 'package:aquamoon/models/song.dart';

void main() {
  group('QQMusicDiscovery models', () {
    test('stream quality parses persisted name with a safe default', () {
      expect(
        QQMusicStreamQuality.fromName('lossless'),
        QQMusicStreamQuality.lossless,
      );
      expect(
        QQMusicStreamQuality.fromName('bogus'),
        QQMusicStreamQuality.high,
      );
      expect(QQMusicStreamQuality.lossless.filenamePrefix, 'F000');
      expect(QQMusicStreamQuality.lossless.extension, 'flac');
      expect(QQMusicStreamQuality.lossless.requiresCookie, isTrue);
    });

    test('collection round-trips through plain maps', () {
      const collection = QQMusicCollection(
        id: '8899001122',
        kind: QQMusicCollectionKind.playlist,
        title: '水墨国风精选',
        subtitle: '水月音',
        coverUrl: 'https://y.gtimg.cn/music/photo_new/T002R800x800M000xx.jpg',
        songCount: 42,
        description: '测试歌单',
        badge: '官方',
      );

      final restored = QQMusicCollection.fromMap(collection.toMap());
      expect(restored.id, '8899001122');
      expect(restored.kind, QQMusicCollectionKind.playlist);
      expect(restored.title, '水墨国风精选');
      expect(restored.songCount, 42);
      expect(restored.badge, '官方');
      expect(restored.coverUrl, collection.coverUrl);
    });

    test('legacy map without kind/badge still loads', () {
      final restored = QQMusicCollection.fromMap({
        'id': '001',
        'title': '旧数据',
      });
      expect(restored.kind, QQMusicCollectionKind.playlist);
      expect(restored.subtitle, '');
      expect(restored.songCount, 0);
      expect(restored.badge, isNull);
    });

    test('collection detail round-trips online songs', () {
      final song = Song(
        id: 'qq_001abc',
        title: '青花瓷',
        artist: '周杰伦',
        album: '我很忙',
        durationMs: 239000,
        filePath: 'qqmusic://001abc',
        dateAdded: DateTime(2026, 5, 1),
        source: SongSource.online,
        qqSongMid: '001abc',
        qqSongId: 1001,
        qqMediaMid: '002media',
      );
      const collection = QQMusicCollection(
        id: '123',
        kind: QQMusicCollectionKind.album,
        title: '我很忙',
      );
      final detail = QQMusicCollectionDetail(
        collection: collection,
        songs: [song],
      );

      final restored = QQMusicCollectionDetail.fromMap(detail.toMap());
      expect(restored.collection.kind, QQMusicCollectionKind.album);
      expect(restored.songs, hasLength(1));
      expect(restored.songs.first.qqSongMid, '001abc');
      expect(restored.songs.first.isQQMusicOnline, isTrue);
    });

    test('empty / null maps produce empty detail instead of throwing', () {
      expect(QQMusicCollectionDetail.fromMap(null).songs, isEmpty);
      expect(QQMusicCollectionDetail.fromMap({}).songs, isEmpty);
      expect(QQMusicCollection.fromMap(null).id, '');
    });
  });
}
