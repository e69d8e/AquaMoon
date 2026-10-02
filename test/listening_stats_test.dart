import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/core/utils/formatters.dart';
import 'package:aquamoon/models/listening_stats.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/listening_stats_provider.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:aquamoon/services/listening_stats_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyListeningRecord Model Tests', () {
    test('serializes and deserializes DailyListeningRecord correctly', () {
      final snapshot = SongMetaSnapshot(
        id: 'song-1',
        title: '高山流水',
        artist: '古琴名家',
        album: '琴韵禅心',
        albumArtUri: 'file:///cover.jpg',
      );

      final record = DailyListeningRecord(
        dateStr: '2026-08-25',
        totalDurationSeconds: 1800,
        songDurationSeconds: {'song-1': 1800},
        songPlayCounts: {'song-1': 3},
        hourlyDurationSeconds: {9: 600, 10: 1200},
        songMetaCache: {'song-1': snapshot},
      );

      final map = record.toMap();
      final restored = DailyListeningRecord.fromMap(map);

      expect(restored.dateStr, '2026-08-25');
      expect(restored.totalDurationSeconds, 1800);
      expect(restored.songDurationSeconds['song-1'], 1800);
      expect(restored.songPlayCounts['song-1'], 3);
      expect(restored.hourlyDurationSeconds[9], 600);
      expect(restored.hourlyDurationSeconds[10], 1200);
      expect(restored.songMetaCache['song-1']?.title, '高山流水');
      expect(restored.songMetaCache['song-1']?.artist, '古琴名家');
    });

    test('handles empty or missing maps gracefully in fromMap', () {
      final emptyRecord = DailyListeningRecord.fromMap({});
      expect(emptyRecord.dateStr, '');
      expect(emptyRecord.totalDurationSeconds, 0);
      expect(emptyRecord.songDurationSeconds, isEmpty);
      expect(emptyRecord.songPlayCounts, isEmpty);
      expect(emptyRecord.hourlyDurationSeconds, isEmpty);
      expect(emptyRecord.songMetaCache, isEmpty);
    });
  });

  group('Formatters Duration & Date Tests', () {
    test('formatListeningDuration formats zero duration', () {
      expect(Formatters.formatListeningDuration(Duration.zero), '0 分钟');
      expect(Formatters.formatListeningDuration(Duration.zero, short: true), '0分');
    });

    test('formatListeningDuration formats sub-minute duration', () {
      expect(Formatters.formatListeningDuration(const Duration(seconds: 45)), '0 分钟');
      expect(Formatters.formatListeningDuration(const Duration(seconds: 45), short: true), '0分');
    });

    test('formatListeningDuration formats minutes', () {
      expect(Formatters.formatListeningDuration(const Duration(minutes: 15)), '15 分钟');
      expect(Formatters.formatListeningDuration(const Duration(minutes: 15, seconds: 30)), '15 分钟');
      expect(Formatters.formatListeningDuration(const Duration(minutes: 15, seconds: 30), short: true), '15分');
    });

    test('formatListeningDuration formats hours and minutes', () {
      expect(Formatters.formatListeningDuration(const Duration(hours: 2, minutes: 35)), '2 小时 35 分钟');
      expect(Formatters.formatListeningDuration(const Duration(hours: 2, minutes: 35), short: true), '2小时35分');
      expect(Formatters.formatListeningDuration(const Duration(hours: 3)), '3 小时');
    });

    test('formatDateKey formats date correctly as yyyy-MM-dd', () {
      final date = DateTime(2026, 8, 25);
      expect(Formatters.formatDateKey(date), '2026-08-25');
    });
  });

  group('StorageService Listening Statistics Integration Tests', () {
    late Directory tempDir;
    late StorageService storageService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_stats_test_');
      storageService = StorageService();
      await storageService.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('records listening duration and play count accurately', () async {
      final song1 = Song(
        id: 's1',
        title: '平沙落雁',
        artist: '古琴大师',
        album: '中国民乐',
        durationMs: 240000,
        filePath: '/music/pingsha.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      final now = DateTime(2026, 8, 25, 14, 30);

      await storageService.recordListeningDuration(
        song: song1,
        seconds: 120,
        timestamp: now,
      );

      await storageService.recordSongPlayCount(
        song: song1,
        timestamp: now,
      );

      final record = storageService.getDailyListeningRecord('2026-08-25');
      expect(record.totalDurationSeconds, 120);
      expect(record.songDurationSeconds['s1'], 120);
      expect(record.hourlyDurationSeconds[14], 120);
      expect(record.songPlayCounts['s1'], 1);
      expect(record.songMetaCache['s1']?.title, '平沙落雁');

      // Add more duration to the same day
      await storageService.recordListeningDuration(
        song: song1,
        seconds: 80,
        timestamp: now,
      );

      final updated = storageService.getDailyListeningRecord('2026-08-25');
      expect(updated.totalDurationSeconds, 200);
      expect(updated.songDurationSeconds['s1'], 200);
    });

    test('getDailyRecordsInRange retrieves records across date range', () async {
      final song = Song(
        id: 's2',
        title: '渔舟唱晚',
        artist: '古筝大师',
        album: '经典名曲',
        durationMs: 180000,
        filePath: '/music/yuzhou.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      await storageService.recordListeningDuration(
        song: song,
        seconds: 300,
        timestamp: DateTime(2026, 8, 24, 10, 0),
      );

      await storageService.recordListeningDuration(
        song: song,
        seconds: 500,
        timestamp: DateTime(2026, 8, 25, 11, 0),
      );

      final records = storageService.getDailyRecordsInRange(
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 25),
      );

      expect(records.length, 2);
      expect(records.map((r) => r.dateStr).toList(), ['2026-08-24', '2026-08-25']);
      expect(storageService.getTotalLifetimeListeningSeconds(), 800);
    });

    test('ListeningStatsTracker buffers and flushes correctly on pause/stop', () async {
      final tracker = ListeningStatsTracker(storageService);

      final song = Song(
        id: 's3',
        title: '梅花三弄',
        artist: '笛子大家',
        album: '水墨笛韵',
        durationMs: 300000,
        filePath: '/music/meihua.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      tracker.onPlay(song);
      tracker.onPause();

      final todayKey = Formatters.formatDateKey(DateTime.now());
      final record = storageService.getDailyListeningRecord(todayKey);
      expect(record.songPlayCounts['s3'], 1);

      tracker.dispose();
    });

    test('listeningPeriodStatsProvider computes Day, Week, Month, Year, and All-Time statistics', () async {
      final songA = Song(
        id: 'sa',
        title: '阳春白雪',
        artist: '琵琶大师',
        album: '国乐大典',
        durationMs: 300000,
        filePath: '/music/yangchun.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      final songB = Song(
        id: 'sb',
        title: '汉宫秋月',
        artist: '二胡名家',
        album: '弦韵',
        durationMs: 240000,
        filePath: '/music/hangong.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      // Record data for 2026-08-24 (Monday) and 2026-08-25 (Tuesday)
      final dateMon = DateTime(2026, 8, 24, 15, 0);
      final dateTue = DateTime(2026, 8, 25, 20, 0);

      await storageService.recordListeningDuration(
        song: songA,
        seconds: 1200,
        timestamp: dateMon,
      );
      await storageService.recordSongPlayCount(song: songA, timestamp: dateMon);

      await storageService.recordListeningDuration(
        song: songB,
        seconds: 600,
        timestamp: dateTue,
      );
      await storageService.recordSongPlayCount(song: songB, timestamp: dateTue);

      // Create ProviderContainer with overridden storageService
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
          statsLiveTickStreamProvider.overrideWith((ref) => Stream.value(0)),
          selectedStatsDateProvider.overrideWith((ref) => DateTime(2026, 8, 25)),
        ],
      );

      // 1. Test Day Stats for 2026-08-25
      container.read(statsPeriodTypeProvider.notifier).state = PeriodType.day;
      final dayStats = container.read(listeningPeriodStatsProvider);
      expect(dayStats.periodType, PeriodType.day);
      expect(dayStats.totalDurationSeconds, 600);
      expect(dayStats.topSongs.length, 1);
      expect(dayStats.topSongs.first.title, '汉宫秋月');
      expect(dayStats.topArtists.first.artist, '二胡名家');
      expect(dayStats.chartBars.length, 24);
      expect(dayStats.chartBars[20].durationSeconds, 600);
      expect(dayStats.chartBars[20].isHighlighted, isTrue);

      // 2. Test Week Stats for the week of Aug 24 - Aug 30, 2026
      container.read(statsPeriodTypeProvider.notifier).state = PeriodType.week;
      final weekStats = container.read(listeningPeriodStatsProvider);
      expect(weekStats.periodType, PeriodType.week);
      expect(weekStats.totalDurationSeconds, 1800);
      expect(weekStats.topSongs.length, 2);
      expect(weekStats.topSongs.first.title, '阳春白雪'); // 1200s > 600s
      expect(weekStats.chartBars.length, 7);
      expect(weekStats.chartBars[0].durationSeconds, 1200); // Mon
      expect(weekStats.chartBars[1].durationSeconds, 600); // Tue

      // 3. Test Month Stats for August 2026
      container.read(statsPeriodTypeProvider.notifier).state = PeriodType.month;
      final monthStats = container.read(listeningPeriodStatsProvider);
      expect(monthStats.periodType, PeriodType.month);
      expect(monthStats.totalDurationSeconds, 1800);
      expect(monthStats.chartBars.length, 31);
      expect(monthStats.chartBars[23].durationSeconds, 1200); // Aug 24
      expect(monthStats.chartBars[24].durationSeconds, 600); // Aug 25

      // 4. Test Year Stats for 2026
      container.read(statsPeriodTypeProvider.notifier).state = PeriodType.year;
      final yearStats = container.read(listeningPeriodStatsProvider);
      expect(yearStats.periodType, PeriodType.year);
      expect(yearStats.totalDurationSeconds, 1800);
      expect(yearStats.chartBars.length, 12);
      expect(yearStats.chartBars[7].durationSeconds, 1800); // August (index 7)
      expect(yearStats.chartBars[7].isHighlighted, isTrue);

      // 5. Test All-Time stats (lifetime per-song play counts)
      container.read(statsPeriodTypeProvider.notifier).state = PeriodType.all;
      final allStats = container.read(listeningPeriodStatsProvider);
      expect(allStats.periodType, PeriodType.all);
      expect(allStats.displayTitle, '全部时间');
      expect(allStats.totalDurationSeconds, 1800);
      expect(allStats.totalPlayCount, 2);
      expect(allStats.topSongs.length, 2);
      expect(allStats.topArtists.length, 2);
      expect(allStats.chartBars.length, 24);
      expect(allStats.chartBars[15].durationSeconds, 1200); // 15:00 (song A)
      expect(allStats.chartBars[20].durationSeconds, 600); // 20:00 (song B)
      // Tie on play count (1 vs 1) is broken by duration: 1200s > 600s.
      expect(allStats.topSongs.first.title, '阳春白雪');
      expect(allStats.topSongs.first.playCount, 1);

      container.dispose();
    });

    test('all-time stats rank by play count and include count-only songs', () async {
      final oftenPlayed = Song(
        id: 's-freq',
        title: '天天听',
        artist: '常驻歌手',
        album: '循环专辑',
        durationMs: 200000,
        filePath: '/music/freq.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      final oncePlayed = Song(
        id: 's-once',
        title: '偶尔听',
        artist: '客串歌手',
        album: '单曲专辑',
        durationMs: 300000,
        filePath: '/music/once.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );

      // 天天听: 5 plays, never any flushed listening seconds (count-only).
      for (var i = 0; i < 5; i++) {
        await storageService.recordSongPlayCount(
          song: oftenPlayed,
          timestamp: DateTime(2026, 8, 25, 12),
        );
      }
      // 偶尔听: 1 play with 3000 flushed seconds (longer duration).
      await storageService.recordListeningDuration(
        song: oncePlayed,
        seconds: 3000,
        timestamp: DateTime(2026, 8, 25, 13),
      );
      await storageService.recordSongPlayCount(
        song: oncePlayed,
        timestamp: DateTime(2026, 8, 25, 13),
      );

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
          statsLiveTickStreamProvider.overrideWith((ref) => Stream.value(0)),
        ],
      );
      addTearDown(container.dispose);

      container.read(statsPeriodTypeProvider.notifier).state = PeriodType.all;
      final allStats = container.read(listeningPeriodStatsProvider);

      // Ranked by play count, not by duration.
      expect(allStats.topSongs.first.title, '天天听');
      expect(allStats.topSongs.first.playCount, 5);
      expect(allStats.topSongs.last.title, '偶尔听');
      expect(allStats.topSongs.last.playCount, 1);

      // The count-only song (no flushed seconds) is not dropped.
      expect(allStats.topSongs.length, 2);
      expect(allStats.totalPlayCount, 6);
    });
  });
}
