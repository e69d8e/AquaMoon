import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils/app_toast.dart';
import '../../providers/audio_provider.dart';

class NotificationPlayerSettingsPage extends ConsumerStatefulWidget {
  const NotificationPlayerSettingsPage({super.key});

  @override
  ConsumerState<NotificationPlayerSettingsPage> createState() => _NotificationPlayerSettingsPageState();
}

class _NotificationPlayerSettingsPageState extends ConsumerState<NotificationPlayerSettingsPage>
    with WidgetsBindingObserver {
  bool _hasNotificationPermission = false;
  bool _hasBatteryExemption = false;
  bool _isLoading = true;
  // 水墨专属通知栏（自定义卡片）开关；系统原生媒体通知始终存在，不受此开关影响。
  bool _customEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _customEnabled = ref.read(audioHandlerProvider).customNotificationEnabled;
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(() {
        _hasNotificationPermission = true;
        _hasBatteryExemption = true;
        _isLoading = false;
      });
      return;
    }

    try {
      final notifStatus = await Permission.notification.status;
      bool batteryGranted = true;
      if (Platform.isAndroid) {
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        batteryGranted = batteryStatus.isGranted;
      }

      setState(() {
        _hasNotificationPermission = notifStatus.isGranted;
        _hasBatteryExemption = batteryGranted;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      setState(() {
        _hasBatteryExemption = status.isGranted;
      });
      if (status.isGranted && mounted) {
        AppToast.show(
          context,
          '已成功开启无限制后台运行与省电豁免',
          icon: Icons.battery_charging_full_rounded,
        );
      } else if (mounted) {
        openAppSettings();
      }
    } catch (_) {
      openAppSettings();
    }
  }

  /// 水墨专属通知栏开关。开启时若无通知权限会先申请；关闭时立即撤下
  /// 自定义卡片，系统原生媒体通知保持不变。
  Future<void> _setCustomEnabled(bool enable) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (enable && !_hasNotificationPermission) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() => _hasNotificationPermission = false);
          _showPermissionDeniedDialog();
        }
        return;
      }
      if (mounted) setState(() => _hasNotificationPermission = true);
    }

    setState(() => _customEnabled = enable);
    await ref.read(audioHandlerProvider).setCustomNotificationEnabled(enable);
    if (mounted) {
      AppToast.show(
        context,
        enable ? '已开启水墨专属通知栏，与系统原生媒体通知同时显示' : '已关闭水墨专属通知栏，仅保留系统原生媒体通知',
        icon: enable ? Icons.brush_rounded : Icons.phone_android_rounded,
      );
    }
  }

  /// 仅申请系统通知权限（供排查指南卡片使用），不改变水墨卡片开关。
  Future<void> _requestNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final status = await Permission.notification.request();
    if (!mounted) return;
    setState(() => _hasNotificationPermission = status.isGranted);
    if (status.isGranted) {
      AppToast.show(
        context,
        '已开启通知权限，播放音乐时将在系统通知栏显示播放器',
        icon: Icons.notifications_active_rounded,
      );
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_off_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('需要通知权限'),
          ],
        ),
        content: const Text(
          '显示系统通知栏音乐播放器需要开启通知权限。\n\n由于系统限制，请点击下方按钮前往系统设置页面手动开启「允许通知」。',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('暂不开启'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('前往系统设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知栏音乐播放器'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Enable Switch Card
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '水墨专属通知栏',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                !_hasNotificationPermission
                                    ? '通知权限未开启，开启开关将先申请权限'
                                    : _customEnabled
                                        ? '播放时同时显示水墨专属卡片与系统原生媒体通知'
                                        : '已关闭，仅显示系统原生媒体通知（锁屏/控制中心/蓝牙）',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: !_hasNotificationPermission
                                      ? theme.colorScheme.error
                                      : _customEnabled
                                          ? Colors.green
                                          : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _customEnabled,
                          onChanged: _setCustomEnabled,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. Style Selector Section (Matching the QQ Music UI Style)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '播放器样式',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildStyleCard(
                        context,
                        title: '水墨专属通知栏',
                        subtitle: '专为小米HyperOS / 国产深度定制ROM优化，常驻通知中心',
                        isSelected: _customEnabled,
                        icon: Icons.brush_rounded,
                        accentColor: theme.colorScheme.primary,
                        onTap: () => _setCustomEnabled(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStyleCard(
                        context,
                        title: '系统原生媒体流',
                        subtitle: '遵循 Android MediaSession 标准规范，支持蓝牙与车机',
                        isSelected: !_customEnabled,
                        icon: Icons.phone_android_rounded,
                        accentColor: theme.colorScheme.tertiary,
                        onTap: () => _setCustomEnabled(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '系统原生媒体通知始终开启（受系统通知权限控制），负责锁屏、控制中心与蓝牙/车机媒体卡片；水墨专属卡片可在此开关。两者可同时显示，也可只保留原生通知。',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // 3. System Adaptation Guide (HyperOS / MIUI / ColorOS / OriginOS / EMUI)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '常见手机系统适配排查',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _buildGuideCard(
                  context,
                  icon: Icons.notifications_active_outlined,
                  title: '1. 通知权限与渠道',
                  desc: '确保系统设置中允许「水月音」发送通知，并开启「播放控制」渠道。',
                  isGood: _hasNotificationPermission,
                  goodText: '已授权',
                  actionText: '去授权',
                  onAction: _requestNotificationPermission,
                ),
                const SizedBox(height: 10),

                _buildGuideCard(
                  context,
                  icon: Icons.battery_charging_full_rounded,
                  title: '2. 忽略电池优化（无限制后台）',
                  desc: '若通知栏显示「省电模式」，系统可能会限制后台播放卡片。点击右侧直接申请系统白名单或设为「无限制」。',
                  isGood: _hasBatteryExemption,
                  goodText: '已豁免',
                  actionText: _hasBatteryExemption ? '已开启' : '去申请',
                  onAction: () => _requestBatteryOptimization(),
                ),
                const SizedBox(height: 10),

                _buildGuideCard(
                  context,
                  icon: Icons.tune_rounded,
                  title: '3. 控制中心媒体播放器卡片',
                  desc: '部分手机（如小米/OPPO/vivo）需在「系统设置 -> 通知与控制中心」中开启「媒体播放器 / 媒体控制」开关。',
                  actionText: '了解',
                  onAction: () => openAppSettings(),
                ),

                const SizedBox(height: 24),

                // 4. Open App Settings Button
                FilledButton.tonalIcon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('打开系统应用详情设置'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildStyleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool isSelected,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: accentColor),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: accentColor, size: 22),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    bool? isGood,
    String? goodText,
    required String actionText,
    required VoidCallback onAction,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 22, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 标题用 Flexible：长标题（如「忽略电池优化（无限制后台）」）
                      // 加徽章后会把行宽挤爆，这里让标题自动换行而不是溢出。
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isGood == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            goodText ?? '正常',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionText),
            ),
          ],
        ),
      ),
    );
  }
}
