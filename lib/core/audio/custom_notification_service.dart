import 'dart:io';
import 'package:flutter/services.dart';

class CustomNotificationService {
  static const MethodChannel _channel = MethodChannel('com.aquamoon.app/custom_notification');

  static bool _initialized = false;
  static VoidCallback? onPlayPause;
  static VoidCallback? onPrev;
  static VoidCallback? onNext;
  static VoidCallback? onClose;

  static void init({
    VoidCallback? playPauseHandler,
    VoidCallback? prevHandler,
    VoidCallback? nextHandler,
    VoidCallback? closeHandler,
  }) {
    onPlayPause = playPauseHandler;
    onPrev = prevHandler;
    onNext = nextHandler;
    onClose = closeHandler;

    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlayPause':
          onPlayPause?.call();
          break;
        case 'onPrev':
          onPrev?.call();
          break;
        case 'onNext':
          onNext?.call();
          break;
        case 'onClose':
          onClose?.call();
          break;
      }
    });
  }

  static Future<void> update({
    required String title,
    required String artist,
    String? albumArtUri,
    required bool isPlaying,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'artist': artist,
        'albumArtUri': albumArtUri,
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
    } catch (_) {}
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {}
  }
}
