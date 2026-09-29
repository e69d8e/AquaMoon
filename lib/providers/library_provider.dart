import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/audio/audio_player_handler.dart';
import '../core/utils/metadata_extractor.dart';
import '../models/song.dart';
import '../services/online_metadata_service.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';

enum SongSortType { dateAdded, title, artist, duration, playCount }

/// Thrown when storage permission is denied so the UI can guide the user to
/// system settings instead of showing a misleading "no files found" toast.
class StoragePermissionDeniedException implements Exception {
  const StoragePermissionDeniedException();
}

/// Result of [LibraryNotifier.batchAutoMatchOnlineMetadata].
class BatchMatchResult {
  final int total;
  final int enriched;
  final int failed;

  const BatchMatchResult({
    required this.total,
    required this.enriched,
    required this.failed,
  });

  bool get allFailed => total > 0 && enriched == 0 && failed == total;
}

final searchQueryProvider = StateProvider<String>((ref) => '');
final sortTypeProvider = StateProvider<SongSortType>(
  (ref) => SongSortType.dateAdded,
);
final sortAscendingProvider = StateProvider<bool>((ref) => false);

class LibraryState {
  final List<Song> songs;
  final bool isScanning;
  final String? scanProgressText;
  final double? scanProgressPercent;

  const LibraryState({
    this.songs = const [],
    this.isScanning = false,
    this.scanProgressText,
    this.scanProgressPercent,
  });

  LibraryState copyWith({
    List<Song>? songs,
    bool? isScanning,
    String? scanProgressText,
    double? scanProgressPercent,
  }) {
    return LibraryState(
      songs: songs ?? this.songs,
      isScanning: isScanning ?? this.isScanning,
      scanProgressText: scanProgressText,
      scanProgressPercent: scanProgressPercent,
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final StorageService _storageService;
  final SoundCraftAudioHandler? _audioHandler;
  static const _uuid = Uuid();
  static const _supportedExtensions = [
    '.mp3',
    '.flac',
    '.m4a',
    '.wav',
    '.aac',
    '.ogg',
    '.opus',
    '.wma',
    '.ape',
    '.alac',
  ];

  LibraryNotifier(this._storageService, [this._audioHandler])
    : super(const LibraryState()) {
    _loadSongs();
  }

  void _loadSongs() {
    final songs = _storageService.getAllSongs();
    final deduplicated = _deduplicateSongs(songs);
    if (deduplicated.length < songs.length) {
      _storageService.overwriteAllSongs(deduplicated);
    }
    state = state.copyWith(songs: deduplicated);
    _fixMissingDurations(deduplicated);
  }

  List<Song> _deduplicateSongs(List<Song> songs) {
    final unique = <Song>[];
    final seenPaths = <String>{};
    final metaKeyMap = <String, Song>{};

    for (final song in songs) {
      final path = song.filePath;
      if (seenPaths.contains(path)) {
        continue;
      }

      final titleNorm = song.title.trim().toLowerCase();
      final artistNorm = song.artist.trim().toLowerCase();
      final metaKey = '$titleNorm|$artistNorm';

      if (titleNorm.isNotEmpty &&
          titleNorm != '未知曲目' &&
          titleNorm != '本地歌曲' &&
          artistNorm != '未知歌手') {
        final existing = metaKeyMap[metaKey];
        if (existing != null && existing.id != song.id) {
          if (existing.durationMs == 0 ||
              song.durationMs == 0 ||
              (existing.durationMs - song.durationMs).abs() < 3000) {
            continue;
          }
        }
      }

      seenPaths.add(path);
      if (artistNorm != '未知歌手') {
        metaKeyMap[metaKey] = song;
      }
      unique.add(song);
    }
    return unique;
  }

  void _fixMissingDurations(List<Song> songs) {
    final missing = songs
        .where((s) => s.durationMs <= 0 && s.filePath.isNotEmpty)
        .toList();
    if (missing.isEmpty) return;

    Future.microtask(() async {
      bool changed = false;
      for (final s in missing) {
        if (await File(s.filePath).exists()) {
          final meta = await MetadataExtractor.extractFromFile(s.filePath);
          if (meta.durationMs > 0) {
            final fix = s.copyWith(durationMs: meta.durationMs);
            await _storageService.saveSong(fix);
            _audioHandler?.syncSong(fix);
            changed = true;
          }
        }
      }
      if (changed) {
        final refreshed = _storageService.getAllSongs();
        state = state.copyWith(songs: refreshed);
      }
    });
  }

  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // 1. Try audio permission (Android 13+)
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;

      // 2. Try storage permission (Android 12 and below)
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // 3. Try manage external storage for all-files access
      final manageStatus = await Permission.manageExternalStorage.request();
      return manageStatus.isGranted;
    }
    return true;
  }

  Future<int> importFiles() async {
    final List<PlatformFile> pickedFiles;
    try {
      pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'flac',
          'm4a',
          'wav',
          'aac',
          'ogg',
          'opus',
          'wma',
          'ape',
          'alac',
        ],
      );
    } catch (_) {
      // Platform picker crashed — treat as cancellation instead of crashing.
      return 0;
    }

    if (pickedFiles.isEmpty) {
      return 0;
    }

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '正在解析选中音频元数据与封面...',
      scanProgressPercent: 0.0,
    );

    final validPaths = pickedFiles
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    final count = await _processAudioFilePaths(validPaths);

    state = state.copyWith(
      isScanning: false,
      scanProgressText: null,
      scanProgressPercent: null,
    );
    return count;
  }

  /// Recursively collects supported audio file paths under [roots], resolving
  /// symlinks and de-duplicating via a Set.
  Future<List<String>> _collectAudioFiles(Iterable<String> roots) async {
    final found = <String>{};
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (_supportedExtensions.contains(ext)) {
              String canonical = entity.path;
              try {
                canonical = entity.resolveSymbolicLinksSync();
              } catch (_) {}
              found.add(canonical);
            }
          }
        }
      } catch (_) {}
    }
    return found.toList();
  }

  Future<int> importFolder() async {
    final hasPermission = await requestStoragePermission();
    if (!hasPermission) throw const StoragePermissionDeniedException();

    String? directoryPath;
    try {
      directoryPath = await FilePicker.getDirectoryPath();
    } catch (_) {}

    // If user cancelled or didn't select a directory, exit cleanly
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return 0;
    }

    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      return 0;
    }

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '正在扫描目录中的音频文件...',
      scanProgressPercent: null,
    );

    final audioFilePaths = await _collectAudioFiles([directoryPath]);

    if (audioFilePaths.isEmpty) {
      state = state.copyWith(isScanning: false, scanProgressText: null);
      return 0;
    }

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '发现 ${audioFilePaths.length} 首歌曲，正在解析标签与内嵌封面...',
      scanProgressPercent: 0.0,
    );

    final count = await _processAudioFilePaths(audioFilePaths);
    state = state.copyWith(
      isScanning: false,
      scanProgressText: null,
      scanProgressPercent: null,
    );
    return count;
  }

  Future<int> scanSystemMusicDirectory() async {
    final hasPermission = await requestStoragePermission();
    if (!hasPermission) throw const StoragePermissionDeniedException();

    const commonDirs = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/netease/cloudmusic/Music',
      '/storage/emulated/0/KuGou/Music',
      '/storage/emulated/0/QQMusic/song',
    ];

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '正在快速扫描系统媒体目录...',
      scanProgressPercent: null,
    );

    final audioFilePaths = await _collectAudioFiles(commonDirs);

    if (audioFilePaths.isEmpty) {
      state = state.copyWith(isScanning: false, scanProgressText: null);
      return 0;
    }

    final count = await _processAudioFilePaths(audioFilePaths);
    state = state.copyWith(
      isScanning: false,
      scanProgressText: null,
      scanProgressPercent: null,
    );
    return count;
  }

  Future<int> _processAudioFilePaths(List<String> paths) async {
    final newSongs = <Song>[];
    final currentSongs = state.songs;

    final existingPaths = {for (final s in currentSongs) s.filePath};
    final existingMetaMap = <String, Song>{
      for (final s in currentSongs)
        if (s.title.trim().isNotEmpty &&
            s.artist.trim().isNotEmpty &&
            s.artist.trim() != '未知歌手')
          '${s.title.trim().toLowerCase()}|${s.artist.trim().toLowerCase()}': s,
    };

    const chunkSize = 4;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final end = (i + chunkSize < paths.length) ? i + chunkSize : paths.length;
      final chunk = paths.sublist(i, end);
      final percent = end / paths.length;

      state = state.copyWith(
        scanProgressText:
            '正在解析 ($end/${paths.length}): ${p.basename(chunk.last)}',
        scanProgressPercent: percent,
      );

      final chunkResults = await Future.wait(
        chunk.map((filePath) async {
          if (existingPaths.contains(filePath)) return null;
          final meta = await MetadataExtractor.extractFromFile(filePath);
          return (filePath, meta);
        }),
      );

      for (final item in chunkResults) {
        if (item == null) continue;
        final filePath = item.$1;
        final metadata = item.$2;

        final titleNorm = metadata.title.trim().toLowerCase();
        final artistNorm = metadata.artist.trim().toLowerCase();
        final metaKey = '$titleNorm|$artistNorm';

        // Check metadata deduplication (same title + artist + close duration)
        if (titleNorm.isNotEmpty &&
            titleNorm != '未知曲目' &&
            titleNorm != '本地歌曲' &&
            artistNorm != '未知歌手') {
          final existing = existingMetaMap[metaKey];
          if (existing != null) {
            if (existing.durationMs == 0 ||
                metadata.durationMs == 0 ||
                (existing.durationMs - metadata.durationMs).abs() < 3000) {
              continue;
            }
          }
        }

        final song = Song(
          id: _uuid.v4(),
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          durationMs: metadata.durationMs,
          filePath: filePath,
          albumArtUri: metadata.albumArtUri,
          albumArtBytes: metadata.albumArtBytes,
          dateAdded: DateTime.now(),
          source: SongSource.local,
          year: metadata.year,
        );

        existingPaths.add(filePath);
        if (artistNorm != '未知歌手') {
          existingMetaMap[metaKey] = song;
        }
        newSongs.add(song);
      }
    }

    if (newSongs.isNotEmpty) {
      await _storageService.saveSongs(newSongs);
      _loadSongs();
    }

    return newSongs.length;
  }

  Future<BatchMatchResult> batchAutoMatchOnlineMetadata(
    OnlineMetadataService onlineService,
  ) async {
    final targets = state.songs
        .where((s) => s.albumArtUri == null || s.lrcContent == null)
        .toList();
    if (targets.isEmpty) {
      return const BatchMatchResult(total: 0, enriched: 0, failed: 0);
    }

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '正在跨库智能检索 ${targets.length} 首歌曲的封面与歌词...',
      scanProgressPercent: 0.0,
    );

    int enrichedCount = 0;
    int failedCount = 0;
    for (int i = 0; i < targets.length; i++) {
      final song = targets[i];
      final percent = (i + 1) / targets.length;

      state = state.copyWith(
        scanProgressText: '正在匹配 (${i + 1}/${targets.length}): ${song.title}',
        scanProgressPercent: percent,
      );

      try {
        final result = await onlineService.fetchMetadata(
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: song.duration,
        );

        if (result != null) {
          String? newArtUri = song.albumArtUri;
          if (newArtUri == null && result.coverUrl != null) {
            newArtUri = await onlineService.cacheOnlineImage(result.coverUrl!);
          }
          final newLrc =
              song.lrcContent ?? result.syncedLyrics ?? result.plainLyrics;

          if (newArtUri != song.albumArtUri || newLrc != song.lrcContent) {
            final updated = song.copyWith(
              albumArtUri: newArtUri,
              lrcContent: newLrc,
            );
            await _storageService.saveSong(updated);
            enrichedCount++;
          }
        }
      } catch (_) {
        failedCount++;
      }
    }

    _loadSongs();
    state = state.copyWith(
      isScanning: false,
      scanProgressText: null,
      scanProgressPercent: null,
    );
    return BatchMatchResult(
      total: targets.length,
      enriched: enrichedCount,
      failed: failedCount,
    );
  }

  Future<void> deleteSong(Song song) async {
    await _storageService.deleteSong(song.id);
    state = state.copyWith(
      songs: state.songs.where((s) => s.id != song.id).toList(),
    );
  }

  Future<void> toggleFavorite(Song song) async {
    final updated = await _storageService.toggleFavorite(song.id);
    if (updated != null) {
      state = state.copyWith(
        songs: state.songs
            .map((s) => s.id == updated.id ? updated : s)
            .toList(),
      );
      _audioHandler?.syncSong(updated);
    }
  }

  Future<void> updateSong(Song song) async {
    await _storageService.saveSong(song);
    state = state.copyWith(
      songs: state.songs.map((s) => s.id == song.id ? song : s).toList(),
    );
    _audioHandler?.syncSong(song);
  }
}

final libraryNotifierProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
      final storage = ref.watch(storageServiceProvider);
      SoundCraftAudioHandler? handler;
      try {
        handler = ref.watch(audioHandlerProvider);
      } catch (_) {}
      return LibraryNotifier(storage, handler);
    });

final filteredSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(libraryNotifierProvider.select((s) => s.songs));
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sortType = ref.watch(sortTypeProvider);
  final ascending = ref.watch(sortAscendingProvider);

  // Decorate-sort-undecorate: lowercased search/sort keys are computed once
  // per song instead of on every comparator invocation (O(n log n) calls).
  var decorated = [
    for (final s in songs)
      (s, s.title.toLowerCase(), s.artist.toLowerCase(), s.album.toLowerCase()),
  ];

  if (query.isNotEmpty) {
    decorated = decorated
        .where(
          (d) =>
              d.$2.contains(query) ||
              d.$3.contains(query) ||
              d.$4.contains(query),
        )
        .toList();
  }

  decorated.sort((a, b) {
    int cmp = 0;
    switch (sortType) {
      case SongSortType.title:
        cmp = a.$2.compareTo(b.$2);
        break;
      case SongSortType.artist:
        cmp = a.$3.compareTo(b.$3);
        break;
      case SongSortType.duration:
        cmp = a.$1.durationMs.compareTo(b.$1.durationMs);
        break;
      case SongSortType.playCount:
        cmp = a.$1.playCount.compareTo(b.$1.playCount);
        break;
      case SongSortType.dateAdded:
        cmp = a.$1.dateAdded.compareTo(b.$1.dateAdded);
        break;
    }
    return ascending ? cmp : -cmp;
  });

  return [for (final d in decorated) d.$1];
});
