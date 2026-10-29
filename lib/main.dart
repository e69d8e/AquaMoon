import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/audio/audio_player_handler.dart';
import 'providers/audio_provider.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive Storage
  final storageService = StorageService();
  await storageService.init();

  // 历史版本遗留在系统临时目录的封面缓存迁往应用支持目录（与
  // AudioService 初始化并行，必须在任何 Provider 读盒之前完成）。
  final coverCacheMigration = storageService.migrateTempCoverCaches();

  // Initialize AudioService Handler
  final audioHandler = await AudioService.init(
    builder: () => SoundCraftAudioHandler(storageService),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.aquamoon.app.channel.playback',
      androidNotificationChannelName: '播放控制',
      androidNotificationChannelDescription: '音乐后台播放控制、锁屏与通知栏操作',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_stat_music',
      androidShowNotificationBadge: false,
      androidNotificationClickStartsActivity: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );

  final migratedCovers = await coverCacheMigration;
  if (migratedCovers > 0) {
    debugPrint('[AquaMoon] migrated $migratedCovers cover cache records');
  }

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const SoundCraftApp(),
    ),
  );
}
