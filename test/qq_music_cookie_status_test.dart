import 'package:aquamoon/core/utils/qq_music_cookie_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成一份带指定到期时间的 Cookie 字符串。
String _cookieWithExpiry(DateTime expiresAt, {DateTime? issuedAt}) {
  final issue = issuedAt ?? expiresAt.subtract(const Duration(days: 30));
  return 'uin=3503823799; qqmusic_key=ABC; qm_keyst=ABC; '
      'psrf_musickey_createtime=${issue.millisecondsSinceEpoch ~/ 1000}; '
      'psrf_access_token_expiresAt=${expiresAt.millisecondsSinceEpoch ~/ 1000}';
}

void main() {
  final now = DateTime(2026, 11, 18, 13, 0);

  group('QQMusicCookieStatus', () {
    test('未配置 Cookie 时为 unknown 且不提示', () {
      final status = QQMusicCookieStatus.parse('', now: now);
      expect(status.health, QQMusicCookieHealth.unknown);
      expect(status.needsAttention, isFalse);
      expect(status.expiresAt, isNull);
    });

    test('超过有效期判断为 expired', () {
      final status = QQMusicCookieStatus.parse(
        _cookieWithExpiry(now.subtract(const Duration(days: 1))),
        now: now,
      );
      expect(status.health, QQMusicCookieHealth.expired);
      expect(status.needsAttention, isTrue);
      expect(status.describe(now), contains('过期'));
    });

    test('3 天内到期判断为 expiringSoon', () {
      final status = QQMusicCookieStatus.parse(
        _cookieWithExpiry(now.add(const Duration(days: 2))),
        now: now,
      );
      expect(status.health, QQMusicCookieHealth.expiringSoon);
      expect(status.needsAttention, isTrue);
      expect(status.describe(now), contains('过期'));
    });

    test('有效期充足判断为 healthy', () {
      final status = QQMusicCookieStatus.parse(
        _cookieWithExpiry(now.add(const Duration(days: 60))),
        now: now,
      );
      expect(status.health, QQMusicCookieHealth.healthy);
      expect(status.needsAttention, isFalse);
      expect(status.describe(now), contains('有效期至'));
    });

    test('缺少过期时间戳时退化为 unknown，不误报过期', () {
      final status = QQMusicCookieStatus.parse(
        'uin=3503823799; qqmusic_key=ABC',
        now: now,
      );
      expect(status.health, QQMusicCookieHealth.unknown);
      expect(status.needsAttention, isFalse);
    });

    test('解析签发时间用于展示', () {
      final issued = now.subtract(const Duration(days: 10));
      final status = QQMusicCookieStatus.parse(
        _cookieWithExpiry(now.add(const Duration(days: 60)), issuedAt: issued),
        now: now,
      );
      expect(status.issuedAt, isNotNull);
      expect(
        status.issuedAt!.difference(issued).inSeconds.abs() < 2,
        isTrue,
      );
    });

    test('remainingFrom 返回剩余时间', () {
      final expires = now.add(const Duration(days: 5));
      final status = QQMusicCookieStatus.parse(
        _cookieWithExpiry(expires),
        now: now,
      );
      expect(status.remainingFrom(now)!.inDays, 5);
    });
  });
}