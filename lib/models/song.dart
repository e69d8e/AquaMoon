import 'dart:typed_data';

enum SongSource { local, online }

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String filePath;
  final String? albumArtUri; // local file:// or https://
  final Uint8List? albumArtBytes;
  final String? lrcContent;
  final DateTime dateAdded;
  final int playCount;
  final bool isFavorite;
  final SongSource source;
  final int? trackNumber;
  final int? year;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.filePath,
    this.albumArtUri,
    this.albumArtBytes,
    this.lrcContent,
    required this.dateAdded,
    this.playCount = 0,
    this.isFavorite = false,
    this.source = SongSource.local,
    this.trackNumber,
    this.year,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? filePath,
    String? albumArtUri,
    Uint8List? albumArtBytes,
    String? lrcContent,
    bool clearLrcContent = false,
    DateTime? dateAdded,
    int? playCount,
    bool? isFavorite,
    SongSource? source,
    int? trackNumber,
    int? year,
    bool clearYear = false,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      filePath: filePath ?? this.filePath,
      albumArtUri: albumArtUri ?? this.albumArtUri,
      albumArtBytes: albumArtBytes ?? this.albumArtBytes,
      lrcContent: clearLrcContent ? null : (lrcContent ?? this.lrcContent),
      dateAdded: dateAdded ?? this.dateAdded,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
      source: source ?? this.source,
      trackNumber: trackNumber ?? this.trackNumber,
      year: clearYear ? null : (year ?? this.year),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'filePath': filePath,
      'albumArtUri': albumArtUri,
      'lrcContent': lrcContent,
      'dateAdded': dateAdded.toIso8601String(),
      'playCount': playCount,
      'isFavorite': isFavorite,
      'source': source.name,
      'trackNumber': trackNumber,
      'year': year,
    };
  }

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    return Song(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '未知曲目',
      artist: map['artist'] as String? ?? '未知歌手',
      album: map['album'] as String? ?? '未知专辑',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      filePath: map['filePath'] as String? ?? '',
      albumArtUri: map['albumArtUri'] as String?,
      lrcContent: map['lrcContent'] as String?,
      dateAdded: map['dateAdded'] is String
          ? DateTime.tryParse(map['dateAdded'] as String) ?? DateTime.now()
          : DateTime.now(),
      playCount: (map['playCount'] as num?)?.toInt() ?? 0,
      isFavorite: map['isFavorite'] as bool? ?? false,
      source: SongSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => SongSource.local,
      ),
      trackNumber: (map['trackNumber'] as num?)?.toInt(),
      year: (map['year'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
