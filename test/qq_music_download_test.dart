import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:aquamoon/models/qq_music_discovery.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/qq_music_download_provider.dart';
import 'package:aquamoon/services/qq_music_download_service.dart';
import 'package:aquamoon/services/storage_service.dart';

/// 下载功能的纯逻辑部分：命名规则、音质识别、状态流转与设置持久化。
/// 真正的网络下载在 service 里，成功路径依赖 CDN，这里只锁定可离线验证的契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Song onlineSong({
    String title = '青花瓷',
    String artist = '周杰伦',
    String album = '我很忙',
    String? mid = '003OUlho2HcRHC',
  }) {
    return Song(
      id: 'qq_${mid ?? 'x'}',
      title: title,
      artist: artist,
      album: album,
      durationMs: 239000,
      filePath: 'qqmusic://${mid ?? 'x'}',
      dateAdded: DateTime(2026, 1, 1),
      source: SongSource.online,
      qqSongMid: mid,
    );
  }

  group('download file naming', () {
    test('uses 歌手 - 歌名 so metadata fallback can rebuild tags', () {
      expect(QQMusicDownloadService.fileNameFor(onlineSong()), '周杰伦 - 青花瓷');
      expect(
        QQMusicDownloadService.fileNameFor(onlineSong(artist: '未知歌手')),
        '青花瓷',
      );
      expect(
        QQMusicDownloadService.fileNameFor(onlineSong(artist: '')),
        '青花瓷',
      );
      expect(
        QQMusicDownloadService.fileNameFor(onlineSong(title: '', artist: '群星')),
        '群星',
      );
      expect(
        QQMusicDownloadService.fileNameFor(onlineSong(title: '', artist: '')),
        'QQ音乐曲目',
      );
    });

    test('sanitizes characters that Android filesystems reject', () {
      expect(
        QQMusicDownloadService.sanitizeFileName('A/B\\C:D*E?F"G<H>I|J'),
        'A_B_C_D_E_F_G_H_I_J',
      );
      expect(QQMusicDownloadService.sanitizeFileName('多  个   空格'), '多 个 空格');
      expect(QQMusicDownloadService.sanitizeFileName('尾部点...'), '尾部点');
      expect(QQMusicDownloadService.sanitizeFileName('   '), 'QQ音乐曲目');
      expect(QQMusicDownloadService.sanitizeFileName('春夏秋冬'), '春夏秋冬');
    });

    test('truncates overlong names to a safe length', () {
      final long = '曲' * 200;
      final sanitized = QQMusicDownloadService.sanitizeFileName(long);
      expect(sanitized.length, lessThanOrEqualTo(120));
      expect(sanitized.runes.length, lessThanOrEqualTo(120));
    });
  });

  group('stream url introspection', () {
    test('recognises the actual quality served by the CDN', () {
      expect(
        QQMusicDownloadService.qualityFromUrl(
          'https://ws.stream.qqmusic.qq.com/F000003OUlho2HcRHC.flac?vkey=abc',
        ),
        QQMusicStreamQuality.lossless,
      );
      expect(
        QQMusicDownloadService.qualityFromUrl(
          'https://ws.stream.qqmusic.qq.com/M800003OUlho2HcRHC.mp3?vkey=abc',
        ),
        QQMusicStreamQuality.high,
      );
      expect(
        QQMusicDownloadService.qualityFromUrl(
          'https://ws.stream.qqmusic.qq.com/O801003OUlho2HcRHC.ogg?vkey=abc',
        ),
        QQMusicStreamQuality.ultra,
      );
      expect(
        QQMusicDownloadService.qualityFromUrl(
          'https://ws.stream.qqmusic.qq.com/C400003OUlho2HcRHC.m4a?vkey=abc',
        ),
        isNull,
      );
    });

    test('extracts only audio extensions', () {
      expect(
        QQMusicDownloadService.extensionFromUrl(
          'https://ws.stream.qqmusic.qq.com/F000003OUlho2HcRHC.flac?vkey=abc',
        ),
        'flac',
      );
      expect(
        QQMusicDownloadService.extensionFromUrl(
          'https://ws.stream.qqmusic.qq.com/x.m4a',
        ),
        'm4a',
      );
      expect(
        QQMusicDownloadService.extensionFromUrl(
          'https://ws.stream.qqmusic.qq.com/x.json?vkey=abc',
        ),
        isNull,
      );
      expect(QQMusicDownloadService.extensionFromUrl('not a url'), isNull);
    });
  });

  group('download task state', () {
    test('reports a downgrade only when the CDN served another quality', () {
      final task = QQMusicDownloadTask(
        key: '003OUlho2HcRHC',
        song: onlineSong(),
        quality: QQMusicStreamQuality.lossless,
        status: QQMusicDownloadStatus.completed,
        actualQuality: QQMusicStreamQuality.lossless,
      );
      expect(task.downgradeNote, isNull);
      expect(
        task.copyWith(actualQuality: QQMusicStreamQuality.high).downgradeNote,
        '音源实际为 高品质 · 320K MP3',
      );
    });

    test('clearProgress mirrors an unknown content length', () {
      final task = QQMusicDownloadTask(
        key: 'k',
        song: onlineSong(),
        quality: QQMusicStreamQuality.high,
        status: QQMusicDownloadStatus.downloading,
        progress: 0.4,
        receivedBytes: 400,
      );
      final unknown = task.copyWith(clearProgress: true, receivedBytes: 512);
      expect(unknown.progress, isNull);
      expect(unknown.receivedBytes, 512);
      expect(unknown.isActive, isTrue);
    });

    test('state indexes tasks by songmid and falls back to song id', () {
      final withMid = onlineSong();
      final withoutMid = onlineSong(mid: null);
      final state = QQMusicDownloadState(
        tasks: {
          QQMusicDownloadNotifier.keyFor(withMid): QQMusicDownloadTask(
            key: QQMusicDownloadNotifier.keyFor(withMid),
            song: withMid,
            quality: QQMusicStreamQuality.high,
            status: QQMusicDownloadStatus.downloading,
          ),
          QQMusicDownloadNotifier.keyFor(withoutMid): QQMusicDownloadTask(
            key: QQMusicDownloadNotifier.keyFor(withoutMid),
            song: withoutMid,
            quality: QQMusicStreamQuality.high,
            status: QQMusicDownloadStatus.queued,
          ),
        },
      );

      expect(QQMusicDownloadNotifier.keyFor(withMid), '003OUlho2HcRHC');
      expect(QQMusicDownloadNotifier.keyFor(withoutMid), withoutMid.id);
      expect(state.taskFor(withMid)?.status, QQMusicDownloadStatus.downloading);
      expect(state.activeCount, 2);
      expect(state.hasActive, isTrue);
    });
  });

  group('download settings persistence', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('qq_download_settings_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('quality, folder and auto-import default to sensible values', () {
      expect(storage.getQQMusicDownloadQuality(), QQMusicStreamQuality.high);
      expect(storage.getQQMusicDownloadDirectory(), '');
      expect(storage.getQQMusicDownloadAddToLibrary(), isTrue);
    });

    test('round-trips the chosen quality and folder', () async {
      await storage.saveQQMusicDownloadQuality(QQMusicStreamQuality.lossless);
      await storage.saveQQMusicDownloadDirectory('/storage/emulated/0/Music');

      expect(storage.getQQMusicDownloadQuality(), QQMusicStreamQuality.lossless);
      expect(
        storage.getQQMusicDownloadDirectory(),
        '/storage/emulated/0/Music',
      );

      await storage.saveQQMusicDownloadDirectory('');
      expect(storage.getQQMusicDownloadDirectory(), '');
    });

    test('auto-import switch persists both ways', () async {
      await storage.saveQQMusicDownloadAddToLibrary(false);
      expect(storage.getQQMusicDownloadAddToLibrary(), isFalse);
      await storage.saveQQMusicDownloadAddToLibrary(true);
      expect(storage.getQQMusicDownloadAddToLibrary(), isTrue);
    });

    test('settings model labels the default folder when unset', () {
      const unset = QQMusicDownloadSettings(
        quality: QQMusicStreamQuality.high,
        directory: '',
        addToLibrary: true,
      );
      expect(unset.directoryLabel, unset.defaultDirectoryPath);

      const custom = QQMusicDownloadSettings(
        quality: QQMusicStreamQuality.high,
        directory: '/storage/emulated/0/Music/水月音',
        addToLibrary: false,
      );
      expect(custom.directoryLabel, '/storage/emulated/0/Music/水月音');
      expect(custom.copyWith(addToLibrary: true).addToLibrary, isTrue);
      expect(custom.copyWith(addToLibrary: true).directoryLabel, custom.directoryLabel);
    });
  });
}
