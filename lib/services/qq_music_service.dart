import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/listening_stats.dart';
import '../models/qq_music_config.dart';
import '../models/song.dart';

/// 拉取 QQ 音乐「我喜欢」歌单的结果封装。
class QQMusicSyncPayload {
  final String uin;
  final String dissid;
  final String nickname;
  final String playlistName;
  final List<Song> songs;

  const QQMusicSyncPayload({
    required this.uin,
    required this.dissid,
    required this.nickname,
    required this.playlistName,
    required this.songs,
  });
}

/// QQ 音乐接口出现可诊断的业务异常（如歌单未公开、QQ号无效、网络超时）。
class QQMusicApiException implements Exception {
  final String message;
  const QQMusicApiException(this.message);

  @override
  String toString() => message;
}

/// 纯 Dart 的 QQ 音乐服务：负责解析用户「我喜欢」歌单、分页拉取收藏曲目、
/// 实时获取在线播放流 (`vkey`/`purl`)、按 `songMid` 获取歌词以及云端红心同步。
class QQMusicService {
  final http.Client _client;
  final bool _ownsClient;

  /// PC 私有通道要求的设备标识（32 位大写十六进制）；同一账号应保持稳定。
  final String desktopGuid;

  QQMusicService({http.Client? client, String? desktopGuid})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      desktopGuid = (desktopGuid != null && desktopGuid.trim().isNotEmpty)
          ? desktopGuid.trim().toUpperCase()
          : const Uuid().v4().replaceAll('-', '').toUpperCase();

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static const String _musicuUrl = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const String _desktopMusicuUrl =
      'https://u6.y.qq.com/cgi-bin/musicu.fcg';
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const String _desktopUserAgent =
      'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)';

  /// 计算 QQ 音乐接口所需的 `g_tk` 签名（DJB2 哈希）。
  static int calculateGtk(String authKey) {
    var hash = 5381;
    for (var i = 0; i < authKey.length; i++) {
      hash += (hash << 5) + authKey.codeUnitAt(i);
    }
    return hash & 0x7fffffff;
  }

  Map<String, String> _buildHeaders(QQMusicConfig config, {bool isJson = true}) {
    final headers = <String, String>{
      'Referer': 'https://y.qq.com/',
      'Origin': 'https://y.qq.com',
      'User-Agent': _userAgent,
      if (isJson) 'Content-Type': 'application/json; charset=utf-8',
    };

    final cookieParts = <String>[];
    if (config.cookie.trim().isNotEmpty) {
      cookieParts.add(config.cookie.trim());
    }
    final uin = config.effectiveUin;
    if (uin.isNotEmpty && !config.cookie.contains('uin=')) {
      cookieParts.add('uin=o$uin');
    }
    if (cookieParts.isNotEmpty) {
      headers['Cookie'] = cookieParts.join('; ');
    }
    return headers;
  }

  /// 剥离可能包裹在响应体外的 JSONP 回调壳（如 `jsonCallback({...})`）。
  static String stripJsonp(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }
    final match = RegExp(
      r'^[a-zA-Z0-9_.]+\((.*)\)\s*;?\s*$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return trimmed;
  }

  /// 同步用户的「我喜欢」收藏歌单。
  ///
  /// 流程：
  /// 1. 若 [config.dissid] 已指定，直接拉取该歌单；
  /// 2. 否则用 [config.effectiveUin] 查询个人主页解析「我喜欢」的 `dissid`；
  /// 3. 若用户把纯数字歌单 ID 填进了 QQ 号栏（个人主页未返回歌单），自动回退将该数字作为 `dissid` 尝试拉取。
  Future<QQMusicSyncPayload> syncFavoritePlaylist(QQMusicConfig config) async {
    var uin = config.effectiveUin;
    var dissid = config.dissid.trim();
    var nickname = config.nickname.trim();

    if (dissid.isEmpty) {
      if (uin.isEmpty) {
        throw const QQMusicApiException('请先填写 QQ 号、「我喜欢」歌单链接或有效 Cookie');
      }
      final resolved = await _resolveFavoriteDissidByUin(uin, config);
      if (resolved != null) {
        dissid = resolved.dissid;
        if (resolved.nickname.isNotEmpty) {
          nickname = resolved.nickname;
        }
      }
    }

    // 若通过 QQ 号未能解析出 dissid，但用户输入的是纯数字（可能直接粘贴了歌单 ID），
    // 尝试直接将该数字作为 dissid 请求歌单详情。
    if (dissid.isEmpty && uin.isNotEmpty) {
      final directAttempt = await _fetchPlaylistSongsByDissid(uin, config);
      if (directAttempt != null) {
        return QQMusicSyncPayload(
          uin: '',
          dissid: uin,
          nickname: directAttempt.nickname.isNotEmpty
              ? directAttempt.nickname
              : nickname,
          playlistName: directAttempt.playlistName,
          songs: directAttempt.songs,
        );
      }
      throw const QQMusicApiException(
        '无法获取该 QQ 号的「我喜欢」歌单。请确认 QQ 音乐中已开启「个人主页公开 -> 我喜欢公开」，或直接粘贴歌单分享链接 / 配置 Cookie。',
      );
    }

    final result = await _fetchPlaylistSongsByDissid(dissid, config);
    if (result == null) {
      // 如果之前缓存的 dissid 失效且有 uin，重新解析一次 dissid
      if (uin.isNotEmpty && config.dissid.isNotEmpty) {
        final refreshed = await _resolveFavoriteDissidByUin(uin, config);
        if (refreshed != null &&
            refreshed.dissid.isNotEmpty &&
            refreshed.dissid != dissid) {
          final retry = await _fetchPlaylistSongsByDissid(
            refreshed.dissid,
            config,
          );
          if (retry != null) {
            return QQMusicSyncPayload(
              uin: uin,
              dissid: refreshed.dissid,
              nickname: retry.nickname.isNotEmpty
                  ? retry.nickname
                  : refreshed.nickname,
              playlistName: retry.playlistName,
              songs: retry.songs,
            );
          }
        }
      }
      throw const QQMusicApiException(
        '拉取「我喜欢」歌单失败，歌单可能被设为私密或网络异常。建议粘贴「我喜欢」歌单分享链接或配置 Cookie。',
      );
    }

    return QQMusicSyncPayload(
      uin: uin,
      dissid: dissid,
      nickname: result.nickname.isNotEmpty ? result.nickname : nickname,
      playlistName: result.playlistName,
      songs: result.songs,
    );
  }

  /// 通过 QQ 号 (`uin`) 查询用户主页以获取「我喜欢」歌单的 `dissid` 与昵称。
  Future<({String dissid, String nickname})?> _resolveFavoriteDissidByUin(
    String uin,
    QQMusicConfig config,
  ) async {
    final gtk = calculateGtk(config.authKey);
    final uri = Uri.parse(
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg'
      '?plat=yqq.json&inCharset=utf8&outCharset=utf-8&cid=205360838'
      '&userid=$uin&reqfrom=1&g_tk=$gtk&loginUin=$uin&hostUin=0&format=json',
    );

    try {
      final resp = await _client
          .get(uri, headers: _buildHeaders(config, isJson: false))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = stripJsonp(utf8.decode(resp.bodyBytes, allowMalformed: true));
        final decoded = json.decode(body);
        if (decoded is Map) {
          final data = decoded['data'];
          if (data is Map) {
            final creator = data['creator'];
            final nick = (creator is Map ? creator['nick'] as String? : null) ?? '';
            final mymusic = data['mymusic'];
            if (mymusic is List) {
              for (final entry in mymusic) {
                if (entry is Map) {
                  final id = entry['id']?.toString() ?? '';
                  final num0 = entry['num0']?.toString() ?? '';
                  if (id.isNotEmpty && id != '0') {
                    return (dissid: id, nickname: nick);
                  }
                  if (num0.isNotEmpty && num0 != '0') {
                    return (dissid: num0, nickname: nick);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// 按歌单 `dissid` 分页拉取完整曲目列表（依次尝试 `fcg_ucc_getcdinfo_byids_cp.fcg` 与 `musicu.fcg`）。
  Future<({String nickname, String playlistName, List<Song> songs})?>
      _fetchPlaylistSongsByDissid(String dissid, QQMusicConfig config) async {
    const pageSize = 500;
    final allSongs = <Song>[];
    final seenMids = <String>{};
    var nickname = '';
    var playlistName = '我喜欢';
    var songBegin = 0;
    var totalExpected = -1;

    while (true) {
      final page = await _fetchPlaylistPageCgi(
            dissid: dissid,
            config: config,
            songBegin: songBegin,
            songNum: pageSize,
          ) ??
          await _fetchPlaylistPageMusicu(
            dissid: dissid,
            config: config,
            songBegin: songBegin,
            songNum: pageSize,
          );

      if (page == null) {
        if (allSongs.isNotEmpty) break;
        return null;
      }

      if (page.nickname.isNotEmpty) nickname = page.nickname;
      if (page.playlistName.isNotEmpty) playlistName = page.playlistName;
      if (totalExpected < 0 && page.totalCount > 0) {
        totalExpected = page.totalCount;
      }

      var addedInPage = 0;
      for (final song in page.songs) {
        final key = song.qqSongMid ?? song.id;
        if (seenMids.add(key)) {
          allSongs.add(song);
          addedInPage++;
        }
      }

      if (page.songs.length < pageSize ||
          addedInPage == 0 ||
          (totalExpected > 0 && allSongs.length >= totalExpected) ||
          songBegin >= 5000) {
        break;
      }
      songBegin += page.songs.length;
    }

    return (
      nickname: nickname,
      playlistName: playlistName,
      songs: allSongs,
    );
  }

  Future<
    ({
      String nickname,
      String playlistName,
      int totalCount,
      List<Song> songs,
    })?
  > _fetchPlaylistPageCgi({
    required String dissid,
    required QQMusicConfig config,
    required int songBegin,
    required int songNum,
  }) async {
    final uin = config.effectiveUin.isEmpty ? '0' : config.effectiveUin;
    final gtk = calculateGtk(config.authKey);
    final uri = Uri.parse(
      'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg'
      '?type=1&json=1&utf8=1&onlysong=0&new_format=1'
      '&disstid=$dissid&g_tk=$gtk&loginUin=$uin&hostUin=0'
      '&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
      '&platform=yqq.json&needNewCode=0'
      '&song_begin=$songBegin&song_num=$songNum',
    );

    try {
      final resp = await _client
          .get(uri, headers: _buildHeaders(config, isJson: false))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final body = stripJsonp(utf8.decode(resp.bodyBytes, allowMalformed: true));
      final decoded = json.decode(body);
      if (decoded is! Map) return null;

      final cdlist = decoded['cdlist'];
      if (cdlist is! List || cdlist.isEmpty) return null;
      final firstCd = cdlist.first;
      if (firstCd is! Map) return null;

      final rawSongs = firstCd['songlist'];
      if (rawSongs is! List) return null;

      final dissname = (firstCd['dissname'] as String?)?.trim() ?? '我喜欢';
      final nick = (firstCd['nickname'] as String?)?.trim() ??
          (firstCd['nick'] as String?)?.trim() ??
          '';
      final totalCount =
          (firstCd['total_song_num'] as num?)?.toInt() ??
          (firstCd['songnum'] as num?)?.toInt() ??
          rawSongs.length;

      final parsedSongs = _parseRawSongList(rawSongs, startOrder: songBegin);
      return (
        nickname: nick,
        playlistName: dissname,
        totalCount: totalCount,
        songs: parsedSongs,
      );
    } catch (_) {
      return null;
    }
  }

  Future<
    ({
      String nickname,
      String playlistName,
      int totalCount,
      List<Song> songs,
    })?
  > _fetchPlaylistPageMusicu({
    required String dissid,
    required QQMusicConfig config,
    required int songBegin,
    required int songNum,
  }) async {
    final disstidInt = int.tryParse(dissid);
    if (disstidInt == null) return null;
    final uinInt = int.tryParse(config.effectiveUin) ?? 0;

    final payload = {
      'comm': {
        'ct': 24,
        'cv': 10000,
        'uin': uinInt,
        'format': 'json',
        if (config.authKey.isNotEmpty) 'authst': config.authKey,
      },
      'req_0': {
        'module': 'music.srfDissInfo.aiDissInfo',
        'method': 'uniform_get_Dissinfo',
        'param': {
          'disstid': disstidInt,
          'enc_host_uin': '',
          'tag': 1,
          'userinfo': 1,
          'song_begin': songBegin,
          'song_num': songNum,
        },
      },
    };

    try {
      final resp = await _client
          .post(
            Uri.parse(_musicuUrl),
            headers: _buildHeaders(config),
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final decoded = json.decode(
        utf8.decode(resp.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      final reqData = decoded['req_0']?['data'];
      if (reqData is! Map) return null;

      final rawSongs = reqData['songlist'];
      if (rawSongs is! List) return null;

      final dirinfo = reqData['dirinfo'];
      final dissname = (dirinfo is Map ? dirinfo['title'] as String? : null)
              ?.trim() ??
          '我喜欢';
      final creator = dirinfo is Map ? dirinfo['creator'] : null;
      final nick =
          (creator is Map ? creator['nick'] as String? : null)?.trim() ?? '';
      final totalCount =
          (reqData['total_song_num'] as num?)?.toInt() ??
          (dirinfo is Map ? (dirinfo['songnum'] as num?)?.toInt() : null) ??
          rawSongs.length;

      final parsedSongs = _parseRawSongList(rawSongs, startOrder: songBegin);
      return (
        nickname: nick,
        playlistName: dissname,
        totalCount: totalCount,
        songs: parsedSongs,
      );
    } catch (_) {
      return null;
    }
  }

  List<Song> _parseRawSongList(
    List<dynamic> rawSongs, {
    int startOrder = 0,
    int defaultPlayCount = 0,
  }) {
    final now = DateTime.now();
    final songs = <Song>[];

    for (var i = 0; i < rawSongs.length; i++) {
      final rawItem = rawSongs[i];
      if (rawItem is! Map) continue;
      final item = rawItem['songInfo'] is Map
          ? rawItem['songInfo'] as Map
          : rawItem['song'] is Map
          ? rawItem['song'] as Map
          : rawItem;

      final songMid =
          (item['mid'] as String?)?.trim() ??
          (item['songmid'] as String?)?.trim() ??
          (rawItem['songmid'] as String?)?.trim() ??
          '';
      if (songMid.isEmpty) continue;

      final songId =
          (item['id'] as num?)?.toInt() ??
          (item['songid'] as num?)?.toInt() ??
          (rawItem['songid'] as num?)?.toInt();

      final title =
          (item['title'] as String?)?.trim() ??
          (item['name'] as String?)?.trim() ??
          (item['songname'] as String?)?.trim() ??
          '未知曲目';

      String artist = '未知歌手';
      final singers = item['singer'];
      if (singers is List && singers.isNotEmpty) {
        final names = singers
            .whereType<Map>()
            .map((s) => (s['name'] as String?)?.trim() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        if (names.isNotEmpty) {
          artist = names.join('/');
        }
      }

      String albumName = '';
      String? albumMid;
      final albumObj = item['album'];
      if (albumObj is Map) {
        albumName = (albumObj['name'] as String?)?.trim() ?? '';
        albumMid = (albumObj['mid'] as String?)?.trim();
      } else {
        albumName = (item['albumname'] as String?)?.trim() ?? '';
        albumMid = (item['albummid'] as String?)?.trim();
      }

      String? mediaMid;
      final fileObj = item['file'];
      if (fileObj is Map) {
        mediaMid = (fileObj['media_mid'] as String?)?.trim();
      }
      mediaMid ??= (item['strMediaMid'] as String?)?.trim();
      if (mediaMid == null || mediaMid.isEmpty) {
        mediaMid = songMid;
      }

      final intervalSec = (item['interval'] as num?)?.toInt() ?? 0;
      final durationMs = intervalSec > 0 ? intervalSec * 1000 : 0;

      String? coverUrl;
      if (albumMid != null &&
          albumMid.isNotEmpty &&
          albumMid != '00000000000000') {
        coverUrl =
            'https://y.gtimg.cn/music/photo_new/T002R800x800M000$albumMid.jpg';
      }

      var isVip = false;
      final payObj = item['pay'];
      if (payObj is Map) {
        final payPlay =
            (payObj['pay_play'] as num?)?.toInt() ??
            (payObj['payplay'] as num?)?.toInt() ??
            0;
        isVip = payPlay == 1;
      }

      final explicitPlayCount =
          (rawItem['cnt'] as num?)?.toInt() ??
          (rawItem['listenCount'] as num?)?.toInt() ??
          (rawItem['listen_count'] as num?)?.toInt() ??
          (rawItem['playcnt'] as num?)?.toInt() ??
          (rawItem['play_count'] as num?)?.toInt() ??
          (rawItem['playCount'] as num?)?.toInt() ??
          (rawItem['count'] as num?)?.toInt() ??
          (item['cnt'] as num?)?.toInt() ??
          (item['listenCount'] as num?)?.toInt() ??
          (item['listen_count'] as num?)?.toInt() ??
          (item['playcnt'] as num?)?.toInt() ??
          (item['play_count'] as num?)?.toInt() ??
          (item['playCount'] as num?)?.toInt() ??
          (item['count'] as num?)?.toInt() ??
          defaultPlayCount;

      songs.add(
        Song(
          id: 'qq_$songMid',
          title: title,
          artist: artist,
          album: albumName,
          durationMs: durationMs,
          filePath: 'qqmusic://$songMid',
          albumArtUri: coverUrl,
          dateAdded: now.subtract(Duration(seconds: startOrder + i)),
          playCount: explicitPlayCount > 0 ? explicitPlayCount : 0,
          isFavorite: true,
          source: SongSource.online,
          qqSongMid: songMid,
          qqSongId: songId,
          qqMediaMid: mediaMid,
          isVip: isVip,
        ),
      );
    }
    return songs;
  }

  /// 实时解析 QQ 音乐歌曲的在线可播放流地址 (`https://.../C400...m4a?vkey=...`)。
  ///
  /// 若配置了 Cookie，优先尝试 `M800` (320kbps MP3) / `M500` (128kbps MP3)，
  /// 否则或降级时请求标准 `C400` M4A 流。
  /// 当因 VIP/版权受限无法获得 `purl` 时返回 `null`。
  Future<String?> resolvePlayUrl({
    required String songMid,
    String? mediaMid,
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final cleanMid = songMid.trim();
    if (cleanMid.isEmpty) return null;
    final targetMediaMid =
        (mediaMid != null && mediaMid.trim().isNotEmpty)
            ? mediaMid.trim()
            : cleanMid;

    // 1. If Cookie is present, try higher quality MP3 first, then fallback to default C400.
    if (config.hasCookie) {
      for (final prefix in const [('M800', 'mp3'), ('M500', 'mp3')]) {
        final filename = '${prefix.$1}$targetMediaMid.${prefix.$2}';
        final url = await _requestVkeyUrl(
          songMid: cleanMid,
          filename: filename,
          config: config,
        );
        if (url != null && url.isNotEmpty) return url;
      }
    }

    // 2. Standard C400 M4A (or default stream without explicit filename)
    final defaultUrl = await _requestVkeyUrl(
      songMid: cleanMid,
      filename: null,
      config: config,
    );
    if (defaultUrl != null && defaultUrl.isNotEmpty) return defaultUrl;

    return _requestVkeyUrl(
      songMid: cleanMid,
      filename: 'C400$targetMediaMid.m4a',
      config: config,
    );
  }

  Future<String?> _requestVkeyUrl({
    required String songMid,
    required String? filename,
    required QQMusicConfig config,
  }) async {
    final uinStr = config.effectiveUin.isEmpty ? '0' : config.effectiveUin;
    final uinInt = int.tryParse(uinStr) ?? 0;

    final param = <String, dynamic>{
      'guid': '10000',
      'songmid': [songMid],
      'songtype': [0],
      'uin': uinStr,
      'loginflag': 1,
      'platform': '20',
      if (filename != null) 'filename': [filename],
    };

    final payload = {
      'comm': {
        'uin': uinInt,
        'format': 'json',
        'ct': 24,
        'cv': 0,
        if (config.authKey.isNotEmpty) 'authst': config.authKey,
      },
      'req_0': {
        'module': 'music.vkey.GetVkey',
        'method': 'CgiGetVkey',
        'param': param,
      },
    };

    try {
      final resp = await _client
          .post(
            Uri.parse(_musicuUrl),
            headers: _buildHeaders(config),
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) return null;
      final decoded = json.decode(
        utf8.decode(resp.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;

      final data = decoded['req_0']?['data'];
      if (data is! Map) return null;

      final midurlinfo = data['midurlinfo'];
      if (midurlinfo is! List || midurlinfo.isEmpty) return null;
      final firstInfo = midurlinfo.first;
      if (firstInfo is! Map) return null;

      final purl = (firstInfo['purl'] as String?)?.trim() ?? '';
      if (purl.isEmpty) return null;

      if (purl.startsWith('http://') || purl.startsWith('https://')) {
        return purl.replaceFirst('http://', 'https://');
      }

      var baseUrl = 'https://ws.stream.qqmusic.qq.com/';
      final sipList = data['sip'];
      if (sipList is List && sipList.isNotEmpty) {
        final validSip = sipList
            .whereType<String>()
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => baseUrl);
        baseUrl = validSip.replaceFirst('http://', 'https://');
      }
      if (!baseUrl.endsWith('/') && !purl.startsWith('/')) {
        baseUrl = '$baseUrl/';
      }
      return '$baseUrl$purl';
    } catch (_) {
      return null;
    }
  }

  /// 根据 `songMid` 直接获取 QQ 音乐 Base64 解码后的 LRC 歌词。
  Future<String?> fetchLyricsBySongMid(
    String songMid, {
    QQMusicConfig config = const QQMusicConfig(),
  }) async {
    final cleanMid = songMid.trim();
    if (cleanMid.isEmpty) return null;

    try {
      final lyricUri = Uri.parse(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
        '?songmid=$cleanMid&format=json&nobase64=0',
      );
      final resp = await _client
          .get(lyricUri, headers: _buildHeaders(config, isJson: false))
          .timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final body = stripJsonp(
          utf8.decode(resp.bodyBytes, allowMalformed: true),
        );
        final lyricData = json.decode(body);
        if (lyricData is Map) {
          final b64Lyric = lyricData['lyric'] as String?;
          if (b64Lyric != null && b64Lyric.isNotEmpty) {
            final decoded = utf8.decode(
              base64.decode(b64Lyric),
              allowMalformed: true,
            );
            if (decoded.trim().isNotEmpty) return decoded;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 将歌曲添加到 QQ 音乐「我喜欢」（需要配置有效 Cookie）。
  Future<bool> addSongToQQFavorites({
    required String songMid,
    required QQMusicConfig config,
  }) async {
    if (!config.hasCookie || songMid.trim().isEmpty) return false;
    final uin = config.effectiveUin;
    if (uin.isEmpty) return false;
    final gtk = calculateGtk(config.authKey);

    final uri = Uri.parse(
      'https://c.y.qq.com/splcloud/fcgi-bin/fcg_music_add2songdir.fcg?g_tk=$gtk',
    );
    final headers = _buildHeaders(config, isJson: false);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    try {
      final resp = await _client
          .post(
            uri,
            headers: headers,
            body: {
              'loginUin': uin,
              'hostUin': '0',
              'format': 'json',
              'inCharset': 'utf8',
              'outCharset': 'utf-8',
              'notice': '0',
              'platform': 'yqq.post',
              'needNewCode': '0',
              'uin': uin,
              'midlist': songMid.trim(),
              'typelist': '13',
              'dirid': config.dirId.toString(),
              'addtype': '',
              'formsender': '4',
              'source': '153',
              'r2': '0',
              'r3': '1',
              'utf8': '1',
              'g_tk': gtk.toString(),
            },
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final body = stripJsonp(
          utf8.decode(resp.bodyBytes, allowMalformed: true),
        );
        final decoded = json.decode(body);
        if (decoded is Map) {
          return (decoded['code'] as num?)?.toInt() == 0;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 将歌曲从 QQ 音乐「我喜欢」移除（需要配置有效 Cookie 且有 `qqSongId`）。
  Future<bool> removeSongFromQQFavorites({
    required int songId,
    required QQMusicConfig config,
  }) async {
    if (!config.hasCookie || songId <= 0) return false;
    final uin = config.effectiveUin;
    if (uin.isEmpty) return false;
    final gtk = calculateGtk(config.authKey);

    final uri = Uri.parse(
      'https://c.y.qq.com/qzone/fcg-bin/fcg_music_delbatchsong.fcg?g_tk=$gtk',
    );
    final headers = _buildHeaders(config, isJson: false);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    try {
      final resp = await _client
          .post(
            uri,
            headers: headers,
            body: {
              'loginUin': uin,
              'hostUin': '0',
              'format': 'json',
              'inCharset': 'utf8',
              'outCharset': 'utf-8',
              'notice': '0',
              'platform': 'yqq.post',
              'needNewCode': '0',
              'uin': uin,
              'dirid': config.dirId.toString(),
              'ids': songId.toString(),
              'types': '3',
              'formsender': '4',
              'flag': '2',
              'from': '3',
              'utf8': '1',
              'g_tk': gtk.toString(),
            },
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final body = stripJsonp(
          utf8.decode(resp.bodyBytes, allowMalformed: true),
        );
        final decoded = json.decode(body);
        if (decoded is Map) {
          return (decoded['code'] as num?)?.toInt() == 0;
        }
      }
    } catch (_) {}
    return false;
  }

  // --- 云端听歌统计（每首曲目播放次数 + 今日有效听歌时长） ---

  /// 拉取 QQ 音乐云端「最近播放」记录（含每首曲目的累计播放次数与最后播放时间）。
  ///
  /// 对应官方 PC 客户端使用的私有接口
  /// `music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo`：曲目在每条记录的
  /// `track`，累计次数在 `listenCnt`，最后播放时间在 `lastTime`（Unix 秒）。
  /// 未登录（无 Cookie）时该接口返回 `code=1000`。
  Future<List<QQMusicCloudHistoryEntry>> fetchCloudListeningHistory(
    QQMusicConfig config,
  ) async {
    if (!config.hasCookie) return const [];

    final data = await _desktopPrivate(
      module: 'music.musicasset.PlayRecentlyRead',
      method: 'GetPlayRecentlyInfo',
      param: const {'requestCnt': 2500, 'type': 2, 'updateTime': 0},
      config: config,
    );
    if (data == null) return const [];

    // 业务层还有一层 `data`：data.data.songList
    final inner = data['data'];
    final rawList = inner is Map ? inner['songList'] : data['songList'];
    if (rawList is! List || rawList.isEmpty) return const [];

    final wrapped = <Map>[];
    final lastPlayedByMid = <String, DateTime>{};
    for (final item in rawList) {
      if (item is! Map) continue;
      final track = item['track'] is Map
          ? item['track'] as Map
          : item['songInfo'] is Map
          ? item['songInfo'] as Map
          : item;
      final mid = (track['mid'] as String?)?.trim() ?? '';
      if (mid.isEmpty) continue;

      final listenCnt = (item['listenCnt'] as num?)?.toInt() ?? 0;
      wrapped.add({...track, 'cnt': listenCnt > 0 ? listenCnt : 1});

      final lastTime =
          (item['lastTime'] as num?)?.toInt() ??
          (item['lasttime'] as num?)?.toInt() ??
          0;
      if (lastTime > 0) {
        lastPlayedByMid[mid] = DateTime.fromMillisecondsSinceEpoch(
          lastTime * 1000,
        );
      }
    }
    if (wrapped.isEmpty) return const [];

    final songs = _parseRawSongList(wrapped, defaultPlayCount: 1);
    return [
      for (final song in songs)
        QQMusicCloudHistoryEntry(
          song: song,
          lastPlayedAt: song.qqSongMid == null
              ? null
              : lastPlayedByMid[song.qqSongMid!],
        ),
    ];
  }

  /// 拉取云端「今日累计有效听歌时间」（秒）。
  ///
  /// 对应 `music.soundPower.SoundPowerSvr.QueryLevelDetailPage`，返回
  /// `data.todayLT`。未登录或接口拒绝时返回 `null`，调用方据此跳过今日时长同步。
  Future<int?> fetchTodayListenSeconds(QQMusicConfig config) async {
    if (!config.hasCookie) return null;
    final uin = config.effectiveUin;

    final payload = {
      'comm': {
        'ct': 11,
        'cv': 14090008,
        'v': 14090008,
        'tmeAppID': 'qqmusic',
        'format': 'json',
        'uin': uin.isEmpty ? '0' : uin,
        if (config.authKey.isNotEmpty) 'authst': config.authKey,
      },
      'req_0': {
        'module': 'music.soundPower.SoundPowerSvr',
        'method': 'QueryLevelDetailPage',
        'param': const <String, dynamic>{},
      },
    };

    try {
      final resp = await _client
          .post(
            Uri.parse(_musicuUrl),
            headers: _buildHeaders(config),
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final decoded = json.decode(
        utf8.decode(resp.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      final data = decoded['req_0']?['data'];
      if (data is! Map) return null;

      final seconds =
          (data['todayLT'] as num?)?.toInt() ??
          (data['today_listen_time'] as num?)?.toInt() ??
          (data['todayListenTime'] as num?)?.toInt();
      if (seconds == null || seconds < 0) return null;
      return seconds;
    } catch (_) {
      return null;
    }
  }

  /// 向 QQ 音乐云端上报一次播放（官方 PC 客户端的「最近播放」写入通道）。
  ///
  /// 对应 `music.musicasset.PlayRecentlyWrite.ReportPlayRecentlyInfo`，参数为
  /// `{"data":[{"id":"<数字songId>","lastTime":<Unix秒>,"listenCnt":1,"type":2}]}`，
  /// 成功时响应 `data.ret == 0`。每次播放开始调用一次；服务端只接受数字
  /// `id`，因此缺少 [Song.qqSongId] 的曲目无法上报（同步云端历史时会自动
  /// 补齐该字段）。
  Future<bool> reportSongPlayback({
    required Song song,
    required QQMusicConfig config,
  }) async {
    if (!config.hasCookie) return false;
    final songId = song.qqSongId ?? 0;
    if (songId <= 0) return false;

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final data = await _desktopPrivate(
      module: 'music.musicasset.PlayRecentlyWrite',
      method: 'ReportPlayRecentlyInfo',
      param: {
        'data': [
          {
            'id': songId.toString(),
            'lastTime': nowSec,
            'listenCnt': 1,
            'type': 2,
          },
        ],
      },
      config: config,
    );
    if (data == null) return false;
    return (data['ret'] as num?)?.toInt() == 0;
  }

  /// PC 私有通道 (`u6.y.qq.com`)：请求键与响应键都是 `module.method`，
  /// 附带登录 Cookie。用于读写当前账号自己的数据（最近播放等）。
  Future<Map?> _desktopPrivate({
    required String module,
    required String method,
    required Map<String, dynamic> param,
    required QQMusicConfig config,
  }) async {
    final key = '$module.$method';
    final uin = config.effectiveUin;
    final cookie = _cookieHeader(config);
    final body = json.encode({
      'comm': {
        'ct': '19',
        'cv': '2276',
        '_channelid': '20',
        '_os_version': '6.2.9200-2',
        'patch': '118',
        'tmeAppID': 'qqmusic',
        'format': 'json',
        'guid': desktopGuid,
        if (uin.isNotEmpty) 'uin': uin,
        if (config.authKey.isNotEmpty) 'authst': config.authKey,
      },
      key: {'module': module, 'method': method, 'param': param},
    });

    final headers = <String, String>{
      'Accept': '*/*',
      'Accept-Language': 'zh-CN',
      'User-Agent': _desktopUserAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': 'https://y.qq.com/',
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };

    try {
      final resp = await _client
          .post(Uri.parse(_desktopMusicuUrl), headers: headers, body: body)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final decoded = json.decode(
        utf8.decode(resp.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      if ((decoded['code'] as num?)?.toInt() != 0) return null;

      final envelope = decoded[key];
      if (envelope is! Map) return null;
      final code = (envelope['code'] as num?)?.toInt();
      if (code != null && code != 0) return null;

      final data = envelope['data'];
      if (data is! Map) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  String _cookieHeader(QQMusicConfig config) {
    final parts = <String>[];
    if (config.cookie.trim().isNotEmpty) {
      parts.add(config.cookie.trim());
    }
    final uin = config.effectiveUin;
    if (uin.isNotEmpty && !config.cookie.contains('uin=')) {
      parts.add('uin=o$uin');
    }
    return parts.join('; ');
  }
}
