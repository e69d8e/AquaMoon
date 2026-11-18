import 'dart:io';

import 'package:flutter/services.dart';

/// Android 媒体库登记桥。
///
/// 下载到公共目录（如 `Download/AquaMoon`）的音频是在应用进程里用 `dart:io`
/// 直接写盘的，MediaStore 不会自动感知；不同步一次的话，系统文件管理器、
/// 图库之外的其它音乐 App 都看不到刚下载的文件。这里调用原生
/// `MediaScannerConnection.scanFile` 把它登记进媒体库。
class MediaScanner {
  static const MethodChannel _channel = MethodChannel(
    'com.aquamoon.app/downloads',
  );

  /// 把 [filePath] 登记到系统媒体库。非 Android 平台或通道不可用时静默返回
  /// false —— 登记失败不影响文件本身已经落盘。
  static Future<bool> scanAudioFile(String filePath) async {
    if (!Platform.isAndroid) return false;
    if (filePath.trim().isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>('scanAudioFile', {
        'path': filePath,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}