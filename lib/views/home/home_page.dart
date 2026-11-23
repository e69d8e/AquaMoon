import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../providers/audio_provider.dart';
import '../../providers/qq_music_provider.dart';
import '../../providers/update_provider.dart';
import '../favorites/unmatched_songs_page.dart';
import '../history/recent_plays_page.dart';
import '../online_search/online_search_page.dart';
import '../player/mini_player.dart';
import '../qq_music/qq_music_discovery_page.dart';
import '../settings/settings_page.dart';
import '../stats/listening_stats_page.dart';
import '../widgets/aquamoon_mark.dart';
import '../widgets/glass_container.dart';
import '../widgets/update_dialog.dart';
import 'tabs/all_songs_tab.dart';
import 'tabs/favorites_tab.dart';
import 'tabs/playlists_tab.dart';

final currentTabProvider = StateProvider<int>((ref) => 0);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  static const List<Widget> _tabs = [
    AllSongsTab(),
    PlaylistsTab(),
    FavoritesTab(),
  ];

  static const List<String> _tabTitles = ['曲库', '歌单', '收藏'];

  bool _batteryPrompted = false;
  DateTime _lastNavTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Guards against double-taps pushing the same page twice.
  void _pushPage(Widget Function() builder) {
    final now = DateTime.now();
    if (now.difference(_lastNavTime) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastNavTime = now;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => builder()));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestAppPermissions();
    _checkForUpdateOnStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user comes back from the system settings page.
    if (state == AppLifecycleState.resumed) {
      _requestAppPermissions(silent: true);
    }
  }

  /// Request Notification and Battery Optimization exemption at startup for Android 13+ Notification Drawer & Lockscreen media controls
  Future<void> _requestAppPermissions({bool silent = false}) async {
    if (kIsWeb) return;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        var notifStatus = await Permission.notification.status;
        if (!notifStatus.isGranted) {
          notifStatus = await Permission.notification.request();
        }
        if (!notifStatus.isGranted && !silent && mounted) {
          _showNotificationGuide();
        }
        if (Platform.isAndroid && !_batteryPrompted) {
          _batteryPrompted = true;
          final batteryStatus =
              await Permission.ignoreBatteryOptimizations.status;
          if (!batteryStatus.isGranted && mounted) {
            // Explain why before triggering the system whitelist dialog.
            final proceed = await _showBatteryExplanation();
            if (proceed) {
              await Permission.ignoreBatteryOptimizations.request();
            }
          }
        }
      } catch (_) {
        // Never let permission checks crash the home page.
      }
    }
  }

  /// 启动后延迟静默检查 GitHub 新版本（每 24 小时最多一次），
  /// 仅在发现新版本时弹窗提示；失败或已是最新保持静默。
  Future<void> _checkForUpdateOnStartup() async {
    // 等启动加载与权限弹窗稳定后再检查，避免开场争抢网络与注意力。
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    try {
      if (!ref.read(autoCheckUpdatesProvider)) return;
      final storage = ref.read(storageServiceProvider);
      final lastCheck = storage.getLastUpdateCheckTime();
      final now = DateTime.now();
      if (lastCheck != null &&
          now.difference(lastCheck) < const Duration(hours: 24)) {
        return;
      }
      final currentVersion = await ref.read(appVersionProvider.future);
      final info = await ref
          .read(updateServiceProvider)
          .checkForUpdate(currentVersion: currentVersion);
      await storage.saveLastUpdateCheckTime(now);
      if (!mounted || info == null) return;
      // 若此时仍有权限引导或其它弹窗正在前台显示，避免连续堆叠打断用户。
      if (ModalRoute.of(context)?.isCurrent != true) return;
      await showUpdateDialog(context, info);
    } catch (_) {
      // 自动检查失败不打扰用户。
    }
  }

  Future<bool> _showBatteryExplanation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保持后台播放稳定'),
        content: const Text(
          '为了防止系统在后台清理播放器、中断音乐播放，水月音希望加入电池优化白名单。你也可以稍后在系统设置中修改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('允许'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showNotificationGuide() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('通知权限未开启'),
        content: const Text('开启通知权限后，播放器才能在通知栏和锁屏显示播放控制，避免后台播放被系统误清。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('暂不'),
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

  int _watchUnmatchedCount() {
    try {
      return ref.watch(unmatchedFavoritesProvider.select((l) => l.length));
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);
    final unmatchedCount = _watchUnmatchedCount();
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    // Surface playback failures (missing/corrupt file) wherever the user is.
    ref.listen<AsyncValue<String>>(playbackErrorStreamProvider, (prev, next) {
      final message = next.valueOrNull;
      if (message != null) {
        AppToast.show(
          context,
          message,
          icon: Icons.error_outline_rounded,
          duration: const Duration(milliseconds: 2800),
        );
      }
    });

    final isLight = theme.brightness == Brightness.light;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isLight
          ? Brightness.dark
          : Brightness.light,
    );

    final currentTabTitle = _tabTitles[currentTab];

    if (isDesktop) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          body: Row(
            children: [
              _buildDesktopSidebar(
                context: context,
                currentTab: currentTab,
                unmatchedCount: unmatchedCount,
              ),
              VerticalDivider(
                thickness: 0.8,
                width: 0.8,
                color: appColors.subtleDivider,
              ),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // 极简顶栏：只承载当前栏目名称，不再堆砌六个孤立图标。
                        Semantics(
                          header: true,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 58),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              currentTabTitle,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: IndexedStack(
                            index: currentTab,
                            children: [
                              for (var i = 0; i < _tabs.length; i++)
                                TickerMode(
                                  enabled: currentTab == i,
                                  child: _tabs[i],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: MiniPlayer(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile Layout with Frosted Glass NavigationBar
    //
    // extendBody 让列表内容从磨砂导航栏与迷你播放器下方滚过，玻璃效果才
    // 有内容可模糊；body 的 MediaQuery.padding.bottom 因此被抬升为底部
    // 导航栏总高度，迷你播放器与列表留白都据此避让。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 16,
          title: Row(
            children: [
              const AquaMoonMark(size: 24),
              const SizedBox(width: 9),
              Text(
                currentTabTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.more_vert_rounded, size: 22),
                  if (unmatchedCount > 0)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: '更多功能',
              onSelected: (value) {
                switch (value) {
                  case 'stats':
                    _pushPage(() => const ListeningStatsPage());
                    break;
                  case 'recent':
                    _pushPage(() => const RecentPlaysPage());
                    break;
                  case 'unmatched':
                    _pushPage(() => const UnmatchedSongsPage());
                    break;
                  case 'online':
                    _pushPage(() => const OnlineSearchPage());
                    break;
                  case 'qq_discovery':
                    _pushPage(() => const QQMusicDiscoveryPage());
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'stats',
                  child: Row(
                    children: [
                      Icon(Icons.insights_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('听歌统计'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'recent',
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('最近播放'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'unmatched',
                  child: Row(
                    children: [
                      const Icon(Icons.link_off_rounded, size: 19),
                      const SizedBox(width: 10),
                      const Text('本地未匹配歌曲'),
                      if (unmatchedCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.13,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unmatchedCount',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'qq_discovery',
                  child: Row(
                    children: [
                      Icon(Icons.radio_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('QQ 音乐在线发现'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'online',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_download_outlined, size: 19),
                      SizedBox(width: 10),
                      Text('全网检索与下载'),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 21),
              tooltip: '设置',
              onPressed: () => _pushPage(() => const SettingsPage()),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Builder(
          builder: (bodyContext) {
            final bottomChromeHeight = MediaQuery.paddingOf(
              bodyContext,
            ).bottom;
            return Stack(
              children: [
                IndexedStack(
                  index: currentTab,
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      TickerMode(
                        enabled: currentTab == i,
                        child: _tabs[i],
                      ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomChromeHeight,
                  child: const MiniPlayer(),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: GlassContainer(
          blurSigma: 26,
          tint: theme.colorScheme.surface.withValues(
            alpha: isLight ? 0.80 : 0.72,
          ),
          border: Border(
            top: BorderSide(color: appColors.glassBorder, width: 0.8),
          ),
          child: NavigationBar(
            height:
                66 +
                ((MediaQuery.textScalerOf(context).scale(1.0) - 1.0).clamp(
                      0.0,
                      1.5,
                    ) *
                    20),
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            selectedIndex: currentTab,
            onDestinationSelected: (index) {
              ref.read(currentTabProvider.notifier).state = index;
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.music_note_outlined),
                selectedIcon: Icon(Icons.music_note_rounded),
                label: '曲库',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music_rounded),
                label: '歌单',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: '收藏',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 桌面端静谧侧栏：品牌徽标、核心三栏、探索与工具、以及置底设置入口。
  Widget _buildDesktopSidebar({
    required BuildContext context,
    required int currentTab,
    required int unmatchedCount,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Container(
      width: 216,
      color: theme.colorScheme.surface.withValues(alpha: isLight ? 0.72 : 0.85),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 品牌头
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 16, 18),
              child: Row(
                children: [
                  const AquaMoonMark(size: 28),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '水月音',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'AquaMoon',
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.4,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.72,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 核心导航
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _SidebarItem(
                    icon: Icons.music_note_outlined,
                    selectedIcon: Icons.music_note_rounded,
                    label: '曲库',
                    selected: currentTab == 0,
                    onTap: () =>
                        ref.read(currentTabProvider.notifier).state = 0,
                  ),
                  const SizedBox(height: 3),
                  _SidebarItem(
                    icon: Icons.queue_music_outlined,
                    selectedIcon: Icons.queue_music_rounded,
                    label: '歌单',
                    selected: currentTab == 1,
                    onTap: () =>
                        ref.read(currentTabProvider.notifier).state = 1,
                  ),
                  const SizedBox(height: 3),
                  _SidebarItem(
                    icon: Icons.favorite_border_rounded,
                    selectedIcon: Icons.favorite_rounded,
                    label: '收藏',
                    selected: currentTab == 2,
                    onTap: () =>
                        ref.read(currentTabProvider.notifier).state = 2,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Divider(height: 1),
                  ),
                  _SidebarItem(
                    icon: Icons.history_rounded,
                    label: '最近播放',
                    tooltip: '最近播放',
                    onTap: () => _pushPage(() => const RecentPlaysPage()),
                  ),
                  const SizedBox(height: 2),
                  _SidebarItem(
                    icon: Icons.insights_rounded,
                    label: '听歌统计',
                    tooltip: '听歌统计',
                    onTap: () => _pushPage(() => const ListeningStatsPage()),
                  ),
                  const SizedBox(height: 2),
                  _SidebarItem(
                    icon: Icons.radio_rounded,
                    label: 'QQ 音乐发现',
                    tooltip: 'QQ 音乐在线发现',
                    onTap: () => _pushPage(() => const QQMusicDiscoveryPage()),
                  ),
                  const SizedBox(height: 2),
                  _SidebarItem(
                    icon: Icons.cloud_download_outlined,
                    label: '全网检索',
                    tooltip: '全网在线歌曲与歌词检索',
                    onTap: () => _pushPage(() => const OnlineSearchPage()),
                  ),
                  const SizedBox(height: 2),
                  _SidebarItem(
                    icon: Icons.link_off_rounded,
                    label: '未匹配歌曲',
                    tooltip: '本地未匹配歌曲',
                    badgeCount: unmatchedCount,
                    onTap: () => _pushPage(() => const UnmatchedSongsPage()),
                  ),
                ],
              ),
            ),

            // 置底设置入口
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: _SidebarItem(
                icon: Icons.settings_outlined,
                label: '设置',
                tooltip: '设置',
                onTap: () => _pushPage(() => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final String? tooltip;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
    this.selected = false,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: isLight ? 0.11 : 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(selected ? (selectedIcon ?? icon) : icon, size: 19, color: fg),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: item);
    }
    return item;
  }
}
