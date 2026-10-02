import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/utils/formatters.dart';
import '../models/listening_stats.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';

/// Currently selected statistics period tab (Day, Week, Month, Year)
final statsPeriodTypeProvider = StateProvider<PeriodType>((ref) => PeriodType.day);

/// Currently selected reference date for viewing stats
final selectedStatsDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Stream provider for live playback tick updates from the audio handler
final statsLiveTickStreamProvider = StreamProvider<int>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.statsTracker.liveTickStream;
});

/// Computes aggregated ListeningPeriodStats for the active period type and selected date
final listeningPeriodStatsProvider = Provider<ListeningPeriodStats>((ref) {
  // Trigger rebuild on live audio playback tick
  ref.watch(statsLiveTickStreamProvider);

  final storage = ref.watch(storageServiceProvider);
  final periodType = ref.watch(statsPeriodTypeProvider);
  final targetDate = ref.watch(selectedStatsDateProvider);

  return _calculatePeriodStats(storage, periodType, targetDate);
});

/// Quick summary of today's listening for home / settings page
final todayListeningSummaryProvider = Provider<DailyListeningRecord>((ref) {
  ref.watch(statsLiveTickStreamProvider);
  final storage = ref.watch(storageServiceProvider);
  final todayStr = Formatters.formatDateKey(DateTime.now());
  return storage.getDailyListeningRecord(todayStr);
});

/// Lifetime total listening seconds
final totalLifetimeListeningSecondsProvider = Provider<int>((ref) {
  ref.watch(statsLiveTickStreamProvider);
  final storage = ref.watch(storageServiceProvider);
  return storage.getTotalLifetimeListeningSeconds();
});

ListeningPeriodStats _calculatePeriodStats(
  StorageService storage,
  PeriodType periodType,
  DateTime targetDate,
) {
  switch (periodType) {
    case PeriodType.day:
      return _computeDayStats(storage, targetDate);
    case PeriodType.week:
      return _computeWeekStats(storage, targetDate);
    case PeriodType.month:
      return _computeMonthStats(storage, targetDate);
    case PeriodType.year:
      return _computeYearStats(storage, targetDate);
    case PeriodType.all:
      return _computeAllStats(storage);
  }
}

/// Aggregates the whole listening history into a lifetime per-song play
/// count ranking plus an hour-of-day distribution.
ListeningPeriodStats _computeAllStats(StorageService storage) {
  final records = storage.getAllDailyRecords();

  final hourly = List<int>.filled(24, 0);
  int totalSeconds = 0;
  for (final r in records) {
    r.hourlyDurationSeconds.forEach((hour, sec) {
      if (hour >= 0 && hour < 24) {
        hourly[hour] += sec;
      }
    });
    totalSeconds += r.totalDurationSeconds;
  }

  final chartBars = <ChartBarData>[];
  int maxHourDuration = 0;
  int peakHour = -1;
  for (int h = 0; h < 24; h++) {
    final dur = hourly[h];
    if (dur > maxHourDuration) {
      maxHourDuration = dur;
      peakHour = h;
    }
    chartBars.add(
      ChartBarData(
        label: '${h.toString().padLeft(2, '0')}:00',
        sublabel: '${h.toString().padLeft(2, '0')}:00',
        durationSeconds: dur,
        isHighlighted: false,
      ),
    );
  }
  if (peakHour >= 0 && maxHourDuration > 0) {
    chartBars[peakHour] = ChartBarData(
      label: chartBars[peakHour].label,
      sublabel: chartBars[peakHour].sublabel,
      durationSeconds: chartBars[peakHour].durationSeconds,
      isHighlighted: true,
    );
  }

  final topSongs = _extractTopSongs(records, sortByPlayCount: true);
  final topArtists = _extractTopArtists(records);
  final totalPlayCount = topSongs.fold(0, (sum, item) => sum + item.playCount);

  final startDate = records.isEmpty
      ? DateTime.now()
      : (DateTime.tryParse(records.first.dateStr) ?? DateTime.now());
  final endDate = DateTime.now();

  String peakSummary = '暂无明显时段偏好';
  if (peakHour >= 0 && maxHourDuration > 0) {
    final nextHour = (peakHour + 1) % 24;
    peakSummary =
        '最常在 ${peakHour.toString().padLeft(2, '0')}:00 - ${nextHour.toString().padLeft(2, '0')}:00 听歌';
  }

  return ListeningPeriodStats(
    periodType: PeriodType.all,
    startDate: startDate,
    endDate: endDate,
    displayTitle: '全部时间',
    totalDurationSeconds: totalSeconds,
    totalPlayCount: totalPlayCount,
    distinctSongsCount: topSongs.length,
    distinctArtistsCount: topArtists.length,
    topSongs: topSongs,
    topArtists: topArtists,
    chartBars: chartBars,
    averageDailySeconds: records.isEmpty
        ? 0
        : totalSeconds / records.length.toDouble(),
    peakTimeSummary: peakSummary,
  );
}

ListeningPeriodStats _computeDayStats(StorageService storage, DateTime date) {
  final dateStr = Formatters.formatDateKey(date);
  final record = storage.getDailyListeningRecord(dateStr);

  final startOfDay = DateTime(date.year, date.month, date.day);
  final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

  // 24-hour bars
  final chartBars = <ChartBarData>[];
  int maxHourDuration = 0;
  int peakHour = -1;

  for (int h = 0; h < 24; h++) {
    final dur = record.hourlyDurationSeconds[h] ?? 0;
    if (dur > maxHourDuration) {
      maxHourDuration = dur;
      peakHour = h;
    }
    chartBars.add(
      ChartBarData(
        label: '${h.toString().padLeft(2, '0')}:00',
        sublabel: '${h.toString().padLeft(2, '0')}:00',
        durationSeconds: dur,
        isHighlighted: false,
      ),
    );
  }

  if (peakHour >= 0 && maxHourDuration > 0) {
    chartBars[peakHour] = ChartBarData(
      label: chartBars[peakHour].label,
      sublabel: chartBars[peakHour].sublabel,
      durationSeconds: chartBars[peakHour].durationSeconds,
      isHighlighted: true,
    );
  }

  final topSongs = _extractTopSongs([record]);
  final topArtists = _extractTopArtists([record]);
  final totalPlayCount = record.songPlayCounts.values.fold(0, (a, b) => a + b);

  final now = DateTime.now();
  final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
  final displayTitle = isToday
      ? '今天 · ${DateFormat('M月d日').format(date)}'
      : Formatters.formatChineseDate(date);

  String peakSummary = '暂无明显时段偏好';
  if (peakHour >= 0 && maxHourDuration > 0) {
    final nextHour = (peakHour + 1) % 24;
    peakSummary = '最常在 ${peakHour.toString().padLeft(2, '0')}:00 - ${nextHour.toString().padLeft(2, '0')}:00 听歌';
  }

  return ListeningPeriodStats(
    periodType: PeriodType.day,
    startDate: startOfDay,
    endDate: endOfDay,
    displayTitle: displayTitle,
    totalDurationSeconds: record.totalDurationSeconds,
    totalPlayCount: totalPlayCount,
    distinctSongsCount: record.songDurationSeconds.keys.length,
    distinctArtistsCount: topArtists.length,
    topSongs: topSongs,
    topArtists: topArtists,
    chartBars: chartBars,
    averageDailySeconds: record.totalDurationSeconds.toDouble(),
    peakTimeSummary: peakSummary,
  );
}

ListeningPeriodStats _computeWeekStats(StorageService storage, DateTime date) {
  // Monday of the week
  final monday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
  final sunday = monday.add(const Duration(days: 6));
  final endOfSunday = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

  final records = storage.getDailyRecordsInRange(monday, sunday);
  final recordMap = {for (final r in records) r.dateStr: r};

  final weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final chartBars = <ChartBarData>[];
  int totalSec = 0;
  int maxDayDuration = 0;
  int peakDayIndex = -1;

  for (int i = 0; i < 7; i++) {
    final dayDate = monday.add(Duration(days: i));
    final key = Formatters.formatDateKey(dayDate);
    final rec = recordMap[key];
    final dur = rec?.totalDurationSeconds ?? 0;
    totalSec += dur;

    if (dur > maxDayDuration) {
      maxDayDuration = dur;
      peakDayIndex = i;
    }

    chartBars.add(
      ChartBarData(
        label: weekDays[i],
        sublabel: DateFormat('M/d').format(dayDate),
        durationSeconds: dur,
        isHighlighted: false,
        date: dayDate,
      ),
    );
  }

  if (peakDayIndex >= 0 && maxDayDuration > 0) {
    chartBars[peakDayIndex] = ChartBarData(
      label: chartBars[peakDayIndex].label,
      sublabel: chartBars[peakDayIndex].sublabel,
      durationSeconds: chartBars[peakDayIndex].durationSeconds,
      isHighlighted: true,
      date: chartBars[peakDayIndex].date,
    );
  }

  final topSongs = _extractTopSongs(records);
  final topArtists = _extractTopArtists(records);
  int totalPlayCount = 0;
  for (final r in records) {
    totalPlayCount += r.songPlayCounts.values.fold(0, (a, b) => a + b);
  }

  final now = DateTime.now();
  final thisMonday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  final isThisWeek = monday.year == thisMonday.year &&
      monday.month == thisMonday.month &&
      monday.day == thisMonday.day;

  final displayTitle = isThisWeek
      ? '本周 (${DateFormat('M月d日').format(monday)} - ${DateFormat('M月d日').format(sunday)})'
      : '${monday.year}年 (${DateFormat('M月d日').format(monday)} - ${DateFormat('M月d日').format(sunday)})';

  String peakSummary = '整周分布均匀';
  if (peakDayIndex >= 0 && maxDayDuration > 0) {
    peakSummary = '${weekDays[peakDayIndex]} 听歌最多 (${Formatters.formatListeningDuration(Duration(seconds: maxDayDuration), short: true)})';
  }

  return ListeningPeriodStats(
    periodType: PeriodType.week,
    startDate: monday,
    endDate: endOfSunday,
    displayTitle: displayTitle,
    totalDurationSeconds: totalSec,
    totalPlayCount: totalPlayCount,
    distinctSongsCount: topSongs.length,
    distinctArtistsCount: topArtists.length,
    topSongs: topSongs,
    topArtists: topArtists,
    chartBars: chartBars,
    averageDailySeconds: totalSec / 7.0,
    peakTimeSummary: peakSummary,
  );
}

ListeningPeriodStats _computeMonthStats(StorageService storage, DateTime date) {
  final firstDay = DateTime(date.year, date.month, 1);
  final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
  final lastDay = DateTime(date.year, date.month, daysInMonth, 23, 59, 59);

  final records = storage.getDailyRecordsInRange(firstDay, lastDay);
  final recordMap = {for (final r in records) r.dateStr: r};

  final chartBars = <ChartBarData>[];
  int totalSec = 0;
  int maxDayDuration = 0;
  int peakDay = -1;

  for (int d = 1; d <= daysInMonth; d++) {
    final dayDate = DateTime(date.year, date.month, d);
    final key = Formatters.formatDateKey(dayDate);
    final rec = recordMap[key];
    final dur = rec?.totalDurationSeconds ?? 0;
    totalSec += dur;

    if (dur > maxDayDuration) {
      maxDayDuration = dur;
      peakDay = d;
    }

    chartBars.add(
      ChartBarData(
        label: '$d日',
        sublabel: '$d',
        durationSeconds: dur,
        isHighlighted: false,
        date: dayDate,
      ),
    );
  }

  if (peakDay > 0 && maxDayDuration > 0) {
    final idx = peakDay - 1;
    chartBars[idx] = ChartBarData(
      label: chartBars[idx].label,
      sublabel: chartBars[idx].sublabel,
      durationSeconds: chartBars[idx].durationSeconds,
      isHighlighted: true,
      date: chartBars[idx].date,
    );
  }

  final topSongs = _extractTopSongs(records);
  final topArtists = _extractTopArtists(records);
  int totalPlayCount = 0;
  for (final r in records) {
    totalPlayCount += r.songPlayCounts.values.fold(0, (a, b) => a + b);
  }

  final now = DateTime.now();
  final isThisMonth = date.year == now.year && date.month == now.month;
  final displayTitle = isThisMonth ? '本月 (${DateFormat('yyyy年M月').format(date)})' : DateFormat('yyyy年M月').format(date);

  String peakSummary = '单日听歌平稳';
  if (peakDay > 0 && maxDayDuration > 0) {
    peakSummary = '$peakDay日听歌最多 (${Formatters.formatListeningDuration(Duration(seconds: maxDayDuration), short: true)})';
  }

  return ListeningPeriodStats(
    periodType: PeriodType.month,
    startDate: firstDay,
    endDate: lastDay,
    displayTitle: displayTitle,
    totalDurationSeconds: totalSec,
    totalPlayCount: totalPlayCount,
    distinctSongsCount: topSongs.length,
    distinctArtistsCount: topArtists.length,
    topSongs: topSongs,
    topArtists: topArtists,
    chartBars: chartBars,
    averageDailySeconds: totalSec / daysInMonth.toDouble(),
    peakTimeSummary: peakSummary,
  );
}

ListeningPeriodStats _computeYearStats(StorageService storage, DateTime date) {
  final firstDay = DateTime(date.year, 1, 1);
  final lastDay = DateTime(date.year, 12, 31, 23, 59, 59);

  final records = storage.getDailyRecordsInRange(firstDay, lastDay);

  final monthDurations = List<int>.filled(12, 0);
  int totalSec = 0;

  for (final r in records) {
    final parsed = DateTime.tryParse(r.dateStr);
    if (parsed != null && parsed.year == date.year) {
      final mIdx = parsed.month - 1;
      monthDurations[mIdx] += r.totalDurationSeconds;
      totalSec += r.totalDurationSeconds;
    }
  }

  final chartBars = <ChartBarData>[];
  int maxMonthDuration = 0;
  int peakMonth = -1;

  for (int m = 0; m < 12; m++) {
    final dur = monthDurations[m];
    if (dur > maxMonthDuration) {
      maxMonthDuration = dur;
      peakMonth = m + 1;
    }
    chartBars.add(
      ChartBarData(
        label: '${m + 1}月',
        sublabel: '${m + 1}月',
        durationSeconds: dur,
        isHighlighted: false,
      ),
    );
  }

  if (peakMonth > 0 && maxMonthDuration > 0) {
    final idx = peakMonth - 1;
    chartBars[idx] = ChartBarData(
      label: chartBars[idx].label,
      sublabel: chartBars[idx].sublabel,
      durationSeconds: chartBars[idx].durationSeconds,
      isHighlighted: true,
    );
  }

  final topSongs = _extractTopSongs(records);
  final topArtists = _extractTopArtists(records);
  int totalPlayCount = 0;
  for (final r in records) {
    totalPlayCount += r.songPlayCounts.values.fold(0, (a, b) => a + b);
  }

  final isLeapYear = (date.year % 4 == 0 && date.year % 100 != 0) || (date.year % 400 == 0);
  final daysInYear = isLeapYear ? 366 : 365;

  final now = DateTime.now();
  final isThisYear = date.year == now.year;
  final displayTitle = isThisYear ? '今年 (${date.year}年度)' : '${date.year}年度';

  String peakSummary = '全年各月分布均匀';
  if (peakMonth > 0 && maxMonthDuration > 0) {
    peakSummary = '$peakMonth月 听歌最久 (${Formatters.formatListeningDuration(Duration(seconds: maxMonthDuration), short: true)})';
  }

  return ListeningPeriodStats(
    periodType: PeriodType.year,
    startDate: firstDay,
    endDate: lastDay,
    displayTitle: displayTitle,
    totalDurationSeconds: totalSec,
    totalPlayCount: totalPlayCount,
    distinctSongsCount: topSongs.length,
    distinctArtistsCount: topArtists.length,
    topSongs: topSongs,
    topArtists: topArtists,
    chartBars: chartBars,
    averageDailySeconds: totalSec / daysInYear.toDouble(),
    peakTimeSummary: peakSummary,
  );
}

List<SongStatItem> _extractTopSongs(
  List<DailyListeningRecord> records, {
  bool sortByPlayCount = false,
}) {
  final durationMap = <String, int>{};
  final playCountMap = <String, int>{};
  final metaMap = <String, SongMetaSnapshot>{};

  for (final rec in records) {
    rec.songDurationSeconds.forEach((songId, dur) {
      durationMap[songId] = (durationMap[songId] ?? 0) + dur;
    });
    rec.songPlayCounts.forEach((songId, count) {
      playCountMap[songId] = (playCountMap[songId] ?? 0) + count;
    });
    rec.songMetaCache.forEach((songId, meta) {
      metaMap.putIfAbsent(songId, () => meta);
    });
  }

  // A song can have a play count without flushed listening seconds yet
  // (seconds are buffered and written in minute batches), so union the keys.
  final songIds = <String>{...durationMap.keys, ...playCountMap.keys};

  final items = <SongStatItem>[];
  for (final songId in songIds) {
    final dur = durationMap[songId] ?? 0;
    final count = playCountMap[songId] ?? 0;
    final meta = metaMap[songId];

    items.add(
      SongStatItem(
        songId: songId,
        title: meta?.title ?? '未知曲目',
        artist: meta?.artist ?? '未知歌手',
        album: meta?.album ?? '',
        albumArtUri: meta?.albumArtUri,
        durationSeconds: dur,
        playCount: count,
      ),
    );
  }

  if (sortByPlayCount) {
    items.sort((a, b) {
      final byCount = b.playCount.compareTo(a.playCount);
      if (byCount != 0) return byCount;
      return b.durationSeconds.compareTo(a.durationSeconds);
    });
  } else {
    items.sort((a, b) => b.durationSeconds.compareTo(a.durationSeconds));
  }
  return items;
}

List<ArtistStatItem> _extractTopArtists(List<DailyListeningRecord> records) {
  final artistDurationMap = <String, int>{};
  final artistSongsMap = <String, Set<String>>{};
  final artistPlayCountMap = <String, int>{};

  for (final rec in records) {
    rec.songDurationSeconds.forEach((songId, dur) {
      final meta = rec.songMetaCache[songId];
      final artist = (meta?.artist.trim().isNotEmpty ?? false) ? meta!.artist.trim() : '未知歌手';
      if (artist == '未知歌手') return;

      artistDurationMap[artist] = (artistDurationMap[artist] ?? 0) + dur;
      artistSongsMap.putIfAbsent(artist, () => <String>{}).add(songId);
      final pc = rec.songPlayCounts[songId] ?? 0;
      artistPlayCountMap[artist] = (artistPlayCountMap[artist] ?? 0) + pc;
    });
  }

  final items = <ArtistStatItem>[];
  for (final artist in artistDurationMap.keys) {
    items.add(
      ArtistStatItem(
        artist: artist,
        durationSeconds: artistDurationMap[artist] ?? 0,
        songCount: artistSongsMap[artist]?.length ?? 0,
        playCount: artistPlayCountMap[artist] ?? 0,
      ),
    );
  }

  items.sort((a, b) => b.durationSeconds.compareTo(a.durationSeconds));
  return items;
}
