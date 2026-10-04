import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

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

  /// 导出歌单为 m3u8 播放列表文件（UTF-8，绝对路径条目）。
  static Future<ExportResult> exportPlaylistM3u({
    required String playlistName,
    required List<Song> songs,
  }) async {
    try {
      if (songs.isEmpty) {
        return const ExportResult(success: false, message: '歌单内没有歌曲可导出');
      }

      final exportDir = await getExportDirectory();
      final fileName = '${sanitizeFileName(playlistName)}.m3u8';
      final targetFile = File(p.join(exportDir.path, fileName));

      final buffer = StringBuffer('#EXTM3U\n#PLAYLIST:$playlistName\n');
      for (final song in songs) {
        final seconds = song.durationMs > 0
            ? (song.durationMs / 1000).round()
            : -1;
        buffer.writeln('#EXTINF:$seconds,${song.artist} - ${song.title}');
        buffer.writeln(song.filePath);
      }

      await targetFile.writeAsString(buffer.toString(), encoding: utf8, flush: true);
      final size = await targetFile.length();

      return ExportResult(
        success: true,
        filePath: targetFile.path,
        fileSizeBytes: size,
        message: '歌单已保存: AquaMoon/$fileName',
      );
    } catch (_) {
      return const ExportResult(success: false, message: '导出歌单失败，请检查存储空间与权限');
    }
  }
}

/// 解析 m3u 内容并与本地曲库匹配的结果。
class M3uImportResult {
  /// 与曲库匹配上的歌曲 id（按文件内顺序）。
  final List<String> matchedSongIds;

  /// 无法匹配到曲库歌曲的条目数。
  final int unmatchedEntries;

  const M3uImportResult({
    required this.matchedSongIds,
    required this.unmatchedEntries,
  });
}

class M3uPlaylistParser {
  /// 解析 m3u/m3u8 内容并按 路径精确匹配 → 文件名匹配 → EXTINF 标题/歌手匹配
  /// 的优先级与曲库比对。纯函数，便于单元测试。
  static M3uImportResult parse(String content, List<Song> library) {
    final byPath = {for (final s in library) s.filePath: s};
    final byBasename = <String, Song>{};
    for (final s in library) {
      final base = p.basename(s.filePath).toLowerCase();
      byBasename.putIfAbsent(base, () => s);
    }

    final matched = <String>[];
    final seen = <String>{};
    var unmatched = 0;
    var pendingExtInfTitle = '';
    var pendingExtInfArtist = '';

    void matchEntry(String entry) {
      final path = entry.trim();
      if (path.isEmpty) return;
      final song =
          byPath[path] ??
          byBasename[p.basename(path).toLowerCase()] ??
          _matchByMeta(pendingExtInfTitle, pendingExtInfArtist, library);
      if (song != null && seen.add(song.id)) {
        matched.add(song.id);
      } else if (song == null) {
        unmatched++;
      }
      pendingExtInfTitle = '';
      pendingExtInfArtist = '';
    }

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        // #EXTINF:<seconds>,<artist> - <title>
        final match = RegExp(r'^#EXTINF:\s*-?\d+\s*,\s*(.*)$').firstMatch(line);
        if (match != null) {
          final meta = match.group(1)?.trim() ?? '';
          final sepIdx = meta.lastIndexOf(' - ');
          if (sepIdx > 0) {
            pendingExtInfArtist = meta.substring(0, sepIdx).trim();
            pendingExtInfTitle = meta.substring(sepIdx + 3).trim();
          } else {
            pendingExtInfTitle = meta;
            pendingExtInfArtist = '';
          }
        }
        continue;
      }
      matchEntry(line);
    }

    return M3uImportResult(matchedSongIds: matched, unmatchedEntries: unmatched);
  }

  static Song? _matchByMeta(
    String title,
    String artist,
    List<Song> library,
  ) {
    final titleNorm = _normalize(title);
    if (titleNorm.isEmpty || titleNorm == '未知曲目') return null;
    final artistNorm = _normalize(artist);
    Song? titleOnly;
    for (final song in library) {
      if (_normalize(song.title) != titleNorm) continue;
      if (artistNorm.isNotEmpty && _normalize(song.artist) == artistNorm) {
        return song;
      }
      titleOnly ??= song;
    }
    return titleOnly;
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
