import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/qq_music_cookie_status.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/listening_stats_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/playback_preferences_provider.dart';
import '../../providers/qq_music_download_provider.dart';
import '../../providers/qq_music_provider.dart';
import '../../providers/qq_music_session_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/backup_service.dart';
import '../../services/qq_music_service.dart';
import '../stats/listening_stats_page.dart';
import '../widgets/aquamoon_mark.dart';
import '../widgets/qq_music_auth_dialog.dart';
import '../widgets/qq_music_quality_picker.dart';
import '../widgets/update_dialog.dart';
import 'audio_effects_settings_page.dart';
import 'lyrics_display_settings_page.dart';
import 'notification_player_settings_page.dart';
import 'theme_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// QQ 音乐下载只适配 Android：默认落在公共下载目录，并依赖原生媒体库登记。
  static bool get _supportsQQMusicDownload =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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

  /// 失效文件清理：先检测、后确认、再移除。
  Future<void> _cleanupMissingFiles(
    BuildContext context,
    WidgetRef ref,
  ) async {
    AppToast.show(context, '正在检测曲库文件完整性...', icon: Icons.search_rounded);
    final missing = await ref
        .read(libraryNotifierProvider.notifier)
        .findMissingFiles();

    if (!context.mounted) return;
    if (missing.isEmpty) {
      AppToast.show(
        context,
        '曲库健康：所有音频文件均可访问',
        icon: Icons.verified_outlined,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现失效歌曲'),
        content: Text(
          '有 ${missing.length} 首歌曲的音频文件已无法访问（可能被移动或删除）。\n\n'
          '前几首：\n${missing.take(5).map((s) => '《${s.title}》').join('、')}${missing.length > 5 ? ' 等' : ''}\n\n'
          '确认从曲库中移除它们吗？（磁盘文件不受影响，重新扫描后可找回）',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final count = await ref
        .read(libraryNotifierProvider.notifier)
        .removeMissingFiles();
    if (context.mounted) {
      AppToast.show(
        context,
        '已移除 $count 首失效歌曲',
        icon: Icons.cleaning_services_rounded,
      );
    }
  }

  /// 从备份文件恢复全部数据。
  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    List<PlatformFile>? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    } catch (_) {
      picked = null;
    }
    // 某些平台取消时可能返回空列表而非 null（List.single 会抛 StateError）。
    if (picked == null || picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认恢复备份？'),
        content: const Text(
          '恢复将覆盖当前的曲库、歌单、收藏、历史、统计与设置。建议先「导出全部数据」留存现状。\n\n恢复完成后需要重启应用生效。',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final summary = await BackupService(
        ref.read(storageServiceProvider),
      ).restoreFromFile(path);
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('恢复完成'),
            content: Text(
              '已恢复 ${summary.songs} 首歌曲、${summary.playlists} 个歌单与 '
              '${summary.historyEntries} 条播放历史。\n\n请重启应用以加载恢复的数据。',
              style: const TextStyle(height: 1.4),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          e.message,
          icon: Icons.error_outline_rounded,
        );
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(
          context,
          '恢复失败，文件可能已损坏',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryCount = ref.watch(
      libraryNotifierProvider.select((s) => s.songs.length),
    );
    final scanProgress = ref.watch(
      libraryNotifierProvider.select(
        (s) => (
          isScanning: s.isScanning,
          text: s.scanProgressText,
          percent: s.scanProgressPercent,
        ),
      ),
    );
    final localSongCount = ref.watch(
      libraryNotifierProvider.select(
        (s) => s.songs.where((song) => song.hasLocalFile).length,
      ),
    );
    final qqFavMeta = ref.watch(
      qqMusicFavoritesProvider.select(
        (s) => (
          isBound: s.isBound,
          mergedCount: s.mergedSongs.length,
          displayLabel: s.config.displayLabel,
          localMatchedCount: s.localMatchedCount,
          isSyncing: s.isSyncing,
        ),
      ),
    );
    final qqSession = ref.watch(qqMusicSessionProvider);
    final todayStats = ref.watch(todayListeningSummaryProvider);
    final themeMode = ref.watch(themeModeProvider);
    final palette = ref.watch(themePaletteProvider);
    final theme = Theme.of(context);

    final appColors = AppColors.of(context);
    final todayDurationText = todayStats.totalDurationSeconds > 0
        ? Formatters.formatListeningDuration(
            Duration(seconds: todayStats.totalDurationSeconds),
            short: true,
          )
        : '0 分钟';

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              // 1. 统一三栏概览卡：本地曲库 · QQ 收藏 · 今日听歌
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: _OverviewMetric(
                              label: '本地曲库',
                              value: '$libraryCount',
                              unit: '首',
                            ),
                          ),
                          Container(
                            width: 0.8,
                            height: 28,
                            color: appColors.subtleDivider,
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => QQMusicAuthDialog.show(context),
                              child: _OverviewMetric(
                                label: qqFavMeta.isBound ? 'QQ 收藏' : 'QQ 音乐',
                                value: qqFavMeta.isBound
                                    ? '${qqFavMeta.mergedCount}'
                                    : '未绑定',
                                unit: qqFavMeta.isBound ? '首' : null,
                                accent: qqFavMeta.isBound,
                              ),
                            ),
                          ),
                          Container(
                            width: 0.8,
                            height: 28,
                            color: appColors.subtleDivider,
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ListeningStatsPage(),
                                  ),
                                );
                              },
                              child: _OverviewMetric(
                                label: '今日聆听',
                                value: todayDurationText,
                                accent: todayStats.totalDurationSeconds > 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.favorite_rounded,
                        color: appColors.favorite,
                        size: 21,
                      ),
                      title: const Text(
                        'QQ 音乐「我喜欢」收藏同步',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            qqFavMeta.isBound
                                ? '已连接 ${qqFavMeta.displayLabel}'
                                      '${qqFavMeta.localMatchedCount > 0 ? ' · 已关联本地 ${qqFavMeta.localMatchedCount} 首' : ''}'
                                : '配置 QQ 号、歌单链接或 Cookie 同步云端收藏',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (qqFavMeta.isBound &&
                              qqSession.health !=
                                  QQMusicCookieHealth.unknown) ...[
                            const SizedBox(height: 2),
                            Text(
                              qqSession.summary,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: qqSession.health.needsAttention
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: qqFavMeta.isBound
                          ? IconButton(
                              icon: qqFavMeta.isSyncing
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.sync_rounded,
                                      color: theme.colorScheme.primary,
                                    ),
                              tooltip: '立即同步',
                              onPressed: qqFavMeta.isSyncing
                                  ? null
                                  : () async {
                                      try {
                                        final msg = await ref
                                            .read(
                                              qqMusicFavoritesProvider.notifier,
                                            )
                                            .syncFavorites(silent: false);
                                        if (context.mounted && msg.isNotEmpty) {
                                          AppToast.show(
                                            context,
                                            msg,
                                            icon: Icons
                                                .check_circle_outline_rounded,
                                          );
                                        }
                                      } on QQMusicApiException catch (e) {
                                        if (context.mounted) {
                                          AppToast.show(
                                            context,
                                            e.message,
                                            icon: Icons.error_outline_rounded,
                                          );
                                        }
                                      } catch (_) {
                                        if (context.mounted) {
                                          AppToast.show(
                                            context,
                                            '同步失败，请检查网络后重试',
                                            icon: Icons.error_outline_rounded,
                                          );
                                        }
                                      }
                                    },
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => QQMusicAuthDialog.show(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.insights_rounded,
                        color: theme.colorScheme.primary,
                        size: 21,
                      ),
                      title: const Text(
                        '听歌统计与时长',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        '查看日 / 周 / 月 / 年听歌趋势与热力图',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ListeningStatsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              if (_supportsQQMusicDownload) ...[
                const SizedBox(height: 12),
                const _QQMusicDownloadCard(),
              ],

          // Scanning Progress Card (if scanning/enriching)
          if (scanProgress.isScanning) ...[
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
                          scanProgress.text ?? '正在处理曲库数据...',
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
                  if (scanProgress.percent != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: scanProgress.percent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Section 1: 曲库管理与歌曲导入
          _sectionTitle(theme, '曲库与文件管理'),
          Card(
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
                  leading: const Icon(Icons.lyrics_outlined),
                  title: const Text(
                    '扫描本地歌词文件',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '查找与音频同目录同名的 .lrc 文件补齐歌词',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final count = await ref
                        .read(libraryNotifierProvider.notifier)
                        .scanSidecarLyrics();
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        count > 0 ? '已为 $count 首歌曲补齐本地歌词！' : '未发现可补齐的本地歌词',
                        icon: count > 0
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                      );
                    }
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text(
                    '清理失效歌曲',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '检测已被移动或删除的音频文件并从曲库移除',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _cleanupMissingFiles(context, ref),
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
          _sectionTitle(theme, '播放与系统适配'),
          Card(
            child: Column(
              children: [
                if (Platform.isAndroid) ...[
                  ListTile(
                    leading: const Icon(Icons.equalizer_rounded),
                    title: const Text(
                      '音效与均衡器',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      '淡入淡出与多频段均衡器（Android 专属）',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AudioEffectsSettingsPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                ],
                _PreferLocalPlaybackTile(
                  localSongCount: localSongCount,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.lyrics_rounded),
                  title: const Text(
                    '歌词显示设置',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '字号、行距、当前行高亮与自动滚动位置',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LyricsDisplaySettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text(
                    '通知栏音乐播放器设置',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '系统通知卡片、小米 HyperOS / 鸿蒙锁屏常驻与省电保活',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationPlayerSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section: 外观
          _sectionTitle(theme, '外观'),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('浅色'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('深色'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('系统'),
                          ),
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
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text(
                    '主题配色',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '当前：${palette.name} · ${palette.tagline}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ThemeSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section 3.5: 数据备份与恢复
          _sectionTitle(theme, '数据备份与恢复'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text(
                    '导出全部数据',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '曲库、歌单、收藏、历史、统计与设置打包为 JSON 备份',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final result = await BackupService(
                      ref.read(storageServiceProvider),
                    ).exportBackup();
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        result.message,
                        icon: result.success
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                      );
                    }
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text(
                    '从备份恢复',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '选择此前导出的水月音备份文件，恢复后需重启应用',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _restoreBackup(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section 4: 关于应用 — 更新检查
          const _UpdateSettingsCard(),

          const SizedBox(height: 20),

          // Section 4: 关于应用
          Center(
            child: Column(
              children: [
                const AquaMoonMark(size: 32),
                const SizedBox(height: 8),
                const Text(
                  '水月音 AquaMoon',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '静心聆听 · 素纸墨韵本地音乐播放器',
                  style: TextStyle(
                    fontSize: 11.5,
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
                    fontFeatures: const [FontFeature.tabularFigures()],
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
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final bool accent;

  const _OverviewMetric({
    required this.label,
    required this.value,
    this.unit,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: accent
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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

    return Card(
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

/// 「优先播放本地音频」开关（设置 → 播放与系统适配）。
///
/// 打开后，音频引擎在播放任何在线曲目之前，先按标题 / 歌手 / 时长在本地
/// 曲库里找同一首歌；命中就播本地文件，省流量且不受在线版权下架影响。
class _PreferLocalPlaybackTile extends ConsumerWidget {
  const _PreferLocalPlaybackTile({required this.localSongCount});

  /// 曲库中带真实本地文件的歌曲数量，用于告知用户可匹配的基数。
  final int localSongCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(preferLocalPlaybackProvider);

    return ListTile(
      leading: const Icon(Icons.download_done_rounded),
      title: const Text(
        '优先播放本地音频',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        enabled
            ? localSongCount > 0
                  ? '已开启 · 在线曲目若曲库中有同一首歌，直接播放本地文件（可匹配 $localSongCount 首）'
                  : '已开启 · 曲库暂无本地音频，导入后会自动生效'
            : '在线曲目若曲库中已有同一首歌，改为播放本地文件，省流量、音质更稳',
        style: const TextStyle(fontSize: 12, height: 1.35),
      ),
      trailing: Switch(
        value: enabled,
        onChanged: (value) {
          ref
              .read(preferLocalPlaybackProvider.notifier)
              .setPreferLocalPlayback(value);
        },
      ),
      onTap: () {
        ref
            .read(preferLocalPlaybackProvider.notifier)
            .setPreferLocalPlayback(!enabled);
      },
    );
  }
}

/// QQ 音乐下载设置卡（仅 Android 展示）。
///
/// 三件事都收在这里：默认下载音质、保存文件夹、下载后是否自动进曲库。
/// 音质与文件夹同时用于「发现页 → 更多 → 下载到本地」的选择面板，用户在
/// 这里设好之后，下载时就不必每次重复选择。
class _QQMusicDownloadCard extends ConsumerWidget {
  const _QQMusicDownloadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(qqMusicDownloadSettingsProvider);
    final downloadState = ref.watch(qqMusicDownloadProvider);
    final hasCookie = ref.watch(qqMusicFavoritesProvider).config.hasCookie;
    final activeTasks = downloadState.activeTasks;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.download_for_offline_rounded),
            title: const Text(
              'QQ 音乐下载',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              activeTasks.isEmpty
                  ? '保存到 ${settings.directoryLabel}'
                  : '正在下载 ${activeTasks.length} 首 · 保存到 ${settings.directoryLabel}',
              maxLines: 2,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          if (activeTasks.isNotEmpty) ...[
            const Divider(height: 1, indent: 56),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                children: [
                  for (final task in activeTasks.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                task.progress == null
                                    ? '下载中'
                                    : '${(task.progress! * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: task.progress,
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.high_quality_rounded),
            title: const Text(
              '下载音质',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.quality.requiresCookie && !hasCookie
                  ? '${settings.quality.label} · 未绑定 Cookie 时将自动回退'
                  : settings.quality.label,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final picked = await showQQMusicQualityPicker(
                context,
                title: '默认下载音质',
                subtitle: '发现页下载时仍可临时改选其它音质',
                selected: settings.quality,
                hasCookie: hasCookie,
              );
              if (picked == null || !context.mounted) return;
              await ref
                  .read(qqMusicDownloadSettingsProvider.notifier)
                  .setQuality(picked);
              if (!context.mounted) return;
              AppToast.show(
                context,
                '下载音质已设为 ${picked.label}',
                icon: Icons.high_quality_rounded,
              );
            },
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text(
              '保存文件夹',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.directoryLabel,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.directory.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                    tooltip: '恢复默认文件夹',
                    onPressed: () async {
                      await ref
                          .read(qqMusicDownloadSettingsProvider.notifier)
                          .resetDirectory();
                      if (!context.mounted) return;
                      AppToast.show(context, '已恢复默认下载文件夹');
                    },
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => _pickDirectory(context, ref),
          ),
          const Divider(height: 1, indent: 56),
          SwitchListTile(
            secondary: const Icon(Icons.playlist_add_check_rounded),
            title: const Text(
              '下载后自动加入曲库',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '关闭后只写文件，需要时再到曲库手动导入',
              style: TextStyle(fontSize: 12),
            ),
            value: settings.addToLibrary,
            onChanged: (value) => ref
                .read(qqMusicDownloadSettingsProvider.notifier)
                .setAddToLibrary(value),
          ),
        ],
      ),
    );
  }

  /// 选择下载文件夹：先确认目录真的可写，不可写就不保存这个设置，
  /// 免得用户以为换了目录、下载却一直落在别处。
  Future<void> _pickDirectory(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    final current = storage.getQQMusicDownloadDirectory();

    String? picked;
    try {
      picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择下载文件夹',
        initialDirectory: current.isEmpty ? null : current,
      );
    } catch (_) {
      if (context.mounted) AppToast.show(context, '无法打开文件夹选择器');
      return;
    }
    if (picked == null || picked.trim().isEmpty || !context.mounted) return;

    // 公共目录写入依赖存储权限；先尝试申请，被拒也会走下面的可写性探测。
    try {
      await ref.read(libraryNotifierProvider.notifier).requestStoragePermission();
    } catch (_) {}
    if (!context.mounted) return;

    final resolved = await ref
        .read(qqMusicDownloadServiceProvider)
        .prepareDownloadDirectory(preferred: picked);
    if (!context.mounted) return;

    final normalized = picked.replaceFirst(RegExp(r'/+$'), '');
    final resolvedNormalized = resolved.replaceFirst(RegExp(r'/+$'), '');
    final writable =
        resolvedNormalized == normalized || resolved == picked;

    if (!writable) {
      await ref.read(qqMusicDownloadSettingsProvider.notifier).resetDirectory();
      if (!context.mounted) return;
      AppToast.show(
        context,
        '该文件夹不可写，已改用默认目录；如需写入请授予「所有文件访问权限」',
        icon: Icons.info_outline_rounded,
        duration: const Duration(milliseconds: 3000),
        maxLines: 2,
      );
      return;
    }

    await ref
        .read(qqMusicDownloadSettingsProvider.notifier)
        .setDirectory(picked);
    if (!context.mounted) return;
    AppToast.show(
      context,
      '下载文件夹已设为 $picked',
      icon: Icons.folder_rounded,
      duration: const Duration(milliseconds: 2200),
      maxLines: 2,
    );
  }
}
