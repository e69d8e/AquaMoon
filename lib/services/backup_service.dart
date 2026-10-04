import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/formatters.dart';
import 'file_export_service.dart';
import 'storage_service.dart';

class BackupRestoreSummary {
  final int songs;
  final int playlists;
  final int historyEntries;

  const BackupRestoreSummary({
    required this.songs,
    required this.playlists,
    required this.historyEntries,
  });
}

/// 全量数据备份/恢复：把 5 个 Hive box 序列化为一个 JSON 文件，
/// 恢复时整体覆写。恢复后需重启应用让各 Provider 重新加载。
class BackupService {
  final StorageService _storageService;

  BackupService(this._storageService);

  Future<ExportResult> exportBackup() async {
    try {
      final data = _storageService.exportBackup();
      final json = const JsonEncoder.withIndent('  ').convert(data);

      final exportDir = await FileExportService.getExportDirectory();
      final stamp = Formatters.formatDateKey(DateTime.now()).replaceAll('-', '');
      final fileName = 'aquamoon_backup_$stamp.json';
      final targetFile = File(p.join(exportDir.path, fileName));
      await targetFile.writeAsString(json, encoding: utf8, flush: true);

      final size = await targetFile.length();
      return ExportResult(
        success: true,
        filePath: targetFile.path,
        fileSizeBytes: size,
        message: '备份已保存: AquaMoon/$fileName',
      );
    } catch (_) {
      return const ExportResult(success: false, message: '备份失败，请检查存储空间与权限');
    }
  }

  /// 从备份文件恢复。失败（含非本应用备份）抛出 [FormatException]。
  Future<BackupRestoreSummary> restoreFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const FormatException('备份文件不存在');
    }
    final dynamic decoded;
    try {
      decoded = json.decode(await file.readAsString(encoding: utf8));
    } catch (_) {
      throw const FormatException('备份文件解析失败');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('不是水月音备份文件');
    }

    await _storageService.restoreBackup(decoded);

    final songsSection = decoded['songs'];
    final playlistsSection = decoded['playlists'];
    final historySection = decoded['history'];
    return BackupRestoreSummary(
      songs: songsSection is Map ? songsSection.length : 0,
      playlists: playlistsSection is Map ? playlistsSection.length : 0,
      historyEntries: historySection is Map
          ? (historySection['recent_song_ids'] is List
                ? (historySection['recent_song_ids'] as List).length
                : 0)
          : 0,
    );
  }
}
