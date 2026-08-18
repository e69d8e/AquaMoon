import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/core/utils/formatters.dart';
import 'package:aquamoon/models/playback_mode.dart';
import 'package:aquamoon/models/playback_progress.dart';
import 'package:aquamoon/models/song.dart';

void main() {
  group('Model & Formatter Tests', () {
    test('PlaybackMode cycling and labels', () {
      expect(PlaybackMode.sequence.next(), equals(PlaybackMode.repeatAll));
      expect(PlaybackMode.repeatAll.next(), equals(PlaybackMode.repeatOne));
      expect(PlaybackMode.repeatOne.next(), equals(PlaybackMode.shuffle));
      expect(PlaybackMode.shuffle.next(), equals(PlaybackMode.sequence));

      expect(PlaybackMode.sequence.label, equals('顺序播放'));
      expect(PlaybackMode.repeatAll.label, equals('列表循环'));
      expect(PlaybackMode.repeatOne.label, equals('单曲循环'));
      expect(PlaybackMode.shuffle.label, equals('随机播放'));
    });

    test('PlaybackProgress calculations', () {
      const progress = PlaybackProgress(
        position: Duration(seconds: 30),
        duration: Duration(seconds: 120),
        bufferedPosition: Duration(seconds: 60),
      );

      expect(progress.progressRatio, closeTo(0.25, 0.001));
      expect(progress.bufferedRatio, closeTo(0.5, 0.001));
    });

    test('Formatters test', () {
      expect(Formatters.formatDuration(const Duration(minutes: 3, seconds: 45)), equals('03:45'));
      expect(Formatters.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), equals('01:02:03'));
      expect(Formatters.formatDuration(Duration.zero), equals('00:00'));

      expect(Formatters.formatFileSize(1024), equals('1.0 KB'));
      expect(Formatters.formatFileSize(1024 * 1024 * 5), equals('5.0 MB'));
    });

    test('Song serialization and deserialization', () {
      final song = Song(
        id: 'test_123',
        title: '夜曲',
        artist: '周杰伦',
        album: '十一月的萧邦',
        durationMs: 226000,
        filePath: '/music/nocturne.mp3',
        dateAdded: DateTime(2026, 1, 1),
        isFavorite: true,
      );

      final map = song.toMap();
      final restored = Song.fromMap(map);

      expect(restored.id, equals(song.id));
      expect(restored.title, equals(song.title));
      expect(restored.artist, equals(song.artist));
      expect(restored.album, equals(song.album));
      expect(restored.durationMs, equals(song.durationMs));
      expect(restored.isFavorite, isTrue);
    });
  });
}
