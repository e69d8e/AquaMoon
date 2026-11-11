import '../../models/song.dart';

/// 跨源曲目匹配：把 QQ 音乐在线曲目对齐到本地曲库中的同一首歌。
///
/// 纯 Dart、无 Flutter 依赖，供收藏合并与播放回退共用。
///
/// 为什么不能直接比 `title == title && artist == artist`：两个来源的元数据
/// 写法差异很大——QQ 音乐用 `A/B` 连接合唱歌手而本地标签可能是 `A、B`、
/// `A & B` 或 `A, B`；QQ 标题常带 `(Live)`、`(伴奏)`、`- Remastered` 等
/// 版本后缀而本地没有；全角/半角标点、大小写、多余空格也都不一致。
/// 因此这里按「基础标题 + 歌手集合 + 时长」分级打分，而不是做字符串全等。
class SongMatcher {
  const SongMatcher._();

  /// 全角 -> 半角标点映射，匹配前先统一。
  static const Map<String, String> _punctuationFolds = {
    '（': '(',
    '）': ')',
    '【': '[',
    '】': ']',
    '［': '[',
    '］': ']',
    '《': '',
    '》': '',
    '「': '',
    '」': '',
    '『': '',
    '』': '',
    '：': ':',
    '；': ';',
    '，': ',',
    '。': '.',
    '、': ',',
    '！': '!',
    '？': '?',
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    '—': '-',
    '－': '-',
    '–': '-',
    '～': '~',
    '｜': '|',
    '·': ' ',
    '•': ' ',
    '×': 'x',
  };

  /// 视为「无歌手信息」的占位值。
  static const Set<String> _unknownArtistTokens = {
    '',
    '未知歌手',
    'unknown',
    'unknownartist',
    'variousartists',
    '群星',
    'v.a',
    'v.a.',
    'va',
  };

  /// 视为「无标题信息」的占位值。
  static const Set<String> _unknownTitleTokens = {
    '',
    '未知曲目',
    '未知歌曲',
    '本地歌曲',
    'unknown',
    'untitled',
  };

  /// 歌手分隔符：QQ 用 `/`，本地标签常见 `,`、`&`、`、`、`feat.` 等。
  static final RegExp _artistSplitter = RegExp(
    r'[/,;&+、]|\bfeat\.?\b|\bfeaturing\b|\bwith\b|\bvs\.?\b|\band\b',
    caseSensitive: false,
  );

  /// 去掉所有标点与空白后的紧凑形式，用于宽松比较。
  static String compact(String input) {
    final folded = foldPunctuation(input);
    final buf = StringBuffer();
    for (final code in folded.runes) {
      final ch = String.fromCharCode(code);
      if (RegExp(r'[a-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]').hasMatch(ch)) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  /// 统一全角标点为半角并压缩空白、转小写。
  static String foldPunctuation(String input) {
    var text = input.trim().toLowerCase();
    _punctuationFolds.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 去掉版本后缀（`(Live)`、`- Remastered`、`[伴奏]` 等），得到「基础标题」。
  ///
  /// 保守处理：只有当括号/破折号后面确实像版本标记时才剥离，避免把
  /// `稻香 (钢琴版)` 与 `稻香` 之外真正不同的曲目混为一谈——即便如此，
  /// 时长打分仍会把差异过大的版本区分开。
  static String baseTitle(String title) {
    var t = foldPunctuation(title);
    // 去掉成对括号及其内容：(Live) / [Bonus] / (feat. X)
    t = t.replaceAll(RegExp(r'\([^)]*\)'), '');
    t = t.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    // 去掉尾部 " - xxx" / " ~xxx" 版本说明
    t = t.replaceAll(RegExp(r'\s*[-~]\s*[^-~]*$'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 标题的宽松键：基础标题去标点去空白。
  static String? titleKey(String title) {
    final key = compact(baseTitle(title));
    if (key.isEmpty) return null;
    if (_unknownTitleTokens.contains(compact(title))) return null;
    return key;
  }

  /// 歌手拆成归一化 token 集合，供交集比较。
  static Set<String> artistTokens(String artist) {
    final folded = foldPunctuation(artist);
    if (_unknownArtistTokens.contains(compact(folded))) return const {};
    return folded
        .split(_artistSplitter)
        .map(compact)
        .where((t) => t.isNotEmpty && !_unknownArtistTokens.contains(t))
        .toSet();
  }

  /// 两个歌手表述是否指向同一（组）歌手：任一方缺失视为「未知」，
  /// 否则要求 token 集合有交集。
  static bool artistsCompatible(String a, String b) {
    final ta = artistTokens(a);
    final tb = artistTokens(b);
    if (ta.isEmpty || tb.isEmpty) return true;
    return ta.intersection(tb).isNotEmpty;
  }

  /// 时长差打分：两侧都已知时越接近越好，差得离谱则强烈扣分。
  static int durationScore(int aMs, int bMs) {
    if (aMs <= 0 || bMs <= 0) return 0;
    final diff = (aMs - bMs).abs();
    if (diff <= 3000) return 3;
    if (diff <= 8000) return 1;
    if (diff <= 20000) return -1;
    return -4;
  }

  /// 给一个 (远端, 本地) 组合打分；返回 `null` 表示不可能是同一首歌。
  ///
  /// 返回值为 `(tier, durationScore)`：tier 越小匹配越可信，同一 tier 内
  /// 再用时长差择优。分层而不是简单相加，是为了避免「标题互为子串 +
  /// 歌手未知」这类弱证据凑够分数造成误匹配（如《爱》匹到《爱情》）。
  static ({int tier, int duration})? scorePair(Song remote, Song local) {
    final remoteTitle = titleKey(remote.title);
    final localTitle = titleKey(local.title);
    if (remoteTitle == null || localTitle == null) return null;

    final remoteArtists = artistTokens(remote.artist);
    final localArtists = artistTokens(local.artist);
    final artistsIntersect = remoteArtists.isNotEmpty &&
        localArtists.isNotEmpty &&
        remoteArtists.intersection(localArtists).isNotEmpty;
    final artistKnown = remoteArtists.isNotEmpty && localArtists.isNotEmpty;

    final int tier;
    if (remoteTitle == localTitle) {
      if (artistsIntersect) {
        tier = 0;
      } else if (!artistKnown) {
        // 一方歌手缺失（常见于标签不全的本地文件）：标题精确仍可匹配
        tier = 1;
      } else {
        // 标题完全相同但歌手明确不同 → 不是同一首歌
        return null;
      }
    } else if (remoteTitle.contains(localTitle) ||
        localTitle.contains(remoteTitle)) {
      // 一方带版本后缀等修饰：只有歌手确实相交才接受
      if (!artistsIntersect) return null;
      tier = 2;
    } else {
      return null;
    }

    return (tier: tier, duration: durationScore(remote.durationMs, local.durationMs));
  }

  /// 在 [candidates] 中为 [remote] 挑最合适的本地曲目；没有可信匹配时返回 `null`。
  ///
  /// 排序优先级：匹配层级 → 时长接近度 → 有本地文件（能真正播放）。
  static Song? bestMatch(Song remote, Iterable<Song> candidates) {
    Song? best;
    ({int tier, int duration})? bestScore;
    for (final c in candidates) {
      final score = scorePair(remote, c);
      if (score == null) continue;
      if (bestScore == null ||
          _better(score, bestScore, c.hasLocalFile, best?.hasLocalFile ?? false)) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  static bool _better(
    ({int tier, int duration}) a,
    ({int tier, int duration}) b,
    bool aHasFile,
    bool bHasFile,
  ) {
    if (a.tier != b.tier) return a.tier < b.tier;
    if (a.duration != b.duration) return a.duration > b.duration;
    return aHasFile && !bHasFile;
  }

  /// 在本地曲库中查找与 [remote] 匹配的曲目（标题键索引，避免全表扫描）。
  static Song? findLocalMatch(
    Song remote,
    Iterable<Song> localSongs, {
    Set<String> excludeIds = const {},
  }) {
    final remoteTitle = titleKey(remote.title);
    if (remoteTitle == null) return null;

    final byTitle = <String, List<Song>>{};
    for (final local in localSongs) {
      if (excludeIds.contains(local.id)) continue;
      final key = titleKey(local.title);
      if (key == null) continue;
      byTitle.putIfAbsent(key, () => []).add(local);
      // 同时按「完整 compact 标题」建索引，兼容带版本后缀的写法
      final full = compact(local.title);
      if (full.isNotEmpty && full != key) {
        byTitle.putIfAbsent(full, () => []).add(local);
      }
    }

    final candidates = <Song>{
      ...?byTitle[remoteTitle],
      ...?byTitle[compact(remote.title)],
    };
    if (candidates.isEmpty) return null;
    return bestMatch(remote, candidates);
  }
}
