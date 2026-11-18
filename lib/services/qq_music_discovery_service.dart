import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/qq_music_config.dart';
import '../models/qq_music_discovery.dart';
import '../models/song.dart';
import 'qq_music_service.dart';

/// QQ 音乐发现接口错误。
class QQMusicDiscoveryException implements Exception {
  final String message;

  const QQMusicDiscoveryException(this.message);

  @override
  String toString() => message;
}

/// 纯 Dart 复刻 go-music-dl / music-lib 的 QQ 音乐「发现」协议：
/// 单曲搜索、歌单 / 专辑 / 榜单、推荐、分类、分享链接解析。
///
/// 播放本身不走这里：返回的 [Song] 带 `qqSongMid` 与 `qqmusic://` 占位路径，
/// 由 `SoundCraftAudioHandler` 复用既有的 vkey 取流链路。
/// 协议细节见 `docs/qq_music_protocol.md`。
class QQMusicDiscoveryService {
  QQMusicDiscoveryService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const int pageSize = 20;
  static const Duration _timeout = Duration(seconds: 12);

  static const String _musicuUrl =
      'https://u.y.qq.com/cgi-bin/musicu.fcg';

  static const List<String> _playlistDetailUrls = <String>[
    'https://i.y.qq.com/qzone-music/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
    'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
    'https://c.y.qq.com/qzone/fcgi-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
  ];

  static const String _iphoneUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 9_1 like Mac OS X) '
      'AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13B143 Safari/601.1';
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36';

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ---------------------------------------------------------------------------
  // 分享链接解析
  // ---------------------------------------------------------------------------

  /// 把 QQ 音乐分享链接解析成歌单 / 专辑合集；非链接返回 null。
  static QQMusicCollection? parseShareInput(String input) {
    final text = input.trim();
    if (!text.contains('qq.com')) return null;

    final albumMatch =
            RegExp(r'album(?:Detail)?/([A-Za-z0-9]+)', caseSensitive: false)
                .firstMatch(text) ??
        RegExp(r'[?&]albummid=([A-Za-z0-9]+)', caseSensitive: false)
            .firstMatch(text);
    if (albumMatch != null) {
      final id = albumMatch.group(1)!;
      return QQMusicCollection(
        id: id,
        kind: QQMusicCollectionKind.album,
        title: 'QQ 音乐专辑',
        subtitle: id,
      );
    }

    final playlistId = extractPlaylistId(text);
    if (playlistId != null) {
      return QQMusicCollection(
        id: playlistId,
        kind: QQMusicCollectionKind.playlist,
        title: 'QQ 音乐歌单',
        subtitle: playlistId,
      );
    }
    return null;
  }

  /// 支持 `.../playlist/8825279434`、`?id=` / `?disstid=` / `?dissid=`、
  /// 以及手输的 `dissid:123456` / `#123456`。只接受纯数字歌单 ID。
  static String? extractPlaylistId(String input) {
    final text = input.trim();
    if (text.contains('songDetail')) return null;

    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasQuery) {
      for (final key in const <String>['id', 'disstid', 'dissid', 'tid']) {
        final value = uri.queryParameters[key];
        if (value != null && RegExp(r'^\d{4,20}$').hasMatch(value)) {
          return value;
        }
      }
    }

    final pathMatch =
        RegExp(r'(?:^|/)playlist/(\d+)(?:[/?#]|$)', caseSensitive: false)
            .firstMatch(text);
    if (pathMatch != null) return pathMatch.group(1);

    final plainMatch =
        RegExp(r'^(?:dissid:|id:|#)(\d{6,20})$', caseSensitive: false)
            .firstMatch(text);
    return plainMatch?.group(1);
  }

  /// 从单曲分享链接中提取 songMid（`songDetail/xxx` 或 `?songmid=xxx`）。
  static String? parseSongMid(String input) {
    final text = input.trim();
    if (!text.contains('qq.com')) return null;
    final match =
        RegExp(r'songDetail/([A-Za-z0-9]+)', caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'[?&]songmid=([A-Za-z0-9]+)', caseSensitive: false)
            .firstMatch(text);
    return match?.group(1);
  }

  // ---------------------------------------------------------------------------
  // 单曲搜索
  // ---------------------------------------------------------------------------

  /// 关键词搜索。优先 go-music-dl 使用的 `search_for_qq_cp`（支持分页），
  /// 失败或空结果时回退到本项目已在用的 desktop `musicu.fcg` 搜索。
  Future<List<Song>> searchSongs(
    String keyword, {
    int page = 1,
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return const <Song>[];
    final safePage = page < 1 ? 1 : page;

    final legacy = await _tryLegacySongSearch(query, safePage, config);
    if (legacy.isNotEmpty) return legacy;

    try {
      return await _desktopSongSearch(query, safePage, config);
    } on QQMusicDiscoveryException {
      if (legacy.isNotEmpty) return legacy;
      rethrow;
    } catch (_) {
      return legacy;
    }
  }

  Future<List<Song>> _tryLegacySongSearch(
    String keyword,
    int page,
    QQMusicConfig config,
  ) async {
    try {
      final uri = Uri.https('c.y.qq.com', '/soso/fcgi-bin/search_for_qq_cp', <String, String>{
        'w': keyword,
        'format': 'json',
        'p': '$page',
        'n': '$pageSize',
      });
      final decoded = await _getJson(
        uri,
        config: config,
        referer: 'http://m.y.qq.com',
        userAgent: _iphoneUserAgent,
      );
      final list = _asList(_dig(decoded, 'data', 'song', 'list'));
      if (list.isEmpty) return const <Song>[];
      return _buildSongs(list, (item, index) => _songFromLegacy(item, index));
    } catch (_) {
      return const <Song>[];
    }
  }

  Future<List<Song>> _desktopSongSearch(
    String keyword,
    int page,
    QQMusicConfig config,
  ) async {
    final body = <String, dynamic>{
      'comm': <String, dynamic>{'ct': 19, 'cv': 1859, 'uin': 0, 'format': 'json'},
      'req': <String, dynamic>{
        'module': 'music.search.SearchCgiService',
        'method': 'DoSearchForQQMusicDesktop',
        'param': <String, dynamic>{
          'search_type': 0,
          'query': keyword,
          'page_num': page,
          'num_per_page': pageSize,
        },
      },
    };
    final decoded = await _postMusicu(body, config: config);
    final list = _asList(_dig(decoded, 'req', 'data', 'body', 'song', 'list'));
    if (list.isEmpty && _int(_dig(decoded, 'req', 'code')) != 0) {
      throw QQMusicDiscoveryException('QQ 音乐搜索未返回结果，请稍后重试');
    }
    return _buildSongs(list, (item, index) => _songFromDesktop(item, index));
  }

  /// 单曲详情（用于分享链接即点即播）。
  Future<Song?> fetchSongByMid(
    String songMid, {
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final mid = songMid.trim();
    if (mid.isEmpty) return null;
    try {
      final uri = Uri.https('c.y.qq.com', '/v8/fcg-bin/fcg_play_single_song.fcg',
          <String, String>{'songmid': mid, 'format': 'json'});
      final decoded = await _getJson(
        uri,
        config: config,
        referer: 'http://m.y.qq.com',
        userAgent: _iphoneUserAgent,
      );
      final list = _asList(decoded['data']);
      if (list.isEmpty) return null;
      return _songFromDetail(_asMap(list.first), 0);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 歌单 / 专辑 / 榜单目录
  // ---------------------------------------------------------------------------

  Future<List<QQMusicCollection>> searchPlaylists(
    String keyword, {
    int page = 1,
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return fetchRecommendedPlaylists(config: config);
    final safePage = page < 1 ? 1 : page;
    final uri = Uri.https(
      'c.y.qq.com',
      '/soso/fcgi-bin/client_music_search_songlist',
      <String, String>{
        'query': query,
        'page_no': '${safePage - 1}',
        'num_per_page': '$pageSize',
        'format': 'json',
        'remoteplace': 'txt.yqq.playlist',
        'flag_qc': '0',
      },
    );
    final decoded = await _getJson(
      uri,
      config: config,
      referer: 'https://y.qq.com/portal/search.html',
      userAgent: _desktopUserAgent,
    );
    final list = _asList(_dig(decoded, 'data', 'list'));
    return list
        .map(_asMap)
        .map((item) => QQMusicCollection(
              id: _str(item['dissid']),
              kind: QQMusicCollectionKind.playlist,
              title: _str(item['dissname']),
              subtitle: _playlistSubtitle(item),
              coverUrl: _https(_str(item['imgurl'])),
              songCount: _int(item['song_count']),
              description: _str(item['introduction']),
            ))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  Future<List<QQMusicCollection>> searchAlbums(
    String keyword, {
    int page = 1,
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return const <QQMusicCollection>[];
    final safePage = page < 1 ? 1 : page;
    final uri = Uri.https('c.y.qq.com', '/soso/fcgi-bin/search_for_qq_cp',
        <String, String>{
          'w': query,
          'format': 'json',
          'p': '$safePage',
          'n': '$pageSize',
          't': '8',
        });
    final decoded = await _getJson(
      uri,
      config: config,
      referer: 'https://y.qq.com/portal/search.html',
      userAgent: _desktopUserAgent,
    );
    final list = _asList(_dig(decoded, 'data', 'album', 'list'));
    if (list.isNotEmpty) {
      return list
          .map(_asMap)
          .map((item) => QQMusicCollection(
                id: _str(item['albumMID']),
                kind: QQMusicCollectionKind.album,
                title: _str(item['albumName']),
                subtitle: _str(item['singerName']),
                coverUrl: _coverUrl(_str(item['albumMID'])),
                description: _str(item['publicTime']),
              ))
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList();
    }
    return _desktopAlbumSearch(query, safePage, config);
  }

  Future<List<QQMusicCollection>> _desktopAlbumSearch(
    String keyword,
    int page,
    QQMusicConfig config,
  ) async {
    try {
      final body = <String, dynamic>{
        'comm': <String, dynamic>{'ct': 19, 'cv': 1859, 'uin': 0, 'format': 'json'},
        'req': <String, dynamic>{
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicDesktop',
          'param': <String, dynamic>{
            'search_type': 2,
            'query': keyword,
            'page_num': page,
            'num_per_page': pageSize,
          },
        },
      };
      final decoded = await _postMusicu(body, config: config);
      final list = _asList(_dig(decoded, 'req', 'data', 'body', 'album', 'list'));
      return list
          .map(_asMap)
          .map((item) => QQMusicCollection(
                id: _str(item['albumMID'] ?? item['albumMid'] ?? item['mid']),
                kind: QQMusicCollectionKind.album,
                title: _str(item['albumName'] ?? item['name']),
                subtitle: _str(item['singerName']),
                coverUrl: _coverUrl(
                    _str(item['albumMID'] ?? item['albumMid'] ?? item['mid'])),
              ))
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList();
    } catch (_) {
      return const <QQMusicCollection>[];
    }
  }

  /// 推荐歌单（go-music-dl 的「每日推荐」即此接口）。
  Future<List<QQMusicCollection>> fetchRecommendedPlaylists({
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    try {
      final body = <String, dynamic>{
        'comm': <String, dynamic>{'ct': 24},
        'recomPlaylist': <String, dynamic>{
          'method': 'get_hot_recommend',
          'module': 'playlist.HotRecommendServer',
          'param': <String, dynamic>{'async': 1, 'cmd': 2},
        },
      };
      final decoded = await _postMusicu(body, config: config);
      final list = _asList(_dig(decoded, 'recomPlaylist', 'data', 'v_hot'));
      if (list.isNotEmpty) {
        return list
            .map(_asMap)
            .map((item) => QQMusicCollection(
                  id: _str(item['content_id']),
                  kind: QQMusicCollectionKind.playlist,
                  title: _str(item['title']),
                  subtitle: _playlistSubtitle(item),
                  coverUrl: _https(_str(item['cover'])),
                  songCount: _int(item['song_cnt'] ?? item['song_count']),
                  badge: '推荐',
                  description: _str(item['username']),
                ))
            .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // 落到官方分类歌单兜底。
    }
    return fetchCategoryPlaylists('', config: config);
  }

  /// 官方歌单分类。
  Future<List<QQMusicCategory>> fetchPlaylistCategories({
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final uri = Uri.https('c.y.qq.com',
        '/splcloud/fcgi-bin/fcg_get_diss_tag_conf.fcg', <String, String>{
      'format': 'json',
      'inCharset': 'utf8',
      'outCharset': 'utf-8',
    });
    final decoded = await _getJson(
      uri,
      config: config,
      referer: 'https://y.qq.com/',
      userAgent: _desktopUserAgent,
    );
    final categories = <QQMusicCategory>[
      const QQMusicCategory(id: '', name: '全部', group: '全部'),
    ];
    for (final group in _asList(_dig(decoded, 'data', 'categories'))) {
      final groupMap = _asMap(group);
      final groupName = _str(groupMap['categoryGroupName']);
      for (final raw in _asList(groupMap['items'])) {
        final item = _asMap(raw);
        final id = _str(item['categoryId']);
        final name = _str(item['categoryName']);
        if (name.isEmpty || id.isEmpty || id == '0' || id == '10000000') continue;
        if (_int(item['usable']) == 0) continue;
        categories.add(QQMusicCategory(id: id, name: name, group: groupName));
      }
    }
    return categories;
  }

  /// 分类歌单（空 categoryId = 全部）。
  Future<List<QQMusicCollection>> fetchCategoryPlaylists(
    String categoryId, {
    int page = 1,
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final safePage = page < 1 ? 1 : page;
    final offset = (safePage - 1) * pageSize;
    final uri = Uri.https('c.y.qq.com',
        '/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg', <String, String>{
      'picmid': '1',
      'rnd': '0.1',
      'g_tk': '${QQMusicService.calculateGtk(config.authKey)}',
      'loginUin': '0',
      'hostUin': '0',
      'format': 'json',
      'inCharset': 'utf8',
      'outCharset': 'utf-8',
      'notice': '0',
      'platform': 'yqq.json',
      'needNewCode': '0',
      'categoryId': categoryId.isEmpty ? '10000000' : categoryId,
      'sortId': '5',
      'sin': '$offset',
      'ein': '${offset + pageSize - 1}',
    });
    final decoded = await _getJson(
      uri,
      config: config,
      referer: 'https://y.qq.com/',
      userAgent: _desktopUserAgent,
    );
    final list = _asList(_dig(decoded, 'data', 'list'));
    return list
        .map(_asMap)
        .map((item) => QQMusicCollection(
              id: _str(item['dissid']),
              kind: QQMusicCollectionKind.playlist,
              title: _str(item['dissname']),
              subtitle: _playlistSubtitle(item),
              coverUrl: _https(_str(item['imgurl'])),
              songCount: _int(item['song_count'] ?? item['song_num']),
              description: _str(item['introduction']),
            ))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  /// 榜单目录。
  Future<List<QQMusicCollection>> fetchCharts({
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    try {
      final payload = <String, dynamic>{
        'comm': <String, dynamic>{
          'cv': 4747474,
          'ct': 24,
          'format': 'json',
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'notice': 0,
          'platform': 'yqq.json',
          'needNewCode': 1,
          'uin': '0',
          'g_tk_new_20200303': 5381,
          'g_tk': 5381,
        },
        'topList': <String, dynamic>{
          'module': 'musicToplist.ToplistInfoServer',
          'method': 'GetAll',
          'param': <String, dynamic>{},
        },
      };
      final uri = Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', <String, String>{
        'format': 'json',
        'data': jsonEncode(payload),
      });
      final decoded = await _getJson(
        uri,
        config: config,
        referer: 'https://y.qq.com/',
        userAgent: _desktopUserAgent,
      );
      final result = <QQMusicCollection>[];
      for (final rawGroup in _asList(_dig(decoded, 'topList', 'data', 'group'))) {
        final group = _asMap(rawGroup);
        final groupName = _str(group['groupName']);
        for (final raw in _asList(group['toplist'])) {
          final item = _asMap(raw);
          final id = _str(item['topId']);
          final title = _str(item['title']);
          if (id.isEmpty || title.isEmpty || _int(item['recType']) == 10010) {
            continue;
          }
          result.add(QQMusicCollection(
            id: id,
            kind: QQMusicCollectionKind.chart,
            title: title,
            subtitle: _str(item['updateTips'] ?? item['period']),
            coverUrl: _chartCover(item),
            songCount: _int(item['totalNum']),
            description: _cleanHtml(_str(item['intro'])),
            badge: groupName,
          ));
        }
      }
      if (result.isNotEmpty) return result;
    } catch (_) {
      // 落到内置热歌榜兜底。
    }
    return const <QQMusicCollection>[
      QQMusicCollection(
        id: '26',
        kind: QQMusicCollectionKind.chart,
        title: '热歌榜',
        subtitle: 'QQ 音乐',
        badge: '热门',
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 合集详情
  // ---------------------------------------------------------------------------

  Future<QQMusicCollectionDetail?> fetchCollectionDetail(
    QQMusicCollection collection, {
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    switch (collection.kind) {
      case QQMusicCollectionKind.playlist:
        return _fetchPlaylistDetail(collection, config);
      case QQMusicCollectionKind.album:
        return _fetchAlbumDetail(collection, config);
      case QQMusicCollectionKind.chart:
        final songs = await fetchChartSongs(collection.id, config: config);
        if (songs.isEmpty) return null;
        return QQMusicCollectionDetail(collection: collection, songs: songs);
    }
  }

  Future<QQMusicCollectionDetail?> _fetchPlaylistDetail(
    QQMusicCollection collection,
    QQMusicConfig config,
  ) async {
    Object? lastError;
    for (final base in _playlistDetailUrls) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: <String, String>{
          'type': '1',
          'json': '1',
          'utf8': '1',
          'onlysong': '0',
          'disstid': collection.id,
          'format': 'json',
          'g_tk': '${QQMusicService.calculateGtk(config.authKey)}',
          'loginUin': '0',
          'hostUin': '0',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
          'notice': '0',
          'platform': 'yqq',
          'needNewCode': '0',
        });
        final decoded = await _getJson(
          uri,
          config: config,
          referer: 'https://y.qq.com/',
          userAgent: _desktopUserAgent,
        );
        final cdlist = _asList(decoded['cdlist']);
        if (cdlist.isEmpty) {
          lastError = '歌单为空或已下架';
          continue;
        }
        final cd = _asMap(cdlist.first);
        final rawSongs = _asList(cd['songlist']);
        if (rawSongs.isEmpty) {
          lastError = '歌单暂无曲目';
          continue;
        }
        final songs =
            _buildSongs(rawSongs, (item, index) => _songFromLegacy(item, index));
        if (songs.isEmpty) {
          lastError = '歌单曲目无法解析';
          continue;
        }
        final enriched = collection.copyWith(
          title: _str(cd['dissname']).isEmpty
              ? collection.title
              : _str(cd['dissname']),
          subtitle: _str(cd['nickname']),
          coverUrl: _https(_str(cd['logo'])),
          songCount: _int(cd['songnum']) > 0 ? _int(cd['songnum']) : songs.length,
          description: _str(cd['desc']),
        );
        return QQMusicCollectionDetail(collection: enriched, songs: songs);
      } catch (error) {
        lastError = error;
      }
    }

    // 最后回退到本项目既有的收藏同步取数链路（musicu.fcg 分页实现）。
    try {
      final service = QQMusicService(client: _client);
      final payload = await service.syncFavoritePlaylist(
        config.copyWith(dissid: collection.id),
      );
      if (payload.songs.isNotEmpty) {
        return QQMusicCollectionDetail(
          collection: collection.copyWith(
            title: payload.playlistName.isEmpty
                ? collection.title
                : payload.playlistName,
            subtitle: payload.nickname,
            songCount: payload.songs.length,
          ),
          songs: payload.songs,
        );
      }
    } catch (_) {
      // 保留原始错误。
    }
    throw QQMusicDiscoveryException(
      lastError is QQMusicDiscoveryException
          ? lastError.message
          : '无法获取该歌单曲目，请检查链接或配置 Cookie',
    );
  }

  Future<QQMusicCollectionDetail?> _fetchAlbumDetail(
    QQMusicCollection collection,
    QQMusicConfig config,
  ) async {
    final infoBody = <String, dynamic>{
      'comm': <String, dynamic>{'ct': 24, 'cv': 0},
      'album': <String, dynamic>{
        'module': 'music.musichallAlbum.AlbumInfoServer',
        'method': 'GetAlbumDetail',
        'param': <String, dynamic>{'albumMid': collection.id},
      },
    };
    QQMusicCollection enriched = collection;
    try {
      final decoded = await _postMusicu(infoBody, config: config);
      final info = _asMap(_dig(decoded, 'album', 'data', 'basicInfo'));
      final name = _str(info['albumName']);
      final artists = _asList(_dig(decoded, 'album', 'data', 'singer', 'singerList'))
          .map(_asMap)
          .map((item) => _str(item['name']))
          .where((item) => item.isNotEmpty)
          .join('、');
      if (name.isNotEmpty) {
        enriched = collection.copyWith(
          title: name,
          subtitle: artists,
          description: _str(info['desc']),
        );
      }
    } catch (_) {
      // 专辑信息接口失败时仍尝试拉曲目。
    }

    final songs = <Song>[];
    const batchSize = 100;
    for (var begin = 0; begin < 500; begin += batchSize) {
      final body = <String, dynamic>{
        'comm': <String, dynamic>{'ct': 24, 'cv': 0},
        'album': <String, dynamic>{
          'module': 'music.musichallAlbum.AlbumSongList',
          'method': 'GetAlbumSongList',
          'param': <String, dynamic>{
            'albumMid': collection.id,
            'begin': begin,
            'num': batchSize,
            'order': 2,
          },
        },
      };
      final decoded = await _postMusicu(body, config: config);
      final rawSongs = _asList(_dig(decoded, 'album', 'data', 'songList'));
      if (rawSongs.isEmpty) break;
      for (final raw in rawSongs) {
        final songInfo = _asMap(_asMap(raw)['songInfo']);
        final song = _songFromAlbum(songInfo, songs.length);
        if (song != null) songs.add(song);
      }
      final total = _int(_dig(decoded, 'album', 'data', 'totalNum'));
      if (rawSongs.length < batchSize || (total > 0 && songs.length >= total)) {
        break;
      }
    }
    if (songs.isEmpty) {
      throw QQMusicDiscoveryException('未能获取该专辑曲目');
    }
    return QQMusicCollectionDetail(
      collection: enriched.copyWith(songCount: songs.length),
      songs: songs,
    );
  }

  /// 榜单曲目，最多取前 100 首。
  Future<List<Song>> fetchChartSongs(
    String topId, {
    int page = 1,
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final id = topId.trim();
    if (id.isEmpty) return const <Song>[];
    final safePage = page < 1 ? 1 : page;
    final begin = (safePage - 1) * 50;
    final uri = Uri.https('c.y.qq.com', '/v8/fcg-bin/fcg_v8_toplist_cp.fcg',
        <String, String>{
          'topid': id,
          'song_begin': '$begin',
          'song_num': '50',
          'format': 'json',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
          'notice': '0',
          'platform': 'h5',
          'needNewCode': '1',
          'tpl': '3',
          'page': 'detail',
          'type': 'top',
        });
    final decoded = await _getJson(
      uri,
      config: config,
      referer: 'https://y.qq.com/',
      userAgent: _iphoneUserAgent,
    );
    final rawSongs = _asList(decoded['songlist']);
    final songs = <Song>[];
    for (final raw in rawSongs) {
      final wrapper = _asMap(raw);
      final data = _asMap(wrapper['data']);
      final rank = _int(wrapper['cur_count']) > 0
          ? _int(wrapper['cur_count'])
          : songs.length + begin + 1;
      final song = _songFromLegacy(data, songs.length, rank: rank);
      if (song != null) songs.add(song);
    }
    return songs;
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  Map<String, String> _headers(
    QQMusicConfig config, {
    String? referer,
    String? userAgent,
    bool jsonBody = false,
  }) {
    final headers = <String, String>{
      'User-Agent': userAgent ?? _desktopUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': ?referer,
      if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
    };
    final cookie = config.cookie.trim();
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required QQMusicConfig config,
    String? referer,
    String? userAgent,
  }) async {
    final response = await _client
        .get(uri, headers: _headers(config, referer: referer, userAgent: userAgent))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw QQMusicDiscoveryException(
          'QQ 音乐接口返回 HTTP ${response.statusCode}');
    }
    return _decode(response.body);
  }

  Future<Map<String, dynamic>> _postMusicu(
    Map<String, dynamic> body, {
    required QQMusicConfig config,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_musicuUrl),
          headers: _headers(
            config,
            referer: 'https://y.qq.com/',
            userAgent: _desktopUserAgent,
            jsonBody: true,
          ),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw QQMusicDiscoveryException(
          'QQ 音乐接口返回 HTTP ${response.statusCode}');
    }
    return _decode(response.body);
  }

  /// 兼容 plain JSON 与 `callback({...})` JSONP 外壳。
  Map<String, dynamic> _decode(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const QQMusicDiscoveryException('QQ 音乐接口返回空内容');
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    final text = start >= 0 && end > start
        ? trimmed.substring(start, end + 1)
        : trimmed;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const QQMusicDiscoveryException('QQ 音乐接口返回内容无法解析');
    }
    throw const QQMusicDiscoveryException('QQ 音乐接口返回内容无法解析');
  }

  // ---------------------------------------------------------------------------
  // Song 构造
  // ---------------------------------------------------------------------------

  List<Song> _buildSongs(
    List<dynamic> raw,
    Song? Function(Map<String, dynamic> item, int index) builder,
  ) {
    final songs = <Song>[];
    for (var i = 0; i < raw.length; i++) {
      final song = builder(_asMap(raw[i]), songs.length);
      if (song != null) songs.add(song);
    }
    return songs;
  }

  /// `search_for_qq_cp` / 歌单 `songlist` / 榜单 `data` 的字段命名。
  Song? _songFromLegacy(
    Map<String, dynamic> item,
    int order, {
    int? rank,
  }) {
    final mid = _str(item['songmid'] ?? item['mid']);
    if (mid.isEmpty) return null;
    final albumMid = _str(item['albummid'] ?? item['albumMid']);
    final mediaMid = _str(item['strMediaMid'] ?? item['media_mid']);
    final pay = _asMap(item['pay']);
    return Song(
      id: 'qq_$mid',
      title: _str(item['songname'] ?? item['name']),
      artist: _joinArtists(item['singer']),
      album: _str(item['albumname'] ?? item['albumName']),
      durationMs: _int(item['interval']) * 1000,
      filePath: 'qqmusic://$mid',
      albumArtUri: _coverUrl(albumMid),
      dateAdded: DateTime.now().subtract(Duration(seconds: order)),
      trackNumber: rank,
      source: SongSource.online,
      qqSongMid: mid,
      qqSongId: _nullableInt(item['songid'] ?? item['id']),
      qqMediaMid: mediaMid.isEmpty ? mid : mediaMid,
      isVip: _int(pay['payplay'] ?? pay['pay_play']) == 1,
    );
  }

  /// desktop `musicu.fcg` 搜索的字段命名。
  Song? _songFromDesktop(Map<String, dynamic> item, int order) {
    final mid = _str(item['mid']);
    if (mid.isEmpty) return null;
    final album = _asMap(item['album']);
    final file = _asMap(item['file']);
    final pay = _asMap(item['pay']);
    final albumMid = _str(album['mid']);
    final mediaMid = _str(file['media_mid'] ?? file['strMediaMid']);
    return Song(
      id: 'qq_$mid',
      title: _str(item['name']),
      artist: _joinArtists(item['singer']),
      album: _str(album['name']),
      durationMs: _int(item['interval']) * 1000,
      filePath: 'qqmusic://$mid',
      albumArtUri: _coverUrl(albumMid),
      dateAdded: DateTime.now().subtract(Duration(seconds: order)),
      source: SongSource.online,
      qqSongMid: mid,
      qqSongId: _nullableInt(item['id']),
      qqMediaMid: mediaMid.isEmpty ? mid : mediaMid,
      isVip: _int(pay['pay_play']) == 1,
    );
  }

  /// 专辑曲目 `songList[].songInfo` 的字段命名。
  Song? _songFromAlbum(Map<String, dynamic> songInfo, int order) {
    final mid = _str(songInfo['mid']);
    if (mid.isEmpty) return null;
    final album = _asMap(songInfo['album']);
    final file = _asMap(songInfo['file']);
    final pay = _asMap(songInfo['pay']);
    final albumMid = _str(album['mid']);
    final mediaMid = _str(file['media_mid'] ?? file['strMediaMid']);
    return Song(
      id: 'qq_$mid',
      title: _str(songInfo['name']),
      artist: _joinArtists(songInfo['singer']),
      album: _str(album['name']),
      durationMs: _int(songInfo['interval']) * 1000,
      filePath: 'qqmusic://$mid',
      albumArtUri: _coverUrl(albumMid),
      dateAdded: DateTime.now().subtract(Duration(seconds: order)),
      trackNumber: order + 1,
      source: SongSource.online,
      qqSongMid: mid,
      qqSongId: _nullableInt(songInfo['id']),
      qqMediaMid: mediaMid.isEmpty ? mid : mediaMid,
      isVip: _int(pay['pay_play']) == 1,
    );
  }

  /// `fcg_play_single_song.fcg` 的字段命名。
  Song? _songFromDetail(Map<String, dynamic> item, int order) {
    final mid = _str(item['mid']);
    if (mid.isEmpty) return null;
    final album = _asMap(item['album']);
    final albumMid = _str(album['mid']);
    return Song(
      id: 'qq_$mid',
      title: _str(item['name']),
      artist: _joinArtists(item['singer']),
      album: _str(album['name']),
      durationMs: _int(item['interval']) * 1000,
      filePath: 'qqmusic://$mid',
      albumArtUri: _coverUrl(albumMid),
      dateAdded: DateTime.now().subtract(Duration(seconds: order)),
      source: SongSource.online,
      qqSongMid: mid,
      qqSongId: _nullableInt(item['id']),
      qqMediaMid: mid,
    );
  }

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  static String _coverUrl(String albumMid) => albumMid.isEmpty
      ? ''
      : 'https://y.gtimg.cn/music/photo_new/T002R800x800M000$albumMid.jpg';

  static String _https(String url) => url.startsWith('http://')
      ? 'https://${url.substring(7)}'
      : url;

  static String _playlistSubtitle(Map<String, dynamic> item) {
    final count = _int(item['song_count'] ?? item['song_cnt'] ?? item['song_num']);
    final listens = _int(item['listennum'] ?? item['listen_num']);
    final creator = _str(_asMap(item['creator'])['name'] ?? item['username']);
    final parts = <String>[
      if (count > 0) '$count 首',
      if (listens > 0) '${_formatListens(listens)} 次播放',
      if (creator.isNotEmpty) creator,
    ];
    return parts.join(' · ');
  }

  static String _formatListens(int value) {
    if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
    return '$value';
  }

  static String _chartCover(Map<String, dynamic> item) {
    for (final key in const <String>[
      'frontPicUrl',
      'mbFrontPicUrl',
      'headPicUrl',
      'mbHeadPicUrl',
      'musichallPicUrl',
    ]) {
      final url = _str(item[key]);
      if (url.isNotEmpty) return _https(url);
    }
    return '';
  }

  static String _cleanHtml(String text) => text
      .replaceAll(RegExp(r'</?br\s*/?>', caseSensitive: false), ' ')
      .trim();

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  static dynamic _dig(Map<String, dynamic> map, String key,
      [String? key2, String? key3, String? key4, String? key5, String? key6]) {
    var current = map[key];
    for (final next in <String?>[key2, key3, key4, key5, key6]) {
      if (next == null) break;
      current = _asMap(current)[next];
    }
    return current;
  }

  static String _str(dynamic value) =>
      value == null ? '' : value.toString();

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _nullableInt(dynamic value) {
    final parsed = _int(value);
    return parsed > 0 ? parsed : null;
  }

  static String _joinArtists(dynamic singers) {
    if (singers is! List || singers.isEmpty) return '';
    return singers
        .map(_asMap)
        .map((item) => _str(item['name']))
        .where((item) => item.isNotEmpty)
        .join('、');
  }
}
