import 'song.dart';

/// QQ 音乐发现页中「歌单 / 专辑 / 榜单」入口的类型。
///
/// 与 [QQMusicCollection.kind] 一起决定详情接口：歌单走 disstid，
/// 专辑走 albumMid，榜单走 topId。
enum QQMusicCollectionKind {
  playlist('playlist'),
  album('album'),
  chart('chart');

  const QQMusicCollectionKind(this.key);

  /// 持久化 / JSON 中使用的稳定标识，不依赖枚举顺序。
  final String key;

  static QQMusicCollectionKind fromKey(String? key) =>
      QQMusicCollectionKind.values.firstWhere(
        (value) => value.key == key,
        orElse: () => QQMusicCollectionKind.playlist,
      );
}

/// 在线音质档位。`filenamePrefix` 用于拼 QQ 音乐 vkey 接口的 filename，
/// `extension` 是对应容器后缀；[requiresCookie] 表示通常需要绿钻 Cookie
/// 才能拿到非空 purl。
///
/// 档位与前缀照搬 go-music-dl / music-lib 的 `qqQualityCandidates`
/// （AI00 臻品母带 → Q001/Q000 全景声 → F000 无损 → O801 超清 →
/// M800 320K → M500 128K），顺序即从高到低的选优优先级。
enum QQMusicStreamQuality {
  master('臻品母带 · FLAC', 'AI00', 'flac', true),
  atmos51('全景声 5.1 · FLAC', 'Q001', 'flac', true),
  atmos('全景声 2.0 · FLAC', 'Q000', 'flac', true),
  lossless('无损 · FLAC', 'F000', 'flac', true),
  ultra('超高品质 · OGG', 'O801', 'ogg', true),
  high('高品质 · 320K MP3', 'M800', 'mp3', false),
  standard('标准 · 128K MP3', 'M500', 'mp3', false);

  const QQMusicStreamQuality(
    this.label,
    this.filenamePrefix,
    this.extension,
    this.requiresCookie,
  );

  final String label;
  final String filenamePrefix;
  final String extension;
  final bool requiresCookie;

  static QQMusicStreamQuality fromName(String? name) =>
      QQMusicStreamQuality.values.firstWhere(
        (value) => value.name == name,
        orElse: () => QQMusicStreamQuality.high,
      );
}

/// 官方歌单分类（`fcg_get_diss_tag_conf.fcg`）。
class QQMusicCategory {
  final String id;
  final String name;
  final String group;

  const QQMusicCategory({
    required this.id,
    required this.name,
    this.group = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'group': group,
      };

  factory QQMusicCategory.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const QQMusicCategory(id: '', name: '');
    return QQMusicCategory(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      group: map['group'] as String? ?? '',
    );
  }
}

/// 歌单 / 专辑 / 榜单的概要信息（列表卡片用）。
class QQMusicCollection {
  final String id;
  final QQMusicCollectionKind kind;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final int songCount;
  final String? description;

  /// 榜单的更新时间 / 推荐语等次级信息，按原样展示。
  final String? badge;

  const QQMusicCollection({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.coverUrl,
    this.songCount = 0,
    this.description,
    this.badge,
  });

  QQMusicCollection copyWith({
    String? id,
    QQMusicCollectionKind? kind,
    String? title,
    String? subtitle,
    String? coverUrl,
    int? songCount,
    String? description,
    String? badge,
  }) {
    return QQMusicCollection(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      coverUrl: coverUrl ?? this.coverUrl,
      songCount: songCount ?? this.songCount,
      description: description ?? this.description,
      badge: badge ?? this.badge,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.key,
        'title': title,
        'subtitle': subtitle,
        'coverUrl': coverUrl,
        'songCount': songCount,
        'description': description,
        'badge': badge,
      };

  factory QQMusicCollection.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const QQMusicCollection(
        id: '',
        kind: QQMusicCollectionKind.playlist,
        title: '',
      );
    }
    return QQMusicCollection(
      id: map['id'] as String? ?? '',
      kind: QQMusicCollectionKind.fromKey(map['kind'] as String?),
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      songCount: (map['songCount'] as num?)?.toInt() ?? 0,
      description: map['description'] as String?,
      badge: map['badge'] as String?,
    );
  }
}

/// 集合详情：概要 + 可播放曲目。
class QQMusicCollectionDetail {
  final QQMusicCollection collection;
  final List<Song> songs;

  const QQMusicCollectionDetail({
    required this.collection,
    required this.songs,
  });

  Map<String, dynamic> toMap() => {
        'collection': collection.toMap(),
        'songs': songs.map((song) => song.toMap()).toList(),
      };

  factory QQMusicCollectionDetail.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const QQMusicCollectionDetail(
        collection: QQMusicCollection(
          id: '',
          kind: QQMusicCollectionKind.playlist,
          title: '',
        ),
        songs: [],
      );
    }
    final rawSongs = map['songs'] as List<dynamic>? ?? const [];
    return QQMusicCollectionDetail(
      collection: QQMusicCollection.fromMap(
        map['collection'] as Map<dynamic, dynamic>?,
      ),
      songs: rawSongs
          .whereType<Map>()
          .map((entry) => Song.fromMap(entry))
          .toList(),
    );
  }
}
