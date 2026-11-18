import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/qq_music_cookie_status.dart';
import '../services/qq_music_service.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';
import 'qq_music_provider.dart';

/// QQ 音乐 Cookie 会话状态：本地有效期 + 服务端校验结论。
class QQMusicSessionState {
  /// 本地按 Cookie 时间戳解析出的有效期。
  final QQMusicCookieStatus localStatus;

  /// 服务端校验结论；未校验时为 null。
  final QQMusicSessionCheck? serverCheck;

  /// 是否正在校验。
  final bool isChecking;

  /// 最近一次校验完成的时间。
  final DateTime? checkedAt;

  /// 用户是否已经关掉这次的提示横幅。
  final bool dismissed;

  const QQMusicSessionState({
    this.localStatus = QQMusicCookieStatus.unbound,
    this.serverCheck,
    this.isChecking = false,
    this.checkedAt,
    this.dismissed = false,
  });

  /// 综合结论：服务端明确说失效时以服务端为准，否则看本地时间戳。
  QQMusicCookieHealth get health {
    final server = serverCheck;
    if (server != null) {
      if (!server.valid) return QQMusicCookieHealth.expired;
      if (localStatus.health == QQMusicCookieHealth.expired ||
          localStatus.health == QQMusicCookieHealth.expiringSoon) {
        return localStatus.health;
      }
      return QQMusicCookieHealth.healthy;
    }
    return localStatus.health;
  }

  /// 是否应该在界面上提示用户重新绑定。
  bool get shouldPrompt => health.needsAttention && !dismissed;

  /// 给用户看的一句话摘要。
  String get summary {
    if (health == QQMusicCookieHealth.unknown) {
      return serverCheck?.message ?? localStatus.describe(DateTime.now());
    }
    final parts = <String>[
      localStatus.describe(DateTime.now()),
      if (serverCheck?.valid == false && serverCheck?.message != null)
        serverCheck!.message!,
    ];
    return parts.join(' · ');
  }

  QQMusicSessionState copyWith({
    QQMusicCookieStatus? localStatus,
    QQMusicSessionCheck? serverCheck,
    bool? isChecking,
    DateTime? checkedAt,
    bool? dismissed,
  }) {
    return QQMusicSessionState(
      localStatus: localStatus ?? this.localStatus,
      serverCheck: serverCheck ?? this.serverCheck,
      isChecking: isChecking ?? this.isChecking,
      checkedAt: checkedAt ?? this.checkedAt,
      dismissed: dismissed ?? this.dismissed,
    );
  }
}

/// 维护 QQ 音乐 Cookie 的健康度：打开发现页 / 设置页时按需校验，
/// 结果缓存 [throttle] 时间，避免每次进页面都打一次接口。
class QQMusicSessionNotifier extends StateNotifier<QQMusicSessionState> {
  final StorageService _storageService;
  final QQMusicService _qqMusicService;

  static const Duration throttle = Duration(minutes: 30);

  QQMusicSessionNotifier(this._storageService, this._qqMusicService)
    : super(_initialState(_storageService)) {
    // 后台补一次校验，界面先按本地时间戳渲染。
    check(force: false);
  }

  static QQMusicSessionState _initialState(StorageService storage) {
    final config = storage.getQQMusicConfig();
    return QQMusicSessionState(
      localStatus: QQMusicCookieStatus.parse(config.cookie),
    );
  }

  /// 校验 Cookie；[force] 为 false 时按 [throttle] 节流。
  Future<void> check({bool force = false}) async {
    if (state.isChecking) return;
    final now = DateTime.now();
    final checkedAt = state.checkedAt;
    if (!force &&
        checkedAt != null &&
        now.difference(checkedAt) < throttle &&
        state.serverCheck != null) {
      return;
    }

    final config = _storageService.getQQMusicConfig();
    final localStatus = QQMusicCookieStatus.parse(config.cookie);
    if (!config.hasCookie) {
      state = QQMusicSessionState(
        localStatus: localStatus,
        checkedAt: now,
        dismissed: state.dismissed,
      );
      return;
    }

    state = state.copyWith(localStatus: localStatus, isChecking: true);
    final result = await _qqMusicService.checkSession(config);
    if (!mounted) return;
    state = QQMusicSessionState(
      localStatus: localStatus,
      serverCheck: result,
      checkedAt: DateTime.now(),
      dismissed: state.dismissed,
    );
  }

  /// 用户点了「稍后」：本次会话内不再弹提示。
  void dismiss() {
    state = state.copyWith(dismissed: true);
  }

  /// 重新绑定 Cookie 后调用：清掉旧结论并立刻重新校验。
  Future<void> refreshAfterBind() async {
    state = QQMusicSessionState(
      localStatus: QQMusicCookieStatus.parse(
        _storageService.getQQMusicConfig().cookie,
      ),
    );
    await check(force: true);
  }
}

final qqMusicSessionProvider =
    StateNotifierProvider<QQMusicSessionNotifier, QQMusicSessionState>((ref) {
      return QQMusicSessionNotifier(
        ref.watch(storageServiceProvider),
        ref.watch(qqMusicServiceProvider),
      );
    });