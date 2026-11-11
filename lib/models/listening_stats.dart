import 'package:flutter/foundation.dart';
import 'song.dart';

enum PeriodType {
  day,
  week,
  month,
  year,
  all;

  String get label {
    switch (this) {
      case PeriodType.day:
        return '日';
      case PeriodType.week:
        return '周';
      case PeriodType.month:
        return '月';
      case PeriodType.year:
        return '年';
      case PeriodType.all:
        return '总';
    }
  }
}

/// Snapshot of a song's metadata to preserve display info in statistics
/// even if a song is later deleted from local storage or moved.
@immutable
class SongMetaSnapshot {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumArtUri;
  final String? qqSongMid;
  final int? qqSongId;
  final String? qqMediaMid;
  final bool isVip;
  final bool isQQMusicOnline;

  const SongMetaSnapshot({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtUri,
    this.qqSongMid,
    this.qqSongId,
    this.qqMediaMid,
    this.isVip = false,
    this.isQQMusicOnline = false,
  });

  factory SongMetaSnapshot.fromSong(Song song) {
    return SongMetaSnapshot(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      albumArtUri: song.albumArtUri,
      qqSongMid: song.qqSongMid,
      qqSongId: song.qqSongId,
      qqMediaMid: song.qqMediaMid,
      isVip: song.isVip,
      isQQMusicOnline: song.isQQMusicOnline,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtUri': albumArtUri,
      'qqSongMid': qqSongMid,
      'qqSongId': qqSongId,
      'qqMediaMid': qqMediaMid,
      'isVip': isVip,
      'isQQMusicOnline': isQQMusicOnline,
    };
  }

  factory SongMetaSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final qqMid = map['qqSongMid'] as String?;
    return SongMetaSnapshot(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '未知曲目',
      artist: map['artist'] as String? ?? '未知歌手',
      album: map['album'] as String? ?? '未知专辑',
      albumArtUri: map['albumArtUri'] as String?,
      qqSongMid: qqMid,
      qqSongId: (map['qqSongId'] as num?)?.toInt(),
      qqMediaMid: map['qqMediaMid'] as String?,
      isVip: map['isVip'] as bool? ?? false,
      isQQMusicOnline:
          map['isQQMusicOnline'] as bool? ??
          ((map['id'] as String? ?? '').startsWith('qq_') &&
              qqMid != null &&
              qqMid.isNotEmpty),
    );
  }
}

/// Persisted daily listening log record.
@immutable
class DailyListeningRecord {
  final String dateStr; // Format: yyyy-MM-dd
  final int totalDurationSeconds;
  final Map<String, int> songDurationSeconds; // songId -> seconds
  final Map<String, int> songPlayCounts; // songId -> play count
  final Map<int, int> hourlyDurationSeconds; // hour (0..23) -> seconds
  final Map<String, SongMetaSnapshot> songMetaCache; // songId -> snapshot

  const DailyListeningRecord({
    required this.dateStr,
    this.totalDurationSeconds = 0,
    this.songDurationSeconds = const {},
    this.songPlayCounts = const {},
    this.hourlyDurationSeconds = const {},
    this.songMetaCache = const {},
  });

  DailyListeningRecord copyWith({
    String? dateStr,
    int? totalDurationSeconds,
    Map<String, int>? songDurationSeconds,
    Map<String, int>? songPlayCounts,
    Map<int, int>? hourlyDurationSeconds,
    Map<String, SongMetaSnapshot>? songMetaCache,
  }) {
    return DailyListeningRecord(
      dateStr: dateStr ?? this.dateStr,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      songDurationSeconds: songDurationSeconds ?? this.songDurationSeconds,
      songPlayCounts: songPlayCounts ?? this.songPlayCounts,
      hourlyDurationSeconds: hourlyDurationSeconds ?? this.hourlyDurationSeconds,
      songMetaCache: songMetaCache ?? this.songMetaCache,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dateStr': dateStr,
      'totalDurationSeconds': totalDurationSeconds,
      'songDurationSeconds': songDurationSeconds,
      'songPlayCounts': songPlayCounts,
      'hourlyDurationSeconds': hourlyDurationSeconds.map((k, v) => MapEntry(k.toString(), v)),
      'songMetaCache': songMetaCache.map((k, v) => MapEntry(k, v.toMap())),
    };
  }

  factory DailyListeningRecord.fromMap(Map<dynamic, dynamic> map) {
    final dateStr = map['dateStr'] as String? ?? '';
    final totalDurationSeconds = (map['totalDurationSeconds'] as num?)?.toInt() ?? 0;

    final rawSongDurations = map['songDurationSeconds'];
    final songDurationSeconds = <String, int>{};
    if (rawSongDurations is Map) {
      rawSongDurations.forEach((k, v) {
        if (k != null && v is num) {
          songDurationSeconds[k.toString()] = v.toInt();
        }
      });
    }

    final rawPlayCounts = map['songPlayCounts'];
    final songPlayCounts = <String, int>{};
    if (rawPlayCounts is Map) {
      rawPlayCounts.forEach((k, v) {
        if (k != null && v is num) {
          songPlayCounts[k.toString()] = v.toInt();
        }
      });
    }

    final rawHourly = map['hourlyDurationSeconds'];
    final hourlyDurationSeconds = <int, int>{};
    if (rawHourly is Map) {
      rawHourly.forEach((k, v) {
        final hour = int.tryParse(k.toString());
        if (hour != null && v is num) {
          hourlyDurationSeconds[hour] = v.toInt();
        }
      });
    }

    final rawCache = map['songMetaCache'];
    final songMetaCache = <String, SongMetaSnapshot>{};
    if (rawCache is Map) {
      rawCache.forEach((k, v) {
        if (k != null && v is Map) {
          songMetaCache[k.toString()] = SongMetaSnapshot.fromMap(v);
        }
      });
    }

    return DailyListeningRecord(
      dateStr: dateStr,
      totalDurationSeconds: totalDurationSeconds,
      songDurationSeconds: songDurationSeconds,
      songPlayCounts: songPlayCounts,
      hourlyDurationSeconds: hourlyDurationSeconds,
      songMetaCache: songMetaCache,
    );
  }
}

/// Item in the top songs listening leaderboard
class SongStatItem {
  final String songId;
  final String title;
  final String artist;
  final String album;
  final String? albumArtUri;
  final int durationSeconds;
  final int playCount;
  final String? qqSongMid;
  final int? qqSongId;
  final String? qqMediaMid;
  final bool isVip;
  final bool isQQMusicOnline;

  const SongStatItem({
    required this.songId,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtUri,
    required this.durationSeconds,
    required this.playCount,
    this.qqSongMid,
    this.qqSongId,
    this.qqMediaMid,
    this.isVip = false,
    this.isQQMusicOnline = false,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  bool get hasQQMusicLink => qqSongMid != null && qqSongMid!.isNotEmpty;

  /// Converts this leaderboard item into an online playable [Song] when
  /// backed by a [qqSongMid].
  Song? toOnlinePlayableSong() {
    if (!hasQQMusicLink) return null;
    return Song(
      id: songId.isNotEmpty ? songId : 'qq_$qqSongMid',
      title: title,
      artist: artist,
      album: album,
      durationMs: 0,
      filePath: 'qqmusic://$qqSongMid',
      albumArtUri: albumArtUri,
      dateAdded: DateTime.now(),
      playCount: playCount,
      isFavorite: true,
      source: SongSource.online,
      qqSongMid: qqSongMid,
      qqSongId: qqSongId,
      qqMediaMid: qqMediaMid ?? qqSongMid,
      isVip: isVip,
    );
  }
}

/// Summary of QQ Music cloud listening statistics synchronization & reporting.
@immutable
class QQMusicCloudStatsSummary {
  final int importedSongCount;
  final int importedPlayCount;
  final int importedDurationSeconds;
  final int reportedPlayCount;
  final int todayListenSeconds;
  final DateTime? lastSyncTime;

  const QQMusicCloudStatsSummary({
    this.importedSongCount = 0,
    this.importedPlayCount = 0,
    this.importedDurationSeconds = 0,
    this.reportedPlayCount = 0,
    this.todayListenSeconds = 0,
    this.lastSyncTime,
  });

  QQMusicCloudStatsSummary copyWith({
    int? importedSongCount,
    int? importedPlayCount,
    int? importedDurationSeconds,
    int? reportedPlayCount,
    int? todayListenSeconds,
    DateTime? lastSyncTime,
  }) {
    return QQMusicCloudStatsSummary(
      importedSongCount: importedSongCount ?? this.importedSongCount,
      importedPlayCount: importedPlayCount ?? this.importedPlayCount,
      importedDurationSeconds:
          importedDurationSeconds ?? this.importedDurationSeconds,
      reportedPlayCount: reportedPlayCount ?? this.reportedPlayCount,
      todayListenSeconds: todayListenSeconds ?? this.todayListenSeconds,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'importedSongCount': importedSongCount,
      'importedPlayCount': importedPlayCount,
      'importedDurationSeconds': importedDurationSeconds,
      'reportedPlayCount': reportedPlayCount,
      'todayListenSeconds': todayListenSeconds,
      'lastSyncMs': lastSyncTime?.millisecondsSinceEpoch,
    };
  }

  factory QQMusicCloudStatsSummary.fromMap(Object? raw) {
    if (raw is! Map) return const QQMusicCloudStatsSummary();
    final syncMs = (raw['lastSyncMs'] as num?)?.toInt();
    return QQMusicCloudStatsSummary(
      importedSongCount:
          (raw['importedSongCount'] as num?)?.toInt() ??
          (raw['syncedCloudSongsCount'] as num?)?.toInt() ??
          0,
      importedPlayCount: (raw['importedPlayCount'] as num?)?.toInt() ?? 0,
      importedDurationSeconds:
          (raw['importedDurationSeconds'] as num?)?.toInt() ?? 0,
      reportedPlayCount: (raw['reportedPlayCount'] as num?)?.toInt() ?? 0,
      todayListenSeconds: (raw['todayListenSeconds'] as num?)?.toInt() ?? 0,
      lastSyncTime: syncMs != null
          ? DateTime.fromMillisecondsSinceEpoch(syncMs)
          : null,
    );
  }
}

/// 一条 QQ 音乐云端「最近播放」记录：曲目 + 云端累计播放次数 + 最后播放时间。
///
/// `PlayRecentlyRead.GetPlayRecentlyInfo` 把曲目放在 `track`，累计次数放在同级
/// `listenCnt`，因此需要单独携带，不能只依赖 [Song.playCount]。
@immutable
class QQMusicCloudHistoryEntry {
  final Song song;
  final DateTime? lastPlayedAt;

  const QQMusicCloudHistoryEntry({required this.song, this.lastPlayedAt});

  int get playCount => song.playCount;

  String get songMid => song.qqSongMid ?? '';
}

/// Item in the top artists listening leaderboard
class ArtistStatItem {
  final String artist;
  final int durationSeconds;
  final int songCount;
  final int playCount;

  const ArtistStatItem({
    required this.artist,
    required this.durationSeconds,
    required this.songCount,
    required this.playCount,
  });

  Duration get duration => Duration(seconds: durationSeconds);
}

/// Bar chart data point for visualization
class ChartBarData {
  final String label;
  final String sublabel;
  final int durationSeconds;
  final bool isHighlighted;
  final DateTime? date;

  const ChartBarData({
    required this.label,
    this.sublabel = '',
    required this.durationSeconds,
    this.isHighlighted = false,
    this.date,
  });

  Duration get duration => Duration(seconds: durationSeconds);
}

/// Aggregated listening statistics for a given period (Day, Week, Month, Year)
class ListeningPeriodStats {
  final PeriodType periodType;
  final DateTime startDate;
  final DateTime endDate;
  final String displayTitle;
  final int totalDurationSeconds;
  final int totalPlayCount;
  final int distinctSongsCount;
  final int distinctArtistsCount;
  final List<SongStatItem> topSongs;
  final List<ArtistStatItem> topArtists;
  final List<ChartBarData> chartBars;
  final double averageDailySeconds;
  final String peakTimeSummary;

  const ListeningPeriodStats({
    required this.periodType,
    required this.startDate,
    required this.endDate,
    required this.displayTitle,
    required this.totalDurationSeconds,
    required this.totalPlayCount,
    required this.distinctSongsCount,
    required this.distinctArtistsCount,
    required this.topSongs,
    required this.topArtists,
    required this.chartBars,
    required this.averageDailySeconds,
    required this.peakTimeSummary,
  });

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
  Duration get averageDailyDuration => Duration(seconds: averageDailySeconds.round());

  bool get isEmpty => totalDurationSeconds == 0 && topSongs.isEmpty;
}
