import 'package:aquamoon/core/utils/qq_music_cookie_status.dart';
import 'package:aquamoon/models/qq_music_config.dart';
import 'package:aquamoon/providers/qq_music_session_provider.dart';
import 'package:aquamoon/services/qq_music_service.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends StorageService {
  _FakeStorage(this._config);

  final QQMusicConfig _config;

  @override
  QQMusicConfig getQQMusicConfig() => _config;
}

class _FakeService extends QQMusicService {
  _FakeService(this._result);

  final QQMusicSessionCheck _result;
  int calls = 0;

  @override
  Future<QQMusicSessionCheck> checkSession(QQMusicConfig config) async {
    calls++;
    return _result;
  }
}

String _cookieExpiringIn(Duration delta) {
  final expiresAt = DateTime.now().add(delta);
  return 'uin=3503823799; qqmusic_key=KEY; qm_keyst=KEY; '
      'psrf_access_token_expiresAt=${expiresAt.millisecondsSinceEpoch ~/ 1000}';
}

Future<QQMusicSessionNotifier> _pumpNotifier(
  QQMusicSessionNotifier notifier,
) async {
  // 构造时会触发一次后台校验，等它落地。
  await Future<void>.delayed(Duration.zero);
  return notifier;
}

void main() {
  group('QQMusicSessionNotifier', () {
    test('服务端判定失效时提示重新绑定', () async {
      final storage = _FakeStorage(
        QQMusicConfig(cookie: _cookieExpiringIn(const Duration(days: 60))),
      );
      final service = _FakeService(const QQMusicSessionCheck.invalid());
      final notifier = await _pumpNotifier(
        QQMusicSessionNotifier(storage, service),
      );

      expect(notifier.state.health, QQMusicCookieHealth.expired);
      expect(notifier.state.shouldPrompt, isTrue);
      expect(notifier.state.summary, contains('已失效'));
      expect(service.calls, 1);
    });

    test('本地已过期但服务端仍认可时，仍提示即将/已经过期', () async {
      final storage = _FakeStorage(
        QQMusicConfig(cookie: _cookieExpiringIn(const Duration(days: 1))),
      );
      final service = _FakeService(const QQMusicSessionCheck.ok('l'));
      final notifier = await _pumpNotifier(
        QQMusicSessionNotifier(storage, service),
      );

      expect(notifier.state.health, QQMusicCookieHealth.expiringSoon);
      expect(notifier.state.shouldPrompt, isTrue);
    });

    test('服务端认可且本地时间充足时不打扰用户', () async {
      final storage = _FakeStorage(
        QQMusicConfig(cookie: _cookieExpiringIn(const Duration(days: 90))),
      );
      final notifier = await _pumpNotifier(
        QQMusicSessionNotifier(
          storage,
          _FakeService(const QQMusicSessionCheck.ok('l')),
        ),
      );

      expect(notifier.state.health, QQMusicCookieHealth.healthy);
      expect(notifier.state.shouldPrompt, isFalse);
    });

    test('未绑定 Cookie 时不请求接口也不提示', () async {
      final service = _FakeService(const QQMusicSessionCheck.ok(''));
      final notifier = await _pumpNotifier(
        QQMusicSessionNotifier(_FakeStorage(const QQMusicConfig()), service),
      );

      expect(notifier.state.health, QQMusicCookieHealth.unknown);
      expect(notifier.state.shouldPrompt, isFalse);
      expect(service.calls, 0);
    });

    test('点「稍后」后本次会话不再提示，重新绑定会强制复查', () async {
      final storage = _FakeStorage(
        QQMusicConfig(cookie: _cookieExpiringIn(const Duration(days: 60))),
      );
      final service = _FakeService(const QQMusicSessionCheck.invalid());
      final notifier = await _pumpNotifier(
        QQMusicSessionNotifier(storage, service),
      );

      notifier.dismiss();
      expect(notifier.state.shouldPrompt, isFalse);

      // 节流期内普通 check 不再请求。
      await notifier.check();
      expect(service.calls, 1);

      await notifier.refreshAfterBind();
      expect(service.calls, 2);
      expect(notifier.state.dismissed, isFalse);
    });
  });
}