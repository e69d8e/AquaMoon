import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/listening_stats_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../stats/listening_stats_page.dart';
import '../widgets/update_dialog.dart';
import 'notification_player_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// Shown when storage scans fail due to missing permission.
  void _showStoragePermissionGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('存储权限未授予'),
        content: const Text('扫描本地音乐需要存储权限。请在系统设置中授予后重试，否则无法读取设备上的音频文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              openAppSettings();
            },
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryNotifierProvider);
    final todayStats = ref.watch(todayListeningSummaryProvider);
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Library Management Header / Info Card
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.library_music_rounded,
                      color: theme.colorScheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '曲库概览',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '当前已收录 ${libraryState.songs.length} 首本地音频',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 2. Listening Stats Entry Card
          Card(
            elevation: 0,
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ListeningStatsPage()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.18,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.insights_rounded,
                        color: theme.colorScheme.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text(
                                '听歌统计与时长',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            todayStats.totalDurationSeconds > 0
                                ? '今日已听歌 ${Formatters.formatListeningDuration(Duration(seconds: todayStats.totalDurationSeconds))} · 点击查看日/周/月/年统计'
                                : '今日暂无听歌 · 点击查看历史日/周/月/年统计',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Scanning Progress Card (if scanning/enriching)
          if (libraryState.isScanning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          libraryState.scanProgressText ?? '正在处理曲库数据...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (libraryState.scanProgressPercent != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: libraryState.scanProgressPercent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Section 1: 曲库管理与歌曲导入
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              '曲库与文件管理',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined),
                  title: const Text(
                    '导入音频文件',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '选择单个或多个音频 (FLAC / MP3 / M4A / WAV 等)',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final count = await ref
                        .read(libraryNotifierProvider.notifier)
                        .importFiles();
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        count > 0 ? '成功导入 $count 首歌曲！' : '未导入新歌曲',
                        icon: count > 0
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                      );
                    }
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text(
                    '扫描指定文件夹',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '选择文件夹并自动递归检索其中的所有音频',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    try {
                      final count = await ref
                          .read(libraryNotifierProvider.notifier)
                          .importFolder();
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          count > 0 ? '成功扫描并导入 $count 首歌曲！' : '该目录未发现新音频文件',
                          icon: count > 0
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                        );
                      }
                    } on StoragePermissionDeniedException {
                      if (context.mounted) _showStoragePermissionGuide(context);
                    }
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.devices_other_outlined),
                  title: const Text(
                    '快速扫描系统音乐目录',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '自动检测手机/系统的 Music 与 Download 文件夹',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    try {
                      final count = await ref
                          .read(libraryNotifierProvider.notifier)
                          .scanSystemMusicDirectory();
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          count > 0 ? '成功扫描并导入 $count 首系统音频！' : '系统目录未发现新音频',
                          icon: count > 0
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                        );
                      }
                    } on StoragePermissionDeniedException {
                      if (context.mounted) _showStoragePermissionGuide(context);
                    }
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    '智能补齐所有封面与歌词',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  subtitle: const Text(
                    '一键检索在线库，为缺失封面和歌词的歌曲自动补全',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    // Long network task across the whole library — confirm first.
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('开始智能补齐？'),
                        content: const Text(
                          '将为曲库中缺失封面或歌词的歌曲逐一检索在线数据，可能消耗一些流量与时间。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('开始'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;

                    final onlineService = ref.read(
                      onlineMetadataServiceProvider,
                    );
                    final result = await ref
                        .read(libraryNotifierProvider.notifier)
                        .batchAutoMatchOnlineMetadata(onlineService);
                    if (context.mounted) {
                      if (result.total == 0) {
                        AppToast.show(
                          context,
                          '所有歌曲已有完整封面与歌词',
                          icon: Icons.info_outline_rounded,
                        );
                      } else if (result.allFailed) {
                        AppToast.show(
                          context,
                          '网络异常，匹配失败，请检查网络后重试',
                          icon: Icons.error_outline_rounded,
                        );
                      } else {
                        AppToast.show(
                          context,
                          '成功智能补齐 ${result.enriched} 首歌曲！',
                          icon: Icons.check_circle_outline_rounded,
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section 3: 播放与通知设置
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              '播放与系统适配',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text(
                '通知栏音乐播放器设置',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '系统通知卡片、小米 HyperOS / 鸿蒙锁屏常驻与省电保活',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationPlayerSettingsPage(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Section: 外观
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              '外观',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.contrast_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      '主题模式',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                      ButtonSegment(value: ThemeMode.system, label: Text('系统')),
                    ],
                    selected: {themeMode},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 12),
                      ),
                    ),
                    onSelectionChanged: (selection) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Section 4: 关于应用 — 更新检查
          const _UpdateSettingsCard(),

          const SizedBox(height: 20),

          // Section 4: 关于应用
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 28,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 6),
                const Text(
                  '水月音 SoundCraft',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '极简纯粹 · 本地高保真音乐播放器',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ref
                      .watch(appVersionProvider)
                      .when(
                        data: (version) => 'v$version',
                        loading: () => '',
                        error: (_, _) => '',
                      ),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// 「检查更新」入口 + 自动检查开关（设置 → 关于应用）。
class _UpdateSettingsCard extends ConsumerStatefulWidget {
  const _UpdateSettingsCard();

  @override
  ConsumerState<_UpdateSettingsCard> createState() =>
      _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends ConsumerState<_UpdateSettingsCard> {
  bool _checking = false;

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final currentVersion = await ref.read(appVersionProvider.future);
      final info = await ref
          .read(updateServiceProvider)
          .checkForUpdate(currentVersion: currentVersion);
      // 手动检查同样计入节流，避免随后启动又自动弹窗。
      await ref
          .read(storageServiceProvider)
          .saveLastUpdateCheckTime(DateTime.now());
      if (!mounted) return;
      if (info != null) {
        await showUpdateDialog(context, info);
      } else {
        AppToast.show(
          context,
          '当前已是最新版本 v$currentVersion！',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          '检查更新失败，请检查网络后重试',
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoCheck = ref.watch(autoCheckUpdatesProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text(
              '检查更新',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              ref
                  .watch(appVersionProvider)
                  .when(
                    data: (version) => '当前版本 v$version',
                    loading: () => '正在读取版本信息…',
                    error: (_, _) => '无法读取版本信息',
                  ),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: _checking ? null : _checkForUpdate,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.autorenew_rounded),
            title: const Text(
              '自动检查更新',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '启动时自动检查，每 24 小时最多一次',
              style: TextStyle(fontSize: 12),
            ),
            trailing: Switch(
              value: autoCheck,
              onChanged: (enabled) {
                ref
                    .read(autoCheckUpdatesProvider.notifier)
                    .setAutoCheckUpdates(enabled);
              },
            ),
            onTap: () {
              ref
                  .read(autoCheckUpdatesProvider.notifier)
                  .setAutoCheckUpdates(!autoCheck);
            },
          ),
        ],
      ),
    );
  }
}
