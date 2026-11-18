/// QQ 音乐 Cookie 有效期解析（纯 Dart，可在任意平台与单元测试中运行）。
///
/// y.qq.com 的登录 Cookie 里带两个时间戳：
/// - `psrf_access_token_expiresAt`：access token 到期时间（秒级 Unix 时间戳）；
/// - `psrf_musickey_createtime`：音乐 key 的签发时间。
///
/// 服务端会在 key 轮换或过期后静默降级成匿名请求——表现为「资料还能读、
/// 但取流一律拿不到 purl」，所以本地先按时间戳给出预警，再结合
/// `QQMusicService.checkSession` 的真实回包判断是否真的失效。
library;

/// Cookie 健康度。
enum QQMusicCookieHealth {
  /// 没有 Cookie，或 Cookie 里找不到可判断的时间戳。
  unknown,

  /// 仍在有效期内。
  healthy,

  /// 即将到期（默认 3 天内）。
  expiringSoon,

  /// 已过期。
  expired;

  /// 是否需要提醒用户重新绑定。
  bool get needsAttention =>
      this == QQMusicCookieHealth.expiringSoon ||
      this == QQMusicCookieHealth.expired;
}

/// 本地解析出的 Cookie 有效期状态。
class QQMusicCookieStatus {
  final QQMusicCookieHealth health;

  /// access token 到期时间，缺失时为 null。
  final DateTime? expiresAt;

  /// 音乐 key 签发时间，缺失时为 null。
  final DateTime? issuedAt;

  const QQMusicCookieStatus({
    required this.health,
    this.expiresAt,
    this.issuedAt,
  });

  static const QQMusicCookieStatus unbound = QQMusicCookieStatus(
    health: QQMusicCookieHealth.unknown,
  );

  bool get needsAttention => health.needsAttention;

  /// 距离到期的剩余时间；无到期时间时返回 null。
  Duration? remainingFrom(DateTime now) {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) return null;
    return expiresAt.difference(now);
  }

  /// 面向用户的简短说明。
  String describe(DateTime now) {
    final expiresAt = this.expiresAt;
    switch (health) {
      case QQMusicCookieHealth.unknown:
        return '未检测到 Cookie 有效期';
      case QQMusicCookieHealth.expiringSoon:
        return 'Cookie 将于 ${_formatDate(expiresAt)} 过期';
      case QQMusicCookieHealth.expired:
        return 'Cookie 已于 ${_formatDate(expiresAt)} 过期';
      case QQMusicCookieHealth.healthy:
        return expiresAt == null
            ? 'Cookie 有效'
            : 'Cookie 有效期至 ${_formatDate(expiresAt)}';
    }
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '未知';
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  /// 解析 Cookie 字符串；[expiringWithin] 内到期视为「即将过期」。
  static QQMusicCookieStatus parse(
    String cookie, {
    DateTime? now,
    Duration expiringWithin = const Duration(days: 3),
  }) {
    final trimmed = cookie.trim();
    if (trimmed.isEmpty) return unbound;

    final expiresAt = _readTimestamp(trimmed, 'psrf_access_token_expiresAt');
    final issuedAt = _readTimestamp(trimmed, 'psrf_musickey_createtime');
    if (expiresAt == null) {
      return QQMusicCookieStatus(
        health: QQMusicCookieHealth.unknown,
        issuedAt: issuedAt,
      );
    }

    final reference = now ?? DateTime.now();
    final remaining = expiresAt.difference(reference);
    final health = remaining.isNegative
        ? QQMusicCookieHealth.expired
        : (remaining <= expiringWithin
              ? QQMusicCookieHealth.expiringSoon
              : QQMusicCookieHealth.healthy);

    return QQMusicCookieStatus(
      health: health,
      expiresAt: expiresAt,
      issuedAt: issuedAt,
    );
  }

  static DateTime? _readTimestamp(String cookie, String key) {
    final match = RegExp('(?:^|;\\s*)$key=(\\d{9,12})').firstMatch(cookie);
    if (match == null) return null;
    final seconds = int.tryParse(match.group(1)!);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}

/// 服务端会话探测结果。
class QQMusicSessionCheck {
  /// 服务端是否认可当前 Cookie 的登录态。
  final bool valid;

  /// 探测到的昵称（服务端认可时通常非空）。
  final String nickname;

  /// 失败原因或补充说明，可直接展示给用户。
  final String? message;

  const QQMusicSessionCheck({
    required this.valid,
    this.nickname = '',
    this.message,
  });

  const QQMusicSessionCheck.unbound([String? message])
    : valid = false,
      nickname = '',
      message = message ?? '未配置 QQ 音乐 Cookie';

  const QQMusicSessionCheck.invalid([String? message])
    : valid = false,
      nickname = '',
      message = message ?? 'Cookie 已失效或登录态无法识别';

  const QQMusicSessionCheck.ok(this.nickname)
    : valid = true,
      message = null;
}