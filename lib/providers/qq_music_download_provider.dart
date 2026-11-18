import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/qq_music_discovery.dart';
import '../models/song.dart';
import '../services/qq_music_download_service.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';
import 'library_provider.dart';
import 'qq_music_provider.dart';

enum QQMusicDownloadStatus { queued, downloading, completed, failed }

/// 一首歌的下载状态。下载队列按 `songmid`（缺省时用 `song.id`）去重。
class QQMusicDownloadTask {
  const QQMusicDownloadTask({
    required this.key,
    required this.song,
    required this.quality,
    required this.status,
    this.progress,
    this.receivedBytes = 0,
    this.totalBytes,
    this.filePath,
    this.directory,
    this.actualQuality,
    this.message = '',
  });

  final String key;
  final Song song;
  final QQMusicStreamQuality quality;
  final QQMusicDownloadStatus status;

  /// 0..1；总长度未知时为 null（界面显示「不确定进度」）。
  final double? progress;
  final int receivedBytes;
  final int? totalBytes;
  final String? filePath;
  final String? directory;
  final QQMusicStreamQuality? actualQuality;

  /// 失败原因或成功后的补充说明（如「未能加入曲库」）。
  final String message;

  bool get isActive =>
      status == QQMusicDownloadStatus.queued ||
      status == QQMusicDownloadStatus.downloading;
  bool get isCompleted => status == QQMusicDownloadStatus.completed;
  bool get isFailed => status == QQMusicDownloadStatus.failed;

  /// 服务端降级时给出提示文案（无损 → 320K MP3 等）。
  String? get downgradeNote {
    final actual = actualQuality;
    if (actual == null || actual == quality) return null;
    return '音源实际为 ${actual.label}';
  }

  QQMusicDownloadTask copyWith({
    QQMusicDownloadStatus? status,
    double? progress,
    bool clearProgress = false,
    int? receivedBytes,
    int? totalBytes,
    String? filePath,
    String? directory,
    QQMusicStreamQuality? actualQuality,
    String? message,
  }) {
    return QQMusicDownloadTask(
      key: key,
      song: song,
      quality: quality,
      status: status ?? this.status,
      progress: clearProgress ? null : (progress ?? this.progress),
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      filePath: filePath ?? this.filePath,
      directory: directory ?? this.directory,
      actualQuality: actualQuality ?? this.actualQuality,
      message: message ?? this.message,
    );
  }
}

class QQMusicDownloadState {
  const QQMusicDownloadState({this.tasks = const {}});

  final Map<String, QQMusicDownloadTask> tasks;

  QQMusicDownloadTask? taskFor(Song song) =>
      tasks[QQMusicDownloadNotifier.keyFor(song)];

  List<QQMusicDownloadTask> get activeTasks => tasks.values
      .where((task) => task.isActive)
      .toList(growable: false);

  bool get hasActive => tasks.values.any((task) => task.isActive);

  int get activeCount => activeTasks.length;

  QQMusicDownloadState copyWith({Map<String, QQMusicDownloadTask>? tasks}) {
    return QQMusicDownloadState(tasks: tasks ?? this.tasks);
  }
}

/// 下载偏好（音质 / 文件夹 / 是否入库），与设置页配合。
class QQMusicDownloadSettings {
  const QQMusicDownloadSettings({
    required this.quality,
    required this.directory,
    required this.addToLibrary,
  });

  final QQMusicStreamQuality quality;

  /// 空字符串表示使用默认下载目录。
  final String directory;
  final bool addToLibrary;

  String get defaultDirectoryPath => Platform.isAndroid
      ? QQMusicDownloadService.androidDefaultDirectory
      : '系统下载目录/AquaMoon';

  String get directoryLabel =>
      directory.isEmpty ? defaultDirectoryPath : directory;

  QQMusicDownloadSettings copyWith({
    QQMusicStreamQuality? quality,
    String? directory,
    bool? addToLibrary,
  }) {
    return QQMusicDownloadSettings(
      quality: quality ?? this.quality,
      directory: directory ?? this.directory,
      addToLibrary: addToLibrary ?? this.addToLibrary,
    );
  }
}

class QQMusicDownloadSettingsNotifier
    extends StateNotifier<QQMusicDownloadSettings> {
  QQMusicDownloadSettingsNotifier(this._storage)
    : super(
        QQMusicDownloadSettings(
          quality: _storage.getQQMusicDownloadQuality(),
          directory: _storage.getQQMusicDownloadDirectory(),
          addToLibrary: _storage.getQQMusicDownloadAddToLibrary(),
        ),
      );

  final StorageService _storage;

  Future<void> setQuality(QQMusicStreamQuality quality) async {
    if (state.quality == quality) return;
    state = state.copyWith(quality: quality);
    await _storage.saveQQMusicDownloadQuality(quality);
  }

  Future<void> setDirectory(String directory) async {
    final trimmed = directory.trim();
    state = state.copyWith(directory: trimmed);
    await _storage.saveQQMusicDownloadDirectory(trimmed);
  }

  Future<void> resetDirectory() => setDirectory('');

  Future<void> setAddToLibrary(bool enabled) async {
    if (state.addToLibrary == enabled) return;
    state = state.copyWith(addToLibrary: enabled);
    await _storage.saveQQMusicDownloadAddToLibrary(enabled);
  }
}

final qqMusicDownloadServiceProvider = Provider<QQMusicDownloadService>((ref) {
  final service = QQMusicDownloadService(
    musicService: ref.watch(qqMusicServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final qqMusicDownloadSettingsProvider =
    StateNotifierProvider<
      QQMusicDownloadSettingsNotifier,
      QQMusicDownloadSettings
    >((ref) {
      return QQMusicDownloadSettingsNotifier(ref.watch(storageServiceProvider));
    });

/// 下载队列。
///
/// 串行执行：QQ 音乐的直链带宽有限，并发下载反而更容易超时；串行还能让
/// 进度条稳定推进，用户点了几首也不会出现多个进度互相抢带宽。
class QQMusicDownloadNotifier extends StateNotifier<QQMusicDownloadState> {
  QQMusicDownloadNotifier(
    this._storage,
    this._service,
    this._library,
  ) : super(const QQMusicDownloadState());

  final StorageService _storage;
  final QQMusicDownloadService _service;
  final LibraryNotifier _library;

  final List<({Song song, QQMusicStreamQuality quality})> _queue = [];
  final Map<String, Completer<QQMusicDownloadTask>> _waiters = {};
  bool _draining = false;
  bool _permissionRequested = false;

  static String keyFor(Song song) {
    final mid = song.qqSongMid;
    return (mid != null && mid.isNotEmpty) ? mid : song.id;
  }

  /// 把 [song] 加入下载队列；返回的 Future 在该曲下载结束（成功或失败）时
  /// 完成，界面可以 await 它来弹提示。
  Future<QQMusicDownloadTask> enqueue(
    Song song, {
    QQMusicStreamQuality? quality,
  }) {
    final key = keyFor(song);
    final existing = state.tasks[key];
    if (existing != null && existing.isActive) {
      return _waiters[key]?.future ??
          Future<QQMusicDownloadTask>.value(existing);
    }

    final effectiveQuality = quality ?? _storage.getQQMusicDownloadQuality();
    final completer = Completer<QQMusicDownloadTask>();
    _waiters[key] = completer;
    _setTask(
      QQMusicDownloadTask(
        key: key,
        song: song,
        quality: effectiveQuality,
        status: QQMusicDownloadStatus.queued,
      ),
    );
    _queue.add((song: song, quality: effectiveQuality));
    unawaited(_drain());
    return completer.future;
  }

  /// 清掉已结束的任务记录（队列本身不受影响）。
  void clearFinished() {
    final remaining = <String, QQMusicDownloadTask>{
      for (final entry in state.tasks.entries)
        if (entry.value.isActive) entry.key: entry.value,
    };
    state = state.copyWith(tasks: remaining);
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && mounted) {
        final pending = _queue.removeAt(0);
        await _run(pending.song, pending.quality);
      }
    } finally {
      _draining = false;
    }
  }

  /// Android 11+ 直接写公共下载目录需要「所有文件访问权限」。只在实际写不
  /// 进去时才申请一次，用户拒绝后 service 会回退到应用专属目录。
  Future<void> _ensureStoragePermission() async {
    try {
      final custom = _storage.getQQMusicDownloadDirectory();
      final dir = custom.isNotEmpty
          ? custom
          : QQMusicDownloadService.androidDefaultDirectory;
      if (await QQMusicDownloadService.isDirectoryWritable(dir)) return;
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    } catch (_) {}
  }

  Future<void> _run(Song song, QQMusicStreamQuality quality) async {
    final key = keyFor(song);
    final queued = state.tasks[key];
    if (queued == null) return;

    _setTask(
      queued.copyWith(
        status: QQMusicDownloadStatus.downloading,
        progress: 0,
        receivedBytes: 0,
        message: '',
      ),
    );

    if (Platform.isAndroid && !_permissionRequested) {
      _permissionRequested = true;
      await _ensureStoragePermission();
    }

    try {
      final result = await _service.downloadSong(
        song: song,
        quality: quality,
        targetDirectory: _storage.getQQMusicDownloadDirectory(),
        config: _storage.getQQMusicConfig(),
        onProgress: (received, total) => _updateProgress(key, received, total),
      );

      var note = '';
      if (_storage.getQQMusicDownloadAddToLibrary()) {
        try {
          final added = await _library.addDownloadedFile(
            filePath: result.filePath,
            qqSongMid: song.qqSongMid,
            qqSongId: song.qqSongId,
            qqMediaMid: song.qqMediaMid,
            fallbackTitle: song.title,
            fallbackArtist: song.artist,
            fallbackAlbum: song.album,
          );
          if (added == null) note = '音频已保存，但未能加入曲库';
        } catch (_) {
          note = '音频已保存，但未能加入曲库';
        }
      }

      _finish(
        key,
        QQMusicDownloadTask(
          key: key,
          song: song,
          quality: quality,
          status: QQMusicDownloadStatus.completed,
          progress: 1,
          receivedBytes: result.bytes,
          totalBytes: result.bytes,
          filePath: result.filePath,
          directory: result.directory,
          actualQuality: result.actualQuality,
          message: note,
        ),
      );
    } on QQMusicDownloadException catch (e) {
      _fail(key, e.message);
    } catch (_) {
      _fail(key, '下载失败，请检查网络后重试');
    }
  }

  void _updateProgress(String key, int received, int? total) {
    final task = state.tasks[key];
    if (task == null || !mounted) return;
    final progress = (total != null && total > 0)
        ? (received / total).clamp(0.0, 1.0)
        : null;

    // 每个 chunk 都刷新会让整个发现页高频重建。1% 粒度对进度条已经足够，
    // 总长度未知（无 content-length）时按 256KB 节流。
    if (progress != null && task.progress != null) {
      if (progress < 1.0 && (progress - task.progress!).abs() < 0.01) return;
    } else if (progress == null && received - task.receivedBytes < 256 * 1024) {
      return;
    }

    _setTask(
      task.copyWith(
        progress: progress,
        receivedBytes: received,
        totalBytes: total,
        clearProgress: progress == null,
      ),
    );
  }

  void _fail(String key, String message) {
    final task = state.tasks[key];
    if (task == null) return;
    _finish(
      key,
      task.copyWith(status: QQMusicDownloadStatus.failed, message: message),
    );
  }

  void _finish(String key, QQMusicDownloadTask task) {
    _setTask(task);
    final completer = _waiters.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.complete(task);
    }
  }

  void _setTask(QQMusicDownloadTask task) {
    if (!mounted) return;
    state = state.copyWith(tasks: {...state.tasks, task.key: task});
  }

  @override
  void dispose() {
    for (final completer in _waiters.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const QQMusicDownloadException('下载已取消'),
        );
      }
    }
    _waiters.clear();
    _queue.clear();
    super.dispose();
  }
}

final qqMusicDownloadProvider =
    StateNotifierProvider<QQMusicDownloadNotifier, QQMusicDownloadState>((ref) {
      return QQMusicDownloadNotifier(
        ref.watch(storageServiceProvider),
        ref.watch(qqMusicDownloadServiceProvider),
        ref.watch(libraryNotifierProvider.notifier),
      );
    });