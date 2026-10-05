import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import '../../core/utils/app_toast.dart';
import '../../providers/audio_provider.dart';
import '../../providers/update_provider.dart';
import '../online_search/online_search_page.dart';
import '../player/mini_player.dart';
import '../history/recent_plays_page.dart';
import '../settings/settings_page.dart';
import '../stats/listening_stats_page.dart';
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
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => builder()));
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

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 720;

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

    if (isDesktop) {
      // Desktop / Tablet Layout with NavigationRail
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: currentTab,
                onDestinationSelected: (index) {
                  ref.read(currentTabProvider.notifier).state = index;
                },
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '水月音',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.music_note_outlined),
                    selectedIcon: Icon(Icons.music_note_rounded),
                    label: Text('曲库'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.queue_music_outlined),
                    selectedIcon: Icon(Icons.queue_music_rounded),
                    label: Text('歌单'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.favorite_border_rounded),
                    selectedIcon: Icon(Icons.favorite_rounded),
                    label: Text('收藏'),
                  ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        AppBar(
                          title: Text(_tabTitles[currentTab]),
                          automaticallyImplyLeading: false,
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.insights_rounded),
                              tooltip: '听歌统计',
                              onPressed: () =>
                                  _pushPage(() => const ListeningStatsPage()),
                            ),
                            IconButton(
                              icon: const Icon(Icons.history_rounded),
                              tooltip: '最近播放',
                              onPressed: () =>
                                  _pushPage(() => const RecentPlaysPage()),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cloud_download_outlined),
                              tooltip: '全网在线歌曲与歌词检索',
                              onPressed: () =>
                                  _pushPage(() => const OnlineSearchPage()),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined),
                              tooltip: '设置',
                              onPressed: () =>
                                  _pushPage(() => const SettingsPage()),
                            ),
                          ],
                        ),
                        Expanded(
                          child: IndexedStack(
                            index: currentTab,
                            children: _tabs,
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

    // Mobile Layout with BottomNavigationBar
    //
    // extendBody 让列表内容从磨砂导航栏与迷你播放器下方滚过,玻璃效果才
    // 有内容可模糊;body 的 MediaQuery.padding.bottom 因此被抬升为底部
    // 导航栏总高度,迷你播放器与列表留白都据此避让。
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
              Icon(
                Icons.graphic_eq_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                _tabTitles[currentTab],
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 22),
              tooltip: '更多功能',
              onSelected: (value) {
                switch (value) {
                  case 'stats':
                    _pushPage(() => const ListeningStatsPage());
                    break;
                  case 'recent':
                    _pushPage(() => const RecentPlaysPage());
                    break;
                  case 'online':
                    _pushPage(() => const OnlineSearchPage());
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'stats',
                  child: Row(
                    children: [
                      Icon(Icons.insights_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('听歌统计'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'recent',
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('最近播放'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'online',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_download_outlined, size: 20),
                      SizedBox(width: 10),
                      Text('全网检索与下载'),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 22),
              tooltip: '设置',
              onPressed: () => _pushPage(() => const SettingsPage()),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Builder(
          builder: (bodyContext) {
            final bottomChromeHeight =
                MediaQuery.of(bodyContext).padding.bottom;
            return Stack(
              children: [
                IndexedStack(index: currentTab, children: _tabs),
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
          blurSigma: 24,
          tint: theme.colorScheme.surface.withValues(
            alpha: isLight ? 0.78 : 0.66,
          ),
          child: NavigationBar(
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
}
