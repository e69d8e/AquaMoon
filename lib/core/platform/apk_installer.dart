import 'dart:io';

import 'package:flutter/services.dart';

/// Android 应用内更新安装桥：把下载完成的 APK 交给系统安装器。
class ApkInstaller {
  static const MethodChannel _channel = MethodChannel(
    'com.aquamoon.app/updater',
  );

  /// 当前设备/系统是否允许本应用安装未知来源 APK（Android 8+ 需授权）。
  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 拉起系统安装器。返回 false 时通常已跳转「未知来源授权」页，用户授权后
  /// 需重新触发安装。
  static Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': filePath,
      });
      return result == 'installed';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
