import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/audio/audio_player_handler.dart';
import 'providers/audio_provider.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Hive Storage
  final storageService = StorageService();
  await storageService.init();

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
