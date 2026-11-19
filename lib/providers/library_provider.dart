import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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
    unawaited(_loadSongs());
  }

  Future<void> _loadSongs() async {
    final songs = _storageService.getAllSongs();
    final (deduplicated, mergedChanged, droppedIds) = _deduplicateSongs(songs);
    // Publish the deduplicated library synchronously so the very first read
    // of this provider already sees the final list.
    state = state.copyWith(songs: deduplicated);
    _fixMissingDurations(deduplicated);
    // Persist dedup outcomes as targeted writes — merged copies are saved
    // and duplicates removed by id. The previous whole-box rewrite ran
    // unawaited next to concurrent saveSong calls and could resurrect stale
    // records (wiping freshly matched lyrics with them).
    if (mergedChanged.isNotEmpty) {
      await _storageService.saveSongs(mergedChanged);
    }
    if (droppedIds.isNotEmpty) {
      await _storageService.deleteSongs(droppedIds);
    }
  }

  /// Deduplicates [songs] by file path and title+artist metadata.
  ///
  /// Returns the deduplicated list, the kept records whose data was enriched
  /// by a dropped duplicate (they must be re-saved), and the ids of the
  /// dropped duplicates (they must be deleted from storage).
  (List<Song>, List<Song>, List<String>) _deduplicateSongs(List<Song> songs) {
    final unique = <Song>[];
    final mergedChanged = <Song>[];
    final indexById = <String, int>{};
    final keptIdByPath = <String, String>{};
    final keptIdByMetaKey = <String, String>{};

    for (final song in songs) {
      final path = song.filePath;
      final titleNorm = song.title.trim().toLowerCase();
      final artistNorm = song.artist.trim().toLowerCase();
      final metaKey = '$titleNorm|$artistNorm';

      String? keptId;
      final pathDupId = keptIdByPath[path];
      if (pathDupId != null) {
        keptId = pathDupId;
      } else if (titleNorm.isNotEmpty &&
          titleNorm != '未知曲目' &&
          titleNorm != '本地歌曲' &&
          artistNorm != '未知歌手') {
        final metaDupId = keptIdByMetaKey[metaKey];
        if (metaDupId != null) {
          final existing = unique[indexById[metaDupId]!];
          if (existing.durationMs == 0 ||
              song.durationMs == 0 ||
              (existing.durationMs - song.durationMs).abs() < 3000) {
            keptId = metaDupId;
          }
        }
      }

      if (keptId != null) {
        final keepIndex = indexById[keptId]!;
        final keptSongId = unique[keepIndex].id;
        final merged = _mergeDuplicateData(unique[keepIndex], song);
        unique[keepIndex] = merged;
        mergedChanged.add(merged);
        // The merge may have upgraded placeholder title/artist on the kept
        // record — re-index its metadata key so later songs match it.
        keptIdByMetaKey.removeWhere((key, id) => id == keptSongId);
        final mergedArtist = merged.artist.trim();
        if (mergedArtist.isNotEmpty && mergedArtist != '未知歌手') {
          final mergedMetaKey =
              '${merged.title.trim().toLowerCase()}|'
              '${mergedArtist.toLowerCase()}';
          keptIdByMetaKey.putIfAbsent(mergedMetaKey, () => keptSongId);
        }
        continue;
      }

      keptIdByPath[path] = song.id;
      if (artistNorm != '未知歌手') {
        keptIdByMetaKey[metaKey] = song.id;
      }
      indexById[song.id] = unique.length;
      unique.add(song);
    }

    final keptIds = {for (final s in unique) s.id};
    final droppedIds = [
      for (final s in songs) if (!keptIds.contains(s.id)) s.id,
    ];
    return (unique, mergedChanged, droppedIds);
  }

  static bool _isBlankTitle(String title) {
    final t = title.trim();
    return t.isEmpty || t == '未知曲目' || t == '本地歌曲';
  }

  static bool _isBlankArtist(String artist) {
    final a = artist.trim();
    return a.isEmpty || a == '未知歌手';
  }

  static bool _isBlankAlbum(String album) {
    final a = album.trim();
    return a.isEmpty || a == '未知专辑';
  }

  static bool _isSyncedLrc(String? lrc) =>
      lrc != null && lrc.contains(RegExp(r'\[\d{1,2}:\d{2}(\.\d+)?\]'));

  /// Fills [keep] with data that only exists on [drop] before the duplicate
  /// record is discarded. Without this, startup deduplication used to wipe
  /// matched lyrics / cached covers that lived only on the dropped copy —
  /// the "matched lyrics are gone after relaunch" bug.
  Song _mergeDuplicateData(Song keep, Song drop) {
    final keepLrcSynced = _isSyncedLrc(keep.lrcContent);
    final dropLrcSynced = _isSyncedLrc(drop.lrcContent);
    // Prefer synced lyrics over plain text when the two copies disagree.
    final String? lrcContent =
        keep.lrcContent == null
            ? drop.lrcContent
            : drop.lrcContent != null && !keepLrcSynced && dropLrcSynced
            ? drop.lrcContent
            : keep.lrcContent;

    return keep.copyWith(
      title: _isBlankTitle(keep.title) && !_isBlankTitle(drop.title)
          ? drop.title
          : keep.title,
      artist: _isBlankArtist(keep.artist) && !_isBlankArtist(drop.artist)
          ? drop.artist
          : keep.artist,
      album: _isBlankAlbum(keep.album) && !_isBlankAlbum(drop.album)
          ? drop.album
          : keep.album,
      durationMs: keep.durationMs > 0 ? keep.durationMs : drop.durationMs,
      lrcContent: lrcContent,
      albumArtUri: keep.albumArtUri ?? drop.albumArtUri,
      albumArtBytes: (keep.albumArtUri ?? drop.albumArtUri) != null
          ? null
          : (keep.albumArtBytes ?? drop.albumArtBytes),
      playCount:
          keep.playCount >= drop.playCount ? keep.playCount : drop.playCount,
      isFavorite: keep.isFavorite || drop.isFavorite,
      trackNumber: keep.trackNumber ?? drop.trackNumber,
      year: keep.year ?? drop.year,
      qqSongMid: keep.qqSongMid ?? drop.qqSongMid,
      qqSongId: keep.qqSongId ?? drop.qqSongId,
      qqMediaMid: keep.qqMediaMid ?? drop.qqMediaMid,
      isVip: keep.isVip || drop.isVip,
    );
  }

  void _fixMissingDurations(List<Song> songs) {
    final missing = songs
        .where((s) => s.durationMs <= 0 && s.filePath.isNotEmpty)
        .toList();
    if (missing.isEmpty) return;

    Future.microtask(() async {
      final coverCacheDirPath =
          await MetadataExtractor.resolveCoverCacheDirPath();
      final existingPaths = <String>[];
      final songByPath = <String, Song>{};
      for (final s in missing) {
        if (await File(s.filePath).exists()) {
          existingPaths.add(s.filePath);
          songByPath[s.filePath] = s;
        }
      }
      if (existingPaths.isEmpty) return;

      final metas = await Isolate.run(
        () => MetadataExtractor.extractChunkIsolated(
          existingPaths,
          coverCacheDirPath,
        ),
      );
      final fixes = <Song>[];
      for (var i = 0; i < existingPaths.length; i++) {
        final s = songByPath[existingPaths[i]]!;
        final meta = metas[i];
        if (meta.durationMs > 0) {
          // The snapshot may be stale — skip songs deleted while we were
          // extracting, otherwise saveSong would resurrect them.
          final fresh = _storageService.getSong(s.id);
          if (fresh == null) continue;
          final fix = fresh.copyWith(durationMs: meta.durationMs);
          fixes.add(fix);
        }
      }
      if (fixes.isNotEmpty) {
        await _storageService.saveSongs(fixes);
        for (final fix in fixes) {
          _audioHandler?.syncSong(fix);
        }
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

    try {
      final validPaths = pickedFiles
          .map((f) => f.path)
          .whereType<String>()
          .toList();
      return await _processAudioFilePaths(validPaths);
    } finally {
      // copyWith 的 null 参数语义是“保留旧值”，进度字段必须用全新状态
      // 整体重置，否则扫描结束后文案/百分比仍残留在状态里。
      state = LibraryState(songs: state.songs);
    }
  }

  /// Recursively collects supported audio file paths under [roots] inside a
  /// background isolate, resolving symlinks and de-duplicating via a Set.
  Future<List<String>> _collectAudioFiles(Iterable<String> roots) async {
    final rootList = roots.toList(growable: false);
    if (rootList.isEmpty) return const [];
    const exts = _supportedExtensions;
    return Isolate.run(() async {
      final extSet = exts.toSet();
      final found = <String>{};
      for (final root in rootList) {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        try {
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (extSet.contains(ext)) {
                var canonical = entity.path;
                try {
                  canonical = entity.resolveSymbolicLinksSync();
                } catch (_) {}
                found.add(canonical);
              }
            }
          }
        } catch (_) {}
      }
      return found.toList(growable: false);
    });
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

    try {
      final audioFilePaths = await _collectAudioFiles([directoryPath]);
      if (audioFilePaths.isEmpty) {
        return 0;
      }

      state = state.copyWith(
        scanProgressText: '发现 ${audioFilePaths.length} 首歌曲，正在解析标签与内嵌封面...',
        scanProgressPercent: 0.0,
      );

      return await _processAudioFilePaths(audioFilePaths);
    } finally {
      // copyWith 的 null 参数语义是“保留旧值”，进度字段必须用全新状态
      // 整体重置，否则扫描结束后文案/百分比仍残留在状态里。
      state = LibraryState(songs: state.songs);
    }
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

    try {
      final audioFilePaths = await _collectAudioFiles(commonDirs);
      if (audioFilePaths.isEmpty) {
        return 0;
      }

      return await _processAudioFilePaths(audioFilePaths);
    } finally {
      // copyWith 的 null 参数语义是“保留旧值”，进度字段必须用全新状态
      // 整体重置，否则扫描结束后文案/百分比仍残留在状态里。
      state = LibraryState(songs: state.songs);
    }
  }

  Future<int> _processAudioFilePaths(List<String> paths) async {
    final newSongs = <Song>[];
    final currentSongs = state.songs;

    final existingByPath = <String, Song>{
      for (final s in currentSongs) s.filePath: s,
    };
    final existingMetaMap = <String, Song>{
      for (final s in currentSongs)
        if (s.title.trim().isNotEmpty &&
            s.artist.trim().isNotEmpty &&
            s.artist.trim() != '未知歌手')
          '${s.title.trim().toLowerCase()}|${s.artist.trim().toLowerCase()}': s,
    };

    final pendingPaths = <String>[];
    for (final filePath in paths) {
      final existing = existingByPath[filePath];
      if (existing != null &&
          existing.albumArtUri != null &&
          existing.albumArtUri!.isNotEmpty) {
        continue;
      }
      pendingPaths.add(filePath);
    }
    if (pendingPaths.isEmpty) return 0;

    final coverCacheDirPath =
        await MetadataExtractor.resolveCoverCacheDirPath();
    final existingUpdates = <String, Song Function(Song current)>{};

    const chunkSize = 12;
    const maxConcurrentIsolates = 3;
    final chunks = <List<String>>[
      for (int i = 0; i < pendingPaths.length; i += chunkSize)
        pendingPaths.sublist(
          i,
          (i + chunkSize < pendingPaths.length)
              ? i + chunkSize
              : pendingPaths.length,
        ),
    ];

    int processed = 0;
    for (int waveStart = 0;
        waveStart < chunks.length;
        waveStart += maxConcurrentIsolates) {
      final waveEnd = (waveStart + maxConcurrentIsolates < chunks.length)
          ? waveStart + maxConcurrentIsolates
          : chunks.length;
      final wave = chunks.sublist(waveStart, waveEnd);

      final waveResults = await Future.wait([
        for (final chunk in wave)
          Isolate.run(
            () => MetadataExtractor.extractChunkIsolated(
              chunk,
              coverCacheDirPath,
            ),
          ),
      ]);

      for (int w = 0; w < wave.length; w++) {
        final chunk = wave[w];
        final metas = waveResults[w];
        processed += chunk.length;
        state = state.copyWith(
          scanProgressText:
              '正在解析 ($processed/${pendingPaths.length}): ${p.basename(chunk.last)}',
          scanProgressPercent: processed / pendingPaths.length,
        );

        for (int j = 0; j < chunk.length; j++) {
          final filePath = chunk[j];
          final metadata = metas[j];
          final existing = existingByPath[filePath];

          // 内嵌歌词缺失时再找同名 .lrc 侧车文件。
          var lyrics = metadata.lyrics;
          if (lyrics == null || lyrics.trim().isEmpty) {
            lyrics = await _readSidecarLrc(filePath);
          }

          if (existing != null) {
            final needLrc =
                existing.lrcContent == null ||
                existing.lrcContent!.trim().isEmpty;
            final hasNewLrc = lyrics != null && lyrics.trim().isNotEmpty;
            if (metadata.albumArtUri != null || (needLrc && hasNewLrc)) {
              final artUri = metadata.albumArtUri;
              final resolvedLrc = lyrics;
              existingUpdates[existing.id] = (current) {
                final currentNeedLrc =
                    current.lrcContent == null ||
                    current.lrcContent!.trim().isEmpty;
                return current.copyWith(
                  albumArtUri: current.albumArtUri ?? artUri,
                  lrcContent: currentNeedLrc && hasNewLrc ? resolvedLrc : null,
                );
              };
            }
            continue;
          }

          final titleNorm = metadata.title.trim().toLowerCase();
          final artistNorm = metadata.artist.trim().toLowerCase();
          final metaKey = '$titleNorm|$artistNorm';

          // Check metadata deduplication (same title + artist + close duration)
          if (titleNorm.isNotEmpty &&
              titleNorm != '未知曲目' &&
              titleNorm != '本地歌曲' &&
              artistNorm != '未知歌手') {
            final dup = existingMetaMap[metaKey];
            if (dup != null) {
              if (dup.durationMs == 0 ||
                  metadata.durationMs == 0 ||
                  (dup.durationMs - metadata.durationMs).abs() < 3000) {
                continue;
              }
            }
          }

          final hasArtUri =
              metadata.albumArtUri != null && metadata.albumArtUri!.isNotEmpty;
          final song = Song(
            id: _uuid.v4(),
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            durationMs: metadata.durationMs,
            filePath: filePath,
            albumArtUri: metadata.albumArtUri,
            albumArtBytes: hasArtUri ? null : metadata.albumArtBytes,
            lrcContent: (lyrics != null && lyrics.trim().isNotEmpty)
                ? lyrics
                : null,
            dateAdded: DateTime.now(),
            source: SongSource.local,
            year: metadata.year,
          );

          existingByPath[filePath] = song;
          if (artistNorm != '未知歌手') {
            existingMetaMap[metaKey] = song;
          }
          newSongs.add(song);
        }
      }
    }

    if (existingUpdates.isNotEmpty) {
      await updateSongsMerged(existingUpdates);
    }

    if (newSongs.isNotEmpty) {
      await _storageService.saveSongs(newSongs);
      await _loadSongs();
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

    try {
      int enrichedCount = 0;
      int failedCount = 0;
      final pendingUpdates = <String, Song Function(Song current)>{};

      Future<void> flushUpdates() async {
        if (pendingUpdates.isEmpty) return;
        final batch = Map<String, Song Function(Song current)>.from(
          pendingUpdates,
        );
        pendingUpdates.clear();
        final applied = await updateSongsMerged(batch);
        enrichedCount += applied.length;
      }

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
              newArtUri = await onlineService.cacheOnlineImage(
                result.coverUrl!,
              );
            }
            final newLrc =
                song.lrcContent ?? result.syncedLyrics ?? result.plainLyrics;

            if (newArtUri != song.albumArtUri || newLrc != song.lrcContent) {
              final capturedArt = newArtUri;
              final capturedLrc = newLrc;
              pendingUpdates[song.id] = (current) => current.copyWith(
                albumArtUri: current.albumArtUri ?? capturedArt,
                lrcContent: current.lrcContent ?? capturedLrc,
              );
              if (pendingUpdates.length >= 10) {
                await flushUpdates();
              }
            }
          }
        } catch (_) {
          failedCount++;
        }
      }

      await flushUpdates();
      await _loadSongs();
      return BatchMatchResult(
        total: targets.length,
        enriched: enrichedCount,
        failed: failedCount,
      );
    } finally {
      // copyWith 的 null 参数语义是“保留旧值”，进度字段必须用全新状态
      // 整体重置，否则扫描结束后文案/百分比仍残留在状态里。
      state = LibraryState(songs: state.songs);
    }
  }

  Future<void> deleteSong(Song song) async {
    await _storageService.deleteSong(song.id);
    state = state.copyWith(
      songs: state.songs.where((s) => s.id != song.id).toList(),
    );
  }

  /// 批量收藏/取消收藏。返回受影响歌曲数。
  Future<int> setFavorites(List<String> songIds, bool favorite) async {
    final idSet = songIds.toSet();
    final updated = <Song>[];
    for (final song in state.songs) {
      if (!idSet.contains(song.id) || song.isFavorite == favorite) continue;
      updated.add(song.copyWith(isFavorite: favorite));
    }
    if (updated.isNotEmpty) {
      await _storageService.saveSongs(updated);
      for (final next in updated) {
        _audioHandler?.syncSong(next);
      }
      final byId = {for (final s in updated) s.id: s};
      state = state.copyWith(
        songs: [for (final s in state.songs) byId[s.id] ?? s],
      );
    }
    return updated.length;
  }

  /// 批量从曲库移除（本地文件不受影响）。
  Future<int> deleteSongsByIds(List<String> songIds) async {
    if (songIds.isEmpty) return 0;
    final idSet = songIds.toSet();
    await _storageService.deleteSongs(songIds);
    state = state.copyWith(
      songs: state.songs.where((s) => !idSet.contains(s.id)).toList(),
    );
    return songIds.length;
  }

  /// 找出磁盘上已不存在（被移动/删除）的曲库歌曲。
  Future<List<Song>> findMissingFiles() async {
    final missing = <Song>[];
    const chunkSize = 32;
    for (var i = 0; i < state.songs.length; i += chunkSize) {
      final chunk = state.songs.sublist(
        i,
        (i + chunkSize < state.songs.length)
            ? i + chunkSize
            : state.songs.length,
      );
      final results = await Future.wait([
        for (final s in chunk)
          s.filePath.isEmpty
              ? Future.value(false)
              : File(s.filePath).exists(),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        if (!results[j]) missing.add(chunk[j]);
      }
    }
    return missing;
  }

  /// 移除全部失效歌曲。返回移除数量。
  Future<int> removeMissingFiles() async {
    final missing = await findMissingFiles();
    if (missing.isEmpty) return 0;
    await _storageService.deleteSongs([for (final s in missing) s.id]);
    final removedIds = missing.map((s) => s.id).toSet();
    state = state.copyWith(
      songs: state.songs.where((s) => !removedIds.contains(s.id)).toList(),
    );
    return missing.length;
  }

  /// 扫描与音频同目录同名 `.lrc` 文件，为缺失歌词的歌曲补齐。
  /// 返回补齐的歌曲数。
  Future<int> scanSidecarLyrics() async {
    final updates = <String, Song Function(Song current)>{};
    for (final song in state.songs) {
      if (song.lrcContent != null && song.lrcContent!.trim().isNotEmpty) {
        continue;
      }
      final lrc = await _readSidecarLrc(song.filePath);
      if (lrc == null) continue;
      updates[song.id] = (current) => current.lrcContent == null
          ? current.copyWith(lrcContent: lrc)
          : current;
    }
    if (updates.isEmpty) return 0;
    final applied = await updateSongsMerged(updates);
    return applied.length;
  }

  /// `<音频文件名>.lrc` 侧车歌词；读取失败或不存在返回 null。
  static Future<String?> _readSidecarLrc(String audioPath) async {
    if (audioPath.isEmpty) return null;
    try {
      final lrcPath =
          '${audioPath.substring(0, audioPath.length - p.extension(audioPath).length)}.lrc';
      final file = File(lrcPath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return content.trim().isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }

  /// 把刚下载到磁盘的音频登记进曲库。
  ///
  /// 解析元数据（含同目录 `.lrc` sidecar）并写入 QQ 音乐关联字段：有了
  /// `qqSongMid` 后，「我喜欢」收藏页会自动把这首本地文件与云端曲目对上，
  /// 不再显示为「仅在线」。同路径已有记录时只补关联字段，不重复入库。
  Future<Song?> addDownloadedFile({
    required String filePath,
    String? qqSongMid,
    int? qqSongId,
    String? qqMediaMid,
    String? fallbackTitle,
    String? fallbackArtist,
    String? fallbackAlbum,
    String? lrcContent,
  }) async {
    if (filePath.trim().isEmpty) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;

    Song? existing;
    for (final song in state.songs) {
      if (song.filePath == filePath) {
        existing = song;
        break;
      }
    }
    if (existing != null) {
      final needsLink = (qqSongMid != null &&
              qqSongMid.isNotEmpty &&
              existing.qqSongMid != qqSongMid) ||
          existing.source != SongSource.local;
      if (!needsLink) return existing;
      final linked = await updateSongMerged(
        existing.id,
        (current) => current.copyWith(
          source: SongSource.local,
          qqSongMid: qqSongMid ?? current.qqSongMid,
          qqSongId: qqSongId ?? current.qqSongId,
          qqMediaMid: qqMediaMid ?? current.qqMediaMid,
        ),
      );
      return linked;
    }

    final metadata = await MetadataExtractor.extractFromFile(filePath);
    var lyrics = lrcContent ?? metadata.lyrics;
    if (lyrics == null || lyrics.trim().isEmpty) {
      lyrics = await _readSidecarLrc(filePath);
    }

    // 标签缺失时（下载站音频常见）用调用方给的、或文件名兜底出的名字。
    final metaTitle = metadata.title.trim();
    final metaArtist = metadata.artist.trim();
    final title = metaTitle.isEmpty || metaTitle == '未知曲目'
        ? (fallbackTitle?.trim().isNotEmpty == true
              ? fallbackTitle!.trim()
              : p.basenameWithoutExtension(filePath))
        : metadata.title;
    final artist = metaArtist.isEmpty || metaArtist == '未知歌手'
        ? (fallbackArtist?.trim() ?? '未知歌手')
        : metadata.artist;
    final album = metadata.album.trim().isEmpty || metadata.album == '未知专辑'
        ? (fallbackAlbum?.trim().isNotEmpty == true
              ? fallbackAlbum!.trim()
              : '本地音乐')
        : metadata.album;

    final song = Song(
      id: _uuid.v4(),
      title: title,
      artist: artist,
      album: album,
      durationMs: metadata.durationMs,
      filePath: filePath,
      albumArtUri: metadata.albumArtUri,
      albumArtBytes: (metadata.albumArtUri != null &&
              metadata.albumArtUri!.isNotEmpty)
          ? null
          : metadata.albumArtBytes,
      lrcContent: (lyrics != null && lyrics.trim().isNotEmpty) ? lyrics : null,
      dateAdded: DateTime.now(),
      source: SongSource.local,
      year: metadata.year,
      qqSongMid: qqSongMid,
      qqSongId: qqSongId,
      qqMediaMid: qqMediaMid,
    );

    await _storageService.saveSong(song);
    await _loadSongs();
    return song;
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

  /// Applies [update] onto the freshest copy of the song (re-read from
  /// storage) before persisting. Callers holding a snapshot captured before
  /// an await (cover download, lyrics fetch, dialog editing…) must use this
  /// instead of [updateSong]: writing the stale snapshot wholesale would
  /// revert playCount / isFavorite / lyrics changes that happened meanwhile,
  /// because the audio handler bumps playCount directly in the songs box.
  /// Returns the persisted merged song, or null when the song was deleted
  /// meanwhile (a slow async task must not resurrect it).
  Future<Song?> updateSongMerged(
    String songId,
    Song Function(Song current) update,
  ) async {
    final current = _storageService.getSong(songId);
    if (current == null) return null;
    final merged = update(current);
    await _storageService.saveSong(merged);
    if (state.songs.any((s) => s.id == songId)) {
      state = state.copyWith(
        songs: state.songs.map((s) => s.id == songId ? merged : s).toList(),
      );
    }
    _audioHandler?.syncSong(merged);
    return merged;
  }

  /// Batch counterpart to [updateSongMerged]: reads freshest stored copies,
  /// writes once with `saveSongs`, updates `state.songs` once, and syncs the
  /// audio handler, avoiding O(N) cascading state rebuilds during bulk sync.
  Future<List<Song>> updateSongsMerged(
    Map<String, Song Function(Song current)> updates,
  ) async {
    if (updates.isEmpty) return const [];
    final persisted = <Song>[];
    final byId = <String, Song>{};
    for (final entry in updates.entries) {
      final current = _storageService.getSong(entry.key);
      if (current == null) continue;
      final merged = entry.value(current);
      persisted.add(merged);
      byId[merged.id] = merged;
    }
    if (persisted.isEmpty) return const [];

    await _storageService.saveSongs(persisted);
    state = state.copyWith(
      songs: [for (final s in state.songs) byId[s.id] ?? s],
    );
    for (final song in persisted) {
      _audioHandler?.syncSong(song);
    }
    return persisted;
  }

  /// Re-reads [songId] from storage and patches the in-memory copy when the
  /// persisted play count moved ahead of it. The audio handler increments the
  /// count directly in the songs box as each song starts, and playCount is
  /// the only field it mutates behind this notifier's back, so replacing the
  /// whole entry with the box copy is safe.
  void refreshPlayCountFromStorage(String songId) {
    final fresh = _storageService.getSong(songId);
    if (fresh == null) return;
    final index = state.songs.indexWhere((s) => s.id == songId);
    if (index == -1 || state.songs[index].playCount == fresh.playCount) return;
    final songs = [...state.songs];
    songs[index] = fresh;
    state = state.copyWith(songs: songs);
  }
}

final libraryNotifierProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
      final storage = ref.watch(storageServiceProvider);
      SoundCraftAudioHandler? handler;
      try {
        handler = ref.watch(audioHandlerProvider);
      } catch (_) {}
      final notifier = LibraryNotifier(storage, handler);

      // Mirror the handler-side play count increments into the in-memory
      // library so list UIs and play-count sorting stay current in-session.
      final sub = handler?.currentSongStream.listen((song) {
        if (song != null) notifier.refreshPlayCountFromStorage(song.id);
      });
      if (sub != null) {
        ref.onDispose(sub.cancel);
      }

      return notifier;
    });

final filteredSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(libraryNotifierProvider.select((s) => s.songs));
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sortType = ref.watch(sortTypeProvider);
  final ascending = ref.watch(sortAscendingProvider);

  // Skip unused lowercased strings when neither searching nor sorting by text.
  if (query.isEmpty &&
      sortType != SongSortType.title &&
      sortType != SongSortType.artist) {
    final sorted = List<Song>.of(songs);
    sorted.sort((a, b) {
      final int cmp;
      switch (sortType) {
        case SongSortType.duration:
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
        case SongSortType.playCount:
          cmp = a.playCount.compareTo(b.playCount);
          break;
        case SongSortType.dateAdded:
        case SongSortType.title:
        case SongSortType.artist:
          cmp = a.dateAdded.compareTo(b.dateAdded);
          break;
      }
      return ascending ? cmp : -cmp;
    });
    return sorted;
  }

  // Decorate-sort-undecorate: lowercased search/sort keys are computed once
  // per song instead of on every comparator invocation (O(n log n) calls).
  var decorated = [
    for (final s in songs)
      (
        s,
        (query.isNotEmpty || sortType == SongSortType.title)
            ? s.title.toLowerCase()
            : '',
        (query.isNotEmpty || sortType == SongSortType.artist)
            ? s.artist.toLowerCase()
            : '',
        query.isNotEmpty ? s.album.toLowerCase() : '',
      ),
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
