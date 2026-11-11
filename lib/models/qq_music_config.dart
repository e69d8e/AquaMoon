/// QQ 音乐收藏绑定与授权配置模型。
///
/// 支持两种接入粒度：
/// 1. 免登公开模式：仅提供 [uin]（QQ 号）或 [dissid]（「我喜欢」歌单 ID），
///    无需 Cookie 即可拉取已设为公开的「我喜欢」歌单；
/// 2. 凭证增强模式：额外提供 [cookie]（包含 `uin` 与 `qqmusic_key` / `qm_keyst`），
///    支持私密「我喜欢」读取、会员高音质流媒体地址解析及云端红心增删同步。
class QQMusicConfig {
  final String uin;
  final String dissid;
  final String cookie;
  final String nickname;
  final String playlistName;
  final int dirId;
  final int? lastSyncMs;

  const QQMusicConfig({
    this.uin = '',
    this.dissid = '',
    this.cookie = '',
    this.nickname = '',
    this.playlistName = '我喜欢',
    this.dirId = 201,
    this.lastSyncMs,
  });

  /// 是否已绑定有效的 QQ 号、歌单 ID 或含 uin 的 Cookie。
  bool get isBound =>
      effectiveUin.isNotEmpty || dissid.trim().isNotEmpty;

  /// 是否具备有效的登录态 Cookie。
  bool get hasCookie => extractAuthKeyFromCookie(cookie).isNotEmpty;

  /// 优先返回显式填写的 [uin]，否则尝试从 [cookie] 中提取。
  String get effectiveUin {
    final cleanUin = normalizeUin(uin);
    if (cleanUin.isNotEmpty) return cleanUin;
    return extractUinFromCookie(cookie);
  }

  /// 从 [cookie] 中提取的 `qqmusic_key` 或 `qm_keyst`。
  String get authKey => extractAuthKeyFromCookie(cookie);

  DateTime? get lastSyncTime => lastSyncMs != null && lastSyncMs! > 0
      ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs!)
      : null;

  /// 用于 UI 展示的账号/歌单摘要标签。
  String get displayLabel {
    if (nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    final u = effectiveUin;
    if (u.isNotEmpty) {
      return 'QQ $u';
    }
    if (dissid.trim().isNotEmpty) {
      return '歌单 #${dissid.trim()}';
    }
    return '未绑定';
  }

  QQMusicConfig copyWith({
    String? uin,
    String? dissid,
    String? cookie,
    String? nickname,
    String? playlistName,
    int? dirId,
    int? lastSyncMs,
    bool clearLastSync = false,
  }) {
    return QQMusicConfig(
      uin: uin ?? this.uin,
      dissid: dissid ?? this.dissid,
      cookie: cookie ?? this.cookie,
      nickname: nickname ?? this.nickname,
      playlistName: playlistName ?? this.playlistName,
      dirId: dirId ?? this.dirId,
      lastSyncMs: clearLastSync ? null : (lastSyncMs ?? this.lastSyncMs),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uin': uin,
      'dissid': dissid,
      'cookie': cookie,
      'nickname': nickname,
      'playlistName': playlistName,
      'dirId': dirId,
      'lastSyncMs': lastSyncMs,
    };
  }

  factory QQMusicConfig.fromMap(Object? raw) {
    if (raw is! Map) return const QQMusicConfig();
    return QQMusicConfig(
      uin: raw['uin'] as String? ?? '',
      dissid: raw['dissid'] as String? ?? '',
      cookie: raw['cookie'] as String? ?? '',
      nickname: raw['nickname'] as String? ?? '',
      playlistName: raw['playlistName'] as String? ?? '我喜欢',
      dirId: (raw['dirId'] as num?)?.toInt() ?? 201,
      lastSyncMs: (raw['lastSyncMs'] as num?)?.toInt(),
    );
  }

  // --- Static Parsers ---

  /// 清洗 QQ 号（去除 `o` 前缀与前导 `0`）。
  static String normalizeUin(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final cleaned = trimmed.replaceFirst(RegExp(r'^[oO]+'), '');
    final strippedZeros = cleaned.replaceFirst(RegExp(r'^0+'), '');
    if (RegExp(r'^\d{5,13}$').hasMatch(strippedZeros)) {
      return strippedZeros;
    }
    return '';
  }

  /// 从用户输入（可能为纯数字 QQ 号、纯数字歌单 dissid 或分享链接/文案）
  /// 智能区分出 `(uin, dissid)`。
  ///
  /// 规则：
  /// - 若包含 URL 或 `id=` / `playlist/`，提取歌单 `dissid`；
  /// - 若以 `dissid:` 或 `#` 开头，提取为歌单 `dissid`；
  /// - 若为纯数字：长度 >= 10 且以 `7`/`8`/`9`/`1`/`2`/`3`/`4`/`5`/`6` 等
  ///   歌单常见号段，调用方若不确定可先尝试作为 QQ 号，失败再作歌单 ID；
  ///   此处对包含链接特征的优先归为 `dissid`。
  static ({String uin, String dissid}) parseAccountOrPlaylistInput(
    String input,
  ) {
    final text = input.trim();
    if (text.isEmpty) return (uin: '', dissid: '');

    // 1. URL or share text containing playlist/id=123456
    final urlDissid = extractDissidFromInput(text);
    if (urlDissid.isNotEmpty) {
      return (uin: '', dissid: urlDissid);
    }

    // 2. Pure digits
    final digitsOnly = text.replaceFirst(RegExp(r'^[oO]'), '').trim();
    if (RegExp(r'^\d+$').hasMatch(digitsOnly)) {
      final norm = normalizeUin(digitsOnly);
      return (uin: norm, dissid: '');
    }

    return (uin: '', dissid: '');
  }

  /// 从歌单分享文案或链接中提取歌单 ID (`dissid`)。
  /// 支持：
  /// - `https://y.qq.com/n/ryqq/playlist/7890123456`
  /// - `https://i.y.qq.com/n2/m/share/details/taoge.html?id=7890123456&...`
  /// - `https://c.y.qq.com/base/fcgi-bin/u?__=...` 展开前后的 `id=` / `disstid=`
  /// - 显式 `#7890123456` 或 `dissid:7890123456`
  static String extractDissidFromInput(String input) {
    final text = input.trim();
    if (text.isEmpty) return '';

    final playlistPathMatch = RegExp(
      r'playlist/(\d{6,20})',
      caseSensitive: false,
    ).firstMatch(text);
    if (playlistPathMatch != null) {
      return playlistPathMatch.group(1)!;
    }

    final queryIdMatch = RegExp(
      r'[?&](?:id|disstid|dissid|tid)=(\d{6,20})',
      caseSensitive: false,
    ).firstMatch(text);
    if (queryIdMatch != null) {
      return queryIdMatch.group(1)!;
    }

    final prefixMatch = RegExp(
      r'^(?:dissid:|id:|#)(\d{6,20})$',
      caseSensitive: false,
    ).firstMatch(text);
    if (prefixMatch != null) {
      return prefixMatch.group(1)!;
    }

    return '';
  }

  /// 从 Cookie 字符串中提取数字 QQ 号 (`uin` / `wxuin` / `p_uin`)。
  static String extractUinFromCookie(String cookie) {
    if (cookie.trim().isEmpty) return '';
    final patterns = [
      RegExp(r'(?:^|;\s*)uin=([^;\s]+)'),
      RegExp(r'(?:^|;\s*)p_uin=([^;\s]+)'),
      RegExp(r'(?:^|;\s*)qqmusic_uin=([^;\s]+)'),
      RegExp(r'(?:^|;\s*)wxuin=([^;\s]+)'),
    ];
    for (final reg in patterns) {
      final match = reg.firstMatch(cookie);
      if (match != null) {
        final normalized = normalizeUin(match.group(1)!);
        if (normalized.isNotEmpty) return normalized;
      }
    }
    return '';
  }

  /// 从 Cookie 字符串中提取 `qqmusic_key` 或 `qm_keyst`。
  static String extractAuthKeyFromCookie(String cookie) {
    if (cookie.trim().isEmpty) return '';
    final patterns = [
      RegExp(r'(?:^|;\s*)qqmusic_key=([^;\s]+)'),
      RegExp(r'(?:^|;\s*)qm_keyst=([^;\s]+)'),
    ];
    for (final reg in patterns) {
      final match = reg.firstMatch(cookie);
      if (match != null) {
        final val = match.group(1)!.trim();
        if (val.isNotEmpty) return val;
      }
    }
    return '';
  }
}
