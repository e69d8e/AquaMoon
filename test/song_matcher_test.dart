import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/core/utils/song_matcher.dart';
import 'package:aquamoon/models/song.dart';

Song online({
  required String title,
  required String artist,
  int durationMs = 0,
  String mid = 'mid',
}) =>
    Song(
      id: 'qq_$mid',
      title: title,
      artist: artist,
      album: '',
      durationMs: durationMs,
      filePath: 'qqmusic://$mid',
      dateAdded: DateTime(2026, 1, 1),
      source: SongSource.online,
      qqSongMid: mid,
    );

Song local({
  required String id,
  required String title,
  required String artist,
  int durationMs = 0,
}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      album: '',
      durationMs: durationMs,
      filePath: '/music/$id.flac',
      dateAdded: DateTime(2026, 1, 1),
      source: SongSource.local,
    );

void main() {
  group('SongMatcher normalization', () {
    test('folds full-width punctuation and case', () {
      expect(SongMatcher.compact('稻香（Live）'), SongMatcher.compact('稻香(live)'));
      expect(SongMatcher.compact('A－B'), SongMatcher.compact('A-B'));
      expect(SongMatcher.compact('  Hello   World '), 'helloworld');
    });

    test('strips version suffixes from the base title', () {
      expect(SongMatcher.baseTitle('稻香 (Live)'), '稻香');
      expect(SongMatcher.baseTitle('稻香 - Remastered 2019'), '稻香');
      expect(SongMatcher.baseTitle('稻香 [伴奏]'), '稻香');
      expect(SongMatcher.baseTitle('稻香（钢琴版）'), '稻香');
    });

    test('splits artists on the separators each source uses', () {
      expect(SongMatcher.artistTokens('周杰伦/费玉清'), {'周杰伦', '费玉清'});
      expect(SongMatcher.artistTokens('周杰伦、费玉清'), {'周杰伦', '费玉清'});
      expect(SongMatcher.artistTokens('周杰伦 & 费玉清'), {'周杰伦', '费玉清'});
      expect(SongMatcher.artistTokens('周杰伦, 费玉清'), {'周杰伦', '费玉清'});
      expect(SongMatcher.artistTokens('A feat. B'), {'a', 'b'});
    });

    test('treats placeholder artists as unknown', () {
      expect(SongMatcher.artistTokens('未知歌手'), isEmpty);
      expect(SongMatcher.artistTokens('Various Artists'), isEmpty);
      expect(SongMatcher.artistTokens(''), isEmpty);
    });

    test('rejects placeholder titles', () {
      expect(SongMatcher.titleKey('未知曲目'), isNull);
      expect(SongMatcher.titleKey('本地歌曲'), isNull);
      expect(SongMatcher.titleKey(''), isNull);
    });
  });

  group('SongMatcher matching', () {
    test('matches despite different artist separators', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '千里之外', artist: '周杰伦/费玉清', mid: 'a1'),
        [local(id: 'l1', title: '千里之外', artist: '周杰伦、费玉清')],
      );
      expect(match?.id, 'l1');
    });

    test('matches when QQ title carries a version suffix', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '稻香 (Live)', artist: '周杰伦', mid: 'a2'),
        [local(id: 'l2', title: '稻香', artist: '周杰伦')],
      );
      expect(match?.id, 'l2');
    });

    test('matches when the local tag carries the suffix instead', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '稻香', artist: '周杰伦', mid: 'a3'),
        [local(id: 'l3', title: '稻香 (2008 Remastered)', artist: '周杰伦')],
      );
      expect(match?.id, 'l3');
    });

    test('matches when the local artist tag is missing', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '夜曲', artist: '周杰伦', mid: 'a4'),
        [local(id: 'l4', title: '夜曲', artist: '未知歌手')],
      );
      expect(match?.id, 'l4');
    });

    test('matches full-width vs half-width and stray spacing', () {
      final match = SongMatcher.findLocalMatch(
        online(title: 'A － B', artist: '周杰伦', mid: 'a5'),
        [local(id: 'l5', title: 'a-b', artist: '  周杰伦  ')],
      );
      expect(match?.id, 'l5');
    });

    test('does NOT match a different song by the same artist', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '爱', artist: '周杰伦', mid: 'a6'),
        [local(id: 'l6', title: '爱情', artist: '周杰伦')],
      );
      expect(match, isNull);
    });

    test('does NOT match the same title by a different artist', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '稻香', artist: '周杰伦', mid: 'a7'),
        [local(id: 'l7', title: '稻香', artist: '林俊杰')],
      );
      expect(match, isNull);
    });

    test('prefers the version whose duration is closest', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '稻香', artist: '周杰伦', durationMs: 226000, mid: 'a8'),
        [
          local(id: 'live', title: '稻香', artist: '周杰伦', durationMs: 400000),
          local(id: 'studio', title: '稻香', artist: '周杰伦', durationMs: 227000),
        ],
      );
      expect(match?.id, 'studio');
    });

    test('prefers a candidate that actually has a local file', () {
      final match = SongMatcher.findLocalMatch(
        online(title: '稻香', artist: '周杰伦', mid: 'a9'),
        [
          Song(
            id: 'placeholder',
            title: '稻香',
            artist: '周杰伦',
            album: '',
            durationMs: 0,
            filePath: 'qqmusic://other',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.online,
          ),
          local(id: 'realfile', title: '稻香', artist: '周杰伦'),
        ],
      );
      expect(match?.id, 'realfile');
    });

    test('honours excludeIds so one file is not claimed twice', () {
      final locals = [local(id: 'l10', title: '稻香', artist: '周杰伦')];
      expect(
        SongMatcher.findLocalMatch(
          online(title: '稻香', artist: '周杰伦', mid: 'b1'),
          locals,
        )?.id,
        'l10',
      );
      expect(
        SongMatcher.findLocalMatch(
          online(title: '稻香', artist: '周杰伦', mid: 'b2'),
          locals,
          excludeIds: {'l10'},
        ),
        isNull,
      );
    });
  });
}
