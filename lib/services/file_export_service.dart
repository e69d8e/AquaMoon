import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExportResult {
  final bool success;
  final String? filePath;
  final String message;
  final int? fileSizeBytes;

  const ExportResult({
    required this.success,
    this.filePath,
    required this.message,
    this.fileSizeBytes,
  });
}

class FileExportService {
  static final http.Client _client = http.Client();

  /// Resolve a safe and accessible directory for saving user-downloaded assets
  static Future<Directory> getExportDirectory() async {
    Directory? baseDir;

    try {
      if (Platform.isAndroid) {
        // 1. Try public Download folder on Android
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          baseDir = publicDownload;
        } else {
          baseDir =
              await getDownloadsDirectory() ??
              await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux) {
        baseDir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      baseDir = Directory.systemTemp;
    }

    baseDir ??= Directory.systemTemp;

    // Create a subfolder dedicated to AquaMoon downloads
    final aquaMoonDir = Directory(p.join(baseDir.path, 'AquaMoon'));
    if (!await aquaMoonDir.exists()) {
      await aquaMoonDir.create(recursive: true);
    }

    return aquaMoonDir;
  }

  /// Clean filename to remove invalid characters across Windows, Android, macOS, and Linux
  static String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Download and save a cover image file to local storage
  static Future<ExportResult> saveCoverImage({
    required String coverUrlOrPath,
    required String title,
    required String artist,
  }) async {
    try {
      if (coverUrlOrPath.isEmpty) {
        return const ExportResult(success: false, message: '封面地址为空，无法保存');
      }

      final exportDir = await getExportDirectory();
      final cleanTitle = sanitizeFileName(title.isNotEmpty ? title : '未知曲目');
      final cleanArtist = sanitizeFileName(
        artist.isNotEmpty && artist != '未知歌手' ? artist : '',
      );
      final filePrefix = cleanArtist.isNotEmpty
          ? '$cleanTitle - $cleanArtist'
          : cleanTitle;

      final targetFile = File(
        p.join(exportDir.path, '${filePrefix}_cover.jpg'),
      );

      List<int> imageBytes = [];

      if (coverUrlOrPath.startsWith('http://') ||
          coverUrlOrPath.startsWith('https://')) {
        // Online network image
        final response = await _client
            .get(
              Uri.parse(coverUrlOrPath),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                'Referer': 'https://y.qq.com/',
              },
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          return ExportResult(
            success: false,
            message: '封面下载失败 (HTTP ${response.statusCode})',
          );
        }
        imageBytes = response.bodyBytes;
      } else {
        // Local file or URI
        String localPath = coverUrlOrPath;
        if (coverUrlOrPath.startsWith('file://')) {
          localPath = Uri.parse(coverUrlOrPath).toFilePath();
        }
        final srcFile = File(localPath);
        if (!await srcFile.exists()) {
          return const ExportResult(success: false, message: '本地源封面文件不存在');
        }
        imageBytes = await srcFile.readAsBytes();
      }

      await targetFile.writeAsBytes(imageBytes, flush: true);

      return ExportResult(
        success: true,
        filePath: targetFile.path,
        fileSizeBytes: imageBytes.length,
        message: '封面已保存: AquaMoon/${p.basename(targetFile.path)}',
      );
    } catch (_) {
      return const ExportResult(success: false, message: '保存封面失败，请检查存储空间与权限');
    }
  }

  /// Save lyric content as a `.lrc` file encoded in UTF-8
  static Future<ExportResult> saveLyricFile({
    required String lyricContent,
    required String title,
    required String artist,
  }) async {
    try {
      if (lyricContent.trim().isEmpty) {
        return const ExportResult(success: false, message: '歌词内容为空，无法保存');
      }

      final exportDir = await getExportDirectory();
      final cleanTitle = sanitizeFileName(title.isNotEmpty ? title : '未知曲目');
      final cleanArtist = sanitizeFileName(
        artist.isNotEmpty && artist != '未知歌手' ? artist : '',
      );
      final filePrefix = cleanArtist.isNotEmpty
          ? '$cleanTitle - $cleanArtist'
          : cleanTitle;

      final targetFile = File(p.join(exportDir.path, '$filePrefix.lrc'));

      await targetFile.writeAsString(lyricContent, encoding: utf8, flush: true);
      final size = await targetFile.length();

      return ExportResult(
        success: true,
        filePath: targetFile.path,
        fileSizeBytes: size,
        message: '歌词已保存: AquaMoon/${p.basename(targetFile.path)}',
      );
    } catch (_) {
      return const ExportResult(success: false, message: '保存歌词失败，请检查存储空间与权限');
    }
  }

  /// Copy lyric content to clipboard
  static Future<bool> copyToClipboard(String content) async {
    try {
      if (content.isEmpty) return false;
      await Clipboard.setData(ClipboardData(text: content));
      return true;
    } catch (_) {
      return false;
    }
  }
}
