import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OnlineSearchResult {
  final String source; // 'QQ音乐' | '网易云音乐' | 'Apple Music' | 'LRCLIB'
  final String title;
  final String artist;
  final String album;
  final String? syncedLyrics;
  final String? plainLyrics;
  final String? coverUrl;
  final int durationMs;
  final bool isInstrumental;
  final double matchScore; // 0.0 ~ 100.0
  final String? extraId; // songmid or netease id

  const OnlineSearchResult({
    this.source = 'QQ音乐',
    required this.title,
    required this.artist,
    required this.album,
    this.syncedLyrics,
    this.plainLyrics,
    this.coverUrl,
    this.durationMs = 0,
    this.isInstrumental = false,
    this.matchScore = 0.0,
    this.extraId,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  bool get hasLyrics =>
      (syncedLyrics != null && syncedLyrics!.isNotEmpty) ||
      (plainLyrics != null && plainLyrics!.isNotEmpty) ||
      isInstrumental;

  int durationDiffSeconds(Duration? targetDuration) {
    if (targetDuration == null ||
        targetDuration.inSeconds <= 0 ||
        durationMs <= 0) {
      return 0;
    }
    return (duration.inSeconds - targetDuration.inSeconds).abs();
  }

  OnlineSearchResult copyWith({
    String? source,
    String? title,
    String? artist,
    String? album,
    String? syncedLyrics,
    String? plainLyrics,
    String? coverUrl,
    int? durationMs,
    bool? isInstrumental,
    double? matchScore,
    String? extraId,
  }) {
    return OnlineSearchResult(
      source: source ?? this.source,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      syncedLyrics: syncedLyrics ?? this.syncedLyrics,
      plainLyrics: plainLyrics ?? this.plainLyrics,
      coverUrl: coverUrl ?? this.coverUrl,
      durationMs: durationMs ?? this.durationMs,
      isInstrumental: isInstrumental ?? this.isInstrumental,
      matchScore: matchScore ?? this.matchScore,
      extraId: extraId ?? this.extraId,
    );
  }
}

class OnlineMetadataService {
  final http.Client _client = http.Client();

  /// Search multiple candidates across platforms for user manual selection or best-match calculation.
  Future<List<OnlineSearchResult>> searchCandidates({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final cleanTitle = cleanSongTitle(title);
    final cleanArtist = (artist == '未知歌手' || artist.isEmpty)
        ? ''
        : cleanArtistName(artist);

    if (cleanTitle.isEmpty && cleanArtist.isEmpty) {
      return [];
    }

    final allCandidates = <OnlineSearchResult>[];

    // 1. Primary forward search with QQ Music, NetEase, iTunes, LRCLIB in parallel
    final forwardTasks = <Future<List<OnlineSearchResult>>>[
      _fetchQQMusicCandidates(cleanTitle, cleanArtist, duration),
      _fetchNetEaseCandidates(cleanTitle, cleanArtist, duration),
      _fetchITunesCandidates(cleanTitle, cleanArtist, duration),
      _fetchLrclibCandidates(cleanTitle, cleanArtist, album, duration),
    ];

    final forwardResults = await Future.wait(forwardTasks);
    for (final list in forwardResults) {
      allCandidates.addAll(list);
    }

    // 2. Bidirectional reverse retry:
    // If cleanArtist is not empty and initial results have low confidence or are empty,
    // swap title & artist (in case filename was 'Artist - Title' or 'Title - Artist' inverted).
    final hasHighConfidenceMatch = allCandidates.any((c) => c.matchScore >= 70);
    if (!hasHighConfidenceMatch &&
        cleanArtist.isNotEmpty &&
        cleanArtist != cleanTitle) {
      final reverseTasks = <Future<List<OnlineSearchResult>>>[
        _fetchQQMusicCandidates(cleanArtist, cleanTitle, duration),
        _fetchNetEaseCandidates(cleanArtist, cleanTitle, duration),
      ];
      final reverseResults = await Future.wait(reverseTasks);
      for (final list in reverseResults) {
        for (final c in list) {
          final rescored = c.copyWith(
            matchScore: _calculateMatchScore(
              targetTitle: cleanTitle,
              targetArtist: cleanArtist,
              targetDuration: duration,
              candidateTitle: c.title,
              candidateArtist: c.artist,
              candidateDurationMs: c.durationMs,
              source: c.source,
            ),
          );
          allCandidates.add(rescored);
        }
      }
    }

    // 3. Fallback: Search with only cleanTitle if no results yet
    if (allCandidates.isEmpty && cleanTitle.isNotEmpty) {
      final titleOnlyResults = await Future.wait([
        _fetchQQMusicCandidates(cleanTitle, '', duration),
        _fetchNetEaseCandidates(cleanTitle, '', duration),
      ]);
      for (final list in titleOnlyResults) {
        allCandidates.addAll(list);
      }
    }

    // 4. Deduplicate and sort by matchScore descending
    final uniqueCandidates = <String, OnlineSearchResult>{};
    for (final c in allCandidates) {
      final key = '${c.source}_${c.title}_${c.artist}_${c.durationMs ~/ 1000}'
          .toLowerCase();
      if (!uniqueCandidates.containsKey(key) ||
          (c.matchScore > uniqueCandidates[key]!.matchScore)) {
        uniqueCandidates[key] = c;
      }
    }

    final sorted = uniqueCandidates.values.toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));

    return sorted;
  }

  /// Free-form online song & lyric search for independent search center
  Future<List<OnlineSearchResult>> searchOnlineSongs({
    required String query,
    String?
    platformFilter, // '全部' | 'QQ音乐' | '网易云音乐' | 'Apple Music' | 'LRCLIB'
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Parse potential "Title - Artist" or "Title Artist"
    String titlePart = cleanQuery;
    String artistPart = '';

    if (cleanQuery.contains(' - ')) {
      final parts = cleanQuery.split(' - ');
      if (parts.length >= 2) {
        titlePart = parts[0].trim();
        artistPart = parts.sublist(1).join(' ').trim();
      }
    } else if (cleanQuery.contains('-')) {
      final parts = cleanQuery.split('-');
      if (parts.length >= 2) {
        titlePart = parts[0].trim();
        artistPart = parts.sublist(1).join(' ').trim();
      }
    }

    final allResults = <OnlineSearchResult>[];
    final selectedPlatform = platformFilter ?? '全部';

    final tasks = <Future<List<OnlineSearchResult>>>[];

    if (selectedPlatform == '全部' || selectedPlatform == 'QQ音乐') {
      tasks.add(_fetchQQMusicCandidates(cleanQuery, '', null, limit: 15));
    }
    if (selectedPlatform == '全部' || selectedPlatform == '网易云音乐') {
      tasks.add(_fetchNetEaseCandidates(cleanQuery, '', null, limit: 15));
    }
    if (selectedPlatform == '全部' || selectedPlatform == 'Apple Music') {
      tasks.add(_fetchITunesCandidates(cleanQuery, '', null, limit: 12));
    }
    if (selectedPlatform == '全部' || selectedPlatform == 'LRCLIB') {
      tasks.add(
        _fetchLrclibCandidates(titlePart, artistPart, null, null, limit: 12),
      );
    }

    final responses = await Future.wait(tasks);
    for (final list in responses) {
      allResults.addAll(list);
    }

    // Deduplicate
    final unique = <String, OnlineSearchResult>{};
    for (final r in allResults) {
      final key = '${r.source}_${r.title}_${r.artist}_${r.durationMs ~/ 1000}'
          .toLowerCase();
      if (!unique.containsKey(key)) {
        unique[key] = r;
      }
    }

    return unique.values.toList();
  }

  /// Automatically fetch the best metadata with strict platform dataset integrity (QQ Music Prioritized).
  Future<OnlineSearchResult?> fetchMetadata({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final candidates = await searchCandidates(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
    );

    if (candidates.isEmpty) return null;

    // 1. Priority Rule: Check QQ Music candidate with score >= 45 and complete dataset
    final qqCandidates = candidates
        .where((c) => c.source == 'QQ音乐' && c.matchScore >= 45)
        .toList();
    if (qqCandidates.isNotEmpty) {
      var topQQ = qqCandidates.first;
      if (!topQQ.hasLyrics && topQQ.extraId != null) {
        topQQ = await _ensureQQMusicLyrics(topQQ);
      }
      if (topQQ.coverUrl != null && topQQ.hasLyrics) {
        return topQQ;
      }
      // If QQ has cover, keep QQ as base and only safely fallback lyrics if missing
      if (topQQ.coverUrl != null) {
        if (!topQQ.hasLyrics) {
          final lrcFallback = candidates.firstWhere(
            (c) =>
                c.hasLyrics &&
                (c.durationDiffSeconds(duration) <= 4 || duration == null),
            orElse: () => topQQ,
          );
          if (lrcFallback != topQQ) {
            return topQQ.copyWith(
              syncedLyrics: lrcFallback.syncedLyrics,
              plainLyrics: lrcFallback.plainLyrics,
            );
          }
        }
        return topQQ;
      }
    }

    // 2. Priority Rule: NetEase candidate with score >= 45
    final neteaseCandidates = candidates
        .where((c) => c.source == '网易云音乐' && c.matchScore >= 45)
        .toList();
    if (neteaseCandidates.isNotEmpty) {
      var topNetEase = neteaseCandidates.first;
      if (!topNetEase.hasLyrics && topNetEase.extraId != null) {
        topNetEase = await _ensureNetEaseLyrics(topNetEase);
      }
      if (topNetEase.coverUrl != null && topNetEase.hasLyrics) {
        return topNetEase;
      }
      return topNetEase;
    }

    // 3. Fallback to highest scoring candidate
    var best = candidates.first;
    if (best.source == 'QQ音乐' && !best.hasLyrics && best.extraId != null) {
      best = await _ensureQQMusicLyrics(best);
    } else if (best.source == '网易云音乐' &&
        !best.hasLyrics &&
        best.extraId != null) {
      best = await _ensureNetEaseLyrics(best);
    }

    return best;
  }

  /// Ensure lyrics are fully loaded for a given candidate (useful when user selects from dialog)
  Future<OnlineSearchResult> ensureLyricsLoaded(
    OnlineSearchResult candidate,
  ) async {
    if (candidate.hasLyrics) return candidate;
    if (candidate.source == 'QQ音乐' && candidate.extraId != null) {
      return await _ensureQQMusicLyrics(candidate);
    } else if (candidate.source == '网易云音乐' && candidate.extraId != null) {
      return await _ensureNetEaseLyrics(candidate);
    }
    return candidate;
  }

  // ==========================================
  // Platform Fetchers
  // ==========================================

  /// 1. QQ Music API candidates with duration & scoring
  ///
  /// The legacy `c.y.qq.com/soso/fcgi-bin/client_search_cp` endpoint now
  /// answers HTTP 500, so search goes through the desktop `musicu.fcg`
  /// gateway instead (`comm` block is required or it rejects with code 2001).
  Future<List<OnlineSearchResult>> _fetchQQMusicCandidates(
    String title,
    String artist,
    Duration? targetDuration, {
    int limit = 6,
  }) async {
    final list = <OnlineSearchResult>[];
    try {
      final keyword = '$title $artist'.trim();
      final uri = Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg');

      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Referer': 'https://y.qq.com/',
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            },
            body: json.encode({
              'comm': {'ct': 19, 'cv': 1859, 'uin': 0, 'format': 'json'},
              'req': {
                'module': 'music.search.SearchCgiService',
                'method': 'DoSearchForQQMusicDesktop',
                'param': {
                  'search_type': 0,
                  'query': keyword,
                  'page_num': 1,
                  'num_per_page': limit,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final songList =
            data['req']?['data']?['body']?['song']?['list'] as List<dynamic>?;

        if (songList != null) {
          for (final item in songList) {
            final songName = item['name'] as String? ?? title;
            final singers = item['singer'] as List<dynamic>?;
            final singerName =
                singers?.map((s) => s['name']).join('/') ?? artist;
            final albumObj = item['album'];
            final albumName = albumObj?['name'] as String? ?? '';
            final albumMid = albumObj?['mid'] as String?;
            final songMid = item['mid'] as String?;
            final interval = (item['interval'] as num?)?.toInt() ?? 0;
            final durationMs = interval * 1000;

            String? coverUrl;
            if (albumMid != null &&
                albumMid.isNotEmpty &&
                albumMid != '00000000000000') {
              coverUrl =
                  'https://y.gtimg.cn/music/photo_new/T002R800x800M000$albumMid.jpg';
            }

            final score = _calculateMatchScore(
              targetTitle: title,
              targetArtist: artist,
              targetDuration: targetDuration,
              candidateTitle: songName,
              candidateArtist: singerName,
              candidateDurationMs: durationMs,
              source: 'QQ音乐',
            );

            list.add(
              OnlineSearchResult(
                source: 'QQ音乐',
                title: songName,
                artist: singerName,
                album: albumName,
                coverUrl: coverUrl,
                durationMs: durationMs,
                matchScore: score,
                extraId: songMid,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return list;
  }

  Future<OnlineSearchResult> _ensureQQMusicLyrics(
    OnlineSearchResult candidate,
  ) async {
    final songMid = candidate.extraId;
    if (songMid == null || songMid.isEmpty) return candidate;

    try {
      final lyricUri = Uri.parse(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=$songMid&format=json&nobase64=0',
      );
      final lyricResp = await _client
          .get(
            lyricUri,
            headers: {
              'Referer': 'https://y.qq.com/',
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (lyricResp.statusCode == 200) {
        final lyricData = json.decode(utf8.decode(lyricResp.bodyBytes));
        final b64Lyric = lyricData['lyric'] as String?;
        if (b64Lyric != null && b64Lyric.isNotEmpty) {
          final decoded = utf8.decode(
            base64.decode(b64Lyric),
            allowMalformed: true,
          );
          return candidate.copyWith(syncedLyrics: decoded);
        }
      }
    } catch (_) {}
    return candidate;
  }

  /// 2. NetEase Cloud Music API candidates
  Future<List<OnlineSearchResult>> _fetchNetEaseCandidates(
    String title,
    String artist,
    Duration? targetDuration, {
    int limit = 6,
  }) async {
    final list = <OnlineSearchResult>[];
    try {
      final keyword = '$title $artist'.trim();
      final searchUrl = Uri.parse(
        'https://music.163.com/api/search/get/web?s=${Uri.encodeComponent(keyword)}&type=1&offset=0&limit=$limit',
      );

      final searchResponse = await _client
          .get(
            searchUrl,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (searchResponse.statusCode == 200) {
        final data = json.decode(utf8.decode(searchResponse.bodyBytes));
        final songs = data['result']?['songs'] as List<dynamic>?;
        if (songs != null) {
          for (final song in songs) {
            final songId = song['id']?.toString();
            final songTitle = song['name'] as String? ?? title;
            final artistsList = song['artists'] as List<dynamic>?;
            final artistName =
                artistsList?.map((a) => a['name']).join('/') ?? artist;
            final albumObj = song['album'];
            final albumName = albumObj?['name'] as String? ?? '';
            // The legacy search API no longer populates album.picUrl; derive
            // the CDN address from the album picId when it is absent.
            var coverUrl = albumObj?['picUrl'] as String?;
            if (coverUrl == null || coverUrl.isEmpty) {
              final picId = albumObj?['picId'] as num?;
              coverUrl = neteaseCoverUrlFromPicId(picId?.toString());
            }
            final durationMs = (song['duration'] as num?)?.toInt() ?? 0;

            final score = _calculateMatchScore(
              targetTitle: title,
              targetArtist: artist,
              targetDuration: targetDuration,
              candidateTitle: songTitle,
              candidateArtist: artistName,
              candidateDurationMs: durationMs,
              source: '网易云音乐',
            );

            list.add(
              OnlineSearchResult(
                source: '网易云音乐',
                title: songTitle,
                artist: artistName,
                album: albumName,
                coverUrl: coverUrl,
                durationMs: durationMs,
                matchScore: score,
                extraId: songId,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return list;
  }

  Future<OnlineSearchResult> _ensureNetEaseLyrics(
    OnlineSearchResult candidate,
  ) async {
    final songId = candidate.extraId;
    if (songId == null || songId.isEmpty) return candidate;

    try {
      final lyricUrl = Uri.parse(
        'https://music.163.com/api/song/lyric?os=pc&id=$songId&lv=-1&kv=-1&tv=-1',
      );
      final lyricResp = await _client
          .get(
            lyricUrl,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (lyricResp.statusCode == 200) {
        final lyricData = json.decode(utf8.decode(lyricResp.bodyBytes));
        final lrcObj = lyricData['lrc'];
        if (lrcObj != null) {
          final lrcText = lrcObj['lyric'] as String?;
          if (lrcText != null && lrcText.isNotEmpty) {
            return candidate.copyWith(syncedLyrics: lrcText);
          }
        }
      }
    } catch (_) {}
    return candidate;
  }

  /// 3. iTunes candidates
  ///
  /// The CN storefront intermittently answers with zero results even for
  /// songs it hosts, so fall back to the TW storefront when CN returns a
  /// valid-but-empty response (a timeout or HTTP error is not retried, to
  /// keep the whole multi-source search bounded).
  Future<List<OnlineSearchResult>> _fetchITunesCandidates(
    String title,
    String artist,
    Duration? targetDuration, {
    int limit = 4,
  }) async {
    final cnResults = await _searchITunesStore(
      title,
      artist,
      targetDuration,
      country: 'CN',
      limit: limit,
    );
    if (cnResults.isNotEmpty) return cnResults;
    return _searchITunesStore(
      title,
      artist,
      targetDuration,
      country: 'TW',
      limit: limit,
    );
  }

  Future<List<OnlineSearchResult>> _searchITunesStore(
    String title,
    String artist,
    Duration? targetDuration, {
    required String country,
    required int limit,
  }) async {
    final list = <OnlineSearchResult>[];
    try {
      final query = artist.isNotEmpty ? '$artist $title' : title;
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'country': country,
        'lang': 'zh_cn',
        'entity': 'song',
        'limit': limit.toString(),
      });

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>?;
        if (results != null) {
          for (final item in results) {
            final artwork100 = item['artworkUrl100'] as String?;
            final artwork1000 = artwork100?.replaceAll(
              '100x100bb',
              '1000x1000bb',
            );
            final itemTitle = item['trackName'] ?? title;
            final itemArtist = item['artistName'] ?? artist;
            final durationMs = (item['trackTimeMillis'] as num?)?.toInt() ?? 0;

            final score = _calculateMatchScore(
              targetTitle: title,
              targetArtist: artist,
              targetDuration: targetDuration,
              candidateTitle: itemTitle,
              candidateArtist: itemArtist,
              candidateDurationMs: durationMs,
              source: 'Apple Music',
            );

            list.add(
              OnlineSearchResult(
                source: 'Apple Music',
                title: itemTitle,
                artist: itemArtist,
                album: item['collectionName'] ?? '',
                coverUrl: artwork1000 ?? artwork100,
                durationMs: durationMs,
                matchScore: score,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return list;
  }

  /// 4. LRCLIB candidates
  Future<List<OnlineSearchResult>> _fetchLrclibCandidates(
    String title,
    String artist,
    String? album,
    Duration? targetDuration, {
    int limit = 4,
  }) async {
    final list = <OnlineSearchResult>[];
    try {
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'q': artist.isNotEmpty ? '$title $artist' : title,
      });

      final searchResp = await _client
          .get(searchUri)
          .timeout(const Duration(seconds: 4));
      if (searchResp.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(
          utf8.decode(searchResp.bodyBytes),
        );
        for (final item in jsonList.take(limit)) {
          final itemTitle = item['trackName'] ?? title;
          final itemArtist = item['artistName'] ?? artist;
          final itemAlbum = item['albumName'] ?? (album ?? '');
          final durationMs = lrclibDurationToMs(item['duration'] as num?);

          final score = _calculateMatchScore(
            targetTitle: title,
            targetArtist: artist,
            targetDuration: targetDuration,
            candidateTitle: itemTitle,
            candidateArtist: itemArtist,
            candidateDurationMs: durationMs,
            source: 'LRCLIB',
          );

          list.add(
            OnlineSearchResult(
              source: 'LRCLIB',
              title: itemTitle,
              artist: itemArtist,
              album: itemAlbum,
              syncedLyrics: item['syncedLyrics'] as String?,
              plainLyrics: item['plainLyrics'] as String?,
              durationMs: durationMs,
              isInstrumental: item['instrumental'] == true,
              matchScore: score,
            ),
          );
        }
      }
    } catch (_) {}
    return list;
  }

  // ==========================================
  // Offline helpers
  // ==========================================

  /// Derive a NetEase album cover URL from its picId (the search API stopped
  /// returning `picUrl`). Uses the well-known CDN id scrambling: XOR with a
  /// fixed magic string, then MD5 → URL-safe base64 path segment.
  static String? neteaseCoverUrlFromPicId(String? picId) {
    if (picId == null || picId.isEmpty) return null;
    const magic = '3go8&\$8*3*3h0k(2)2';
    final xored = <int>[
      for (var i = 0; i < picId.length; i++)
        picId.codeUnitAt(i) ^ magic.codeUnitAt(i % magic.length),
    ];
    final digest = base64
        .encode(md5.convert(xored).bytes)
        .replaceAll('/', '_')
        .replaceAll('+', '-');
    return 'https://p3.music.126.net/$digest/$picId.jpg';
  }

  /// LRCLIB reports `duration` as (possibly fractional) seconds, while the
  /// rest of the service works in milliseconds.
  static int lrclibDurationToMs(num? seconds) =>
      seconds == null ? 0 : (seconds * 1000).round();

  // ==========================================
  // Duration & Similarity Scoring Engine
  // ==========================================

  double _calculateMatchScore({
    required String targetTitle,
    required String targetArtist,
    required Duration? targetDuration,
    required String candidateTitle,
    required String candidateArtist,
    required int candidateDurationMs,
    required String source,
  }) {
    double score = 0.0;

    final normTargetTitle = _normalizeString(targetTitle);
    final normCandidateTitle = _normalizeString(candidateTitle);
    final normTargetArtist = _normalizeString(targetArtist);
    final normCandidateArtist = _normalizeString(candidateArtist);

    // 1. Title Similarity (0 ~ 45 pts)
    if (normTargetTitle.isNotEmpty && normCandidateTitle.isNotEmpty) {
      if (normTargetTitle == normCandidateTitle) {
        score += 45.0;
      } else if (normTargetTitle.contains(normCandidateTitle) ||
          normCandidateTitle.contains(normTargetTitle)) {
        score += 38.0;
      } else {
        final sim = _stringSimilarity(normTargetTitle, normCandidateTitle);
        score += (sim * 35.0);
      }
    }

    // 2. Artist Similarity (0 ~ 30 pts)
    if (normTargetArtist.isEmpty || normTargetArtist == '未知歌手') {
      score += 15.0; // neutral if local has no artist
    } else if (normCandidateArtist.isNotEmpty) {
      if (normTargetArtist == normCandidateArtist) {
        score += 30.0;
      } else if (normCandidateArtist.contains(normTargetArtist) ||
          normTargetArtist.contains(normCandidateArtist)) {
        score += 24.0;
      } else {
        final sim = _stringSimilarity(normTargetArtist, normCandidateArtist);
        score += (sim * 20.0);
      }
    }

    // 3. Audio Duration Validation (0 ~ 20 pts with strict penalties)
    if (targetDuration != null &&
        targetDuration.inSeconds > 0 &&
        candidateDurationMs > 0) {
      final diffMs = (targetDuration.inMilliseconds - candidateDurationMs)
          .abs();
      if (diffMs <= 2000) {
        score += 20.0; // Within 2 seconds: perfect duration match!
      } else if (diffMs <= 5000) {
        score += 15.0; // Within 5 seconds: great match
      } else if (diffMs <= 10000) {
        score += 5.0; // Within 10 seconds: acceptable
      } else if (diffMs <= 20000) {
        score -= 10.0; // 10-20 seconds diff: slight penalty
      } else if (diffMs <= 45000) {
        score -= 30.0; // 20-45s diff: likely live or extended edition
      } else {
        score -= 50.0; // >45s diff: likely a short preview or wrong song
      }
    } else {
      score += 10.0; // neutral
    }

    // 4. Platform Preference (QQ Music priority +5 pts)
    if (source == 'QQ音乐') {
      score += 5.0;
    }

    return score.clamp(0.0, 100.0);
  }

  static final RegExp _punctAndSpacesRegex = RegExp(
    r'[\s\p{P}\p{S}]+',
    unicode: true,
  );

  static String _normalizeString(String input) {
    return input.toLowerCase().replaceAll(_punctAndSpacesRegex, '').trim();
  }

  static double _stringSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    final pairs1 = _getBigrams(s1);
    final pairs2 = _getBigrams(s2);
    if (pairs1.isEmpty || pairs2.isEmpty) return 0.0;

    int intersection = 0;
    for (final pair in pairs1) {
      if (pairs2.contains(pair)) {
        intersection++;
      }
    }

    return (2.0 * intersection) / (pairs1.length + pairs2.length);
  }

  static List<String> _getBigrams(String str) {
    final list = <String>[];
    for (int i = 0; i < str.length - 1; i++) {
      list.add(str.substring(i, i + 2));
    }
    return list;
  }

  /// Download and cache an online cover image locally
  Future<String?> cacheOnlineImage(String imageUrl) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final coverDir = Directory(p.join(tempDir.path, 'online_covers'));
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(imageUrl)).toString();
      final cacheFile = File(p.join(coverDir.path, 'cover_$hash.jpg'));

      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        return cacheFile.uri.toString();
      }

      final response = await _client
          .get(Uri.parse(imageUrl), headers: {'Referer': 'https://y.qq.com/'})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await cacheFile.writeAsBytes(response.bodyBytes);
        return cacheFile.uri.toString();
      }
    } catch (_) {}
    return imageUrl;
  }

  static final RegExp _extFilterRegex = RegExp(
    r'\.(mp3|flac|wav|m4a|aac|ogg|opus|wma|ape|alac|dsd|dsf|dff)$',
    caseSensitive: false,
  );
  static final RegExp _titleLeadingTrackRegex = RegExp(r'^\s*\d+[\.\s\-_]+');
  static final RegExp _titleSquareQualityRegex = RegExp(
    r'\[.*?(flac|320k|128k|24bit|96k|hq|sq|lossless|cd|hires|hi-res|kuwo|kugou|qqmusic|网易云|酷我|酷狗|无损|品质).*?\]',
    caseSensitive: false,
  );
  static final RegExp _titleRoundQualityRegex = RegExp(
    r'\(.*?(flac|320k|128k|24bit|96k|hq|sq|lossless|cd|hires|hi-res|kuwo|kugou|qqmusic|网易云|酷我|酷狗|无损|品质).*?\)',
    caseSensitive: false,
  );
  static final RegExp _titleChineseQualityRegex = RegExp(
    r'【.*?(高音质|无损|官方|原版|独家|首发|超清|重制|品质).*?】',
    caseSensitive: false,
  );
  static final RegExp _titleMetaNoiseRegex = RegExp(
    r'\((official|video|audio|mv|remaster|remastered|ost|soundtrack|version).*?\)',
    caseSensitive: false,
  );

  /// Smart filename and title sanitizer for music search
  static String cleanSongTitle(String rawTitle) {
    return rawTitle
        .replaceAll(_extFilterRegex, '')
        .replaceAll(_titleLeadingTrackRegex, '') // '01. ', '01 - '
        .replaceAll(_titleSquareQualityRegex, '')
        .replaceAll(_titleRoundQualityRegex, '')
        .replaceAll(_titleChineseQualityRegex, '')
        .replaceAll(_titleMetaNoiseRegex, '')
        .replaceAll('_', ' ')
        .trim();
  }

  static final RegExp _artistSquareRegex = RegExp(
    r'\[.*?(kuwo|kugou|qqmusic|网易云|酷我|酷狗|flac|320k).*?\]',
    caseSensitive: false,
  );
  static final RegExp _artistRoundRegex = RegExp(
    r'\(.*?(kuwo|kugou|qqmusic|网易云|酷我|酷狗|flac|320k).*?\)',
    caseSensitive: false,
  );
  static final RegExp _artistPrefixNoiseRegex = RegExp(
    r'^\s*(kw|kuwo|kg)[\s\-_]+',
    caseSensitive: false,
  );

  /// Clean noise from artist name
  static String cleanArtistName(String rawArtist) {
    return rawArtist
        .replaceAll(_artistSquareRegex, '')
        .replaceAll(_artistRoundRegex, '')
        .replaceAll(_artistPrefixNoiseRegex, '')
        .trim();
  }

  void dispose() {
    _client.close();
  }
}
