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

enum SongSortType {
  dateAdded,
  title,
  artist,
  duration,
  playCount,
}

final searchQueryProvider = StateProvider<String>((ref) => '');
final sortTypeProvider = StateProvider<SongSortType>((ref) => SongSortType.dateAdded);
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

  LibraryNotifier(this._storageService, [this._audioHandler]) : super(const LibraryState()) {
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
    final seenKeys = <String>{};

    for (final song in songs) {
      String canonicalPath = song.filePath;
      try {
        if (File(song.filePath).existsSync()) {
          canonicalPath = File(song.filePath).resolveSymbolicLinksSync();
        }
      } catch (_) {}

      final titleNorm = song.title.trim().toLowerCase();
      final artistNorm = song.artist.trim().toLowerCase();
      final metaKey = '$titleNorm|$artistNorm';

      if (seenPaths.contains(canonicalPath) || seenPaths.contains(song.filePath)) {
        continue;
      }

      if (titleNorm.isNotEmpty && titleNorm != '未知曲目' && titleNorm != '本地歌曲' && artistNorm != '未知歌手') {
        if (seenKeys.contains(metaKey)) {
          final existing = unique.firstWhere(
            (s) => s.title.trim().toLowerCase() == titleNorm && s.artist.trim().toLowerCase() == artistNorm,
            orElse: () => song,
          );
          if (existing.id != song.id) {
            if (existing.durationMs == 0 || song.durationMs == 0 || (existing.durationMs - song.durationMs).abs() < 3000) {
              continue;
            }
          }
        }
      }

      seenPaths.add(canonicalPath);
      seenPaths.add(song.filePath);
      if (artistNorm != '未知歌手') {
        seenKeys.add(metaKey);
      }
      unique.add(song);
    }
    return unique;
  }

  void _fixMissingDurations(List<Song> songs) {
    final missing = songs.where((s) => s.durationMs <= 0 && s.filePath.isNotEmpty).toList();
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
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'm4a', 'wav', 'aac', 'ogg', 'opus', 'wma', 'ape', 'alac'],
    );

    if (pickedFiles.isEmpty) {
      return 0;
    }

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '正在解析选中音频元数据与封面...',
      scanProgressPercent: 0.0,
    );

    final validPaths = pickedFiles.map((f) => f.path).whereType<String>().toList();
    final count = await _processAudioFilePaths(validPaths);

    state = state.copyWith(isScanning: false, scanProgressText: null, scanProgressPercent: null);
    return count;
  }

  Future<int> importFolder() async {
    final hasPermission = await requestStoragePermission();
    if (!hasPermission) return 0;

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

    final audioFilePaths = <String>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_supportedExtensions.contains(ext)) {
            String canonical = entity.path;
            try {
              canonical = entity.resolveSymbolicLinksSync();
            } catch (_) {}
            if (!audioFilePaths.contains(canonical) && !audioFilePaths.contains(entity.path)) {
              audioFilePaths.add(canonical);
            }
          }
        }
      }
    } catch (_) {}

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
    state = state.copyWith(isScanning: false, scanProgressText: null, scanProgressPercent: null);
    return count;
  }

  Future<int> scanSystemMusicDirectory() async {
    final hasPermission = await requestStoragePermission();
    if (!hasPermission) return 0;

    final audioFilePaths = <String>[];
    final commonDirs = [
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

    for (final path in commonDirs) {
      final d = Directory(path);
      if (await d.exists()) {
        try {
          await for (final entity in d.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (_supportedExtensions.contains(ext)) {
                String canonical = entity.path;
                try {
                  canonical = entity.resolveSymbolicLinksSync();
                } catch (_) {}
                if (!audioFilePaths.contains(canonical) && !audioFilePaths.contains(entity.path)) {
                  audioFilePaths.add(canonical);
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    if (audioFilePaths.isEmpty) {
      state = state.copyWith(isScanning: false, scanProgressText: null);
      return 0;
    }

    final count = await _processAudioFilePaths(audioFilePaths);
    state = state.copyWith(isScanning: false, scanProgressText: null, scanProgressPercent: null);
    return count;
  }

  Future<int> _processAudioFilePaths(List<String> paths) async {
    final newSongs = <Song>[];
    final currentSongs = state.songs;

    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      final percent = (i + 1) / paths.length;

      state = state.copyWith(
        scanProgressText: '正在解析 (${i + 1}/${paths.length}): ${p.basename(path)}',
        scanProgressPercent: percent,
      );

      String canonicalPath = path;
      try {
        if (File(path).existsSync()) {
          canonicalPath = File(path).resolveSymbolicLinksSync();
        }
      } catch (_) {}

      // 1. Check path deduplication against both existing library and current scan batch
      if (currentSongs.any((s) => s.filePath == path || s.filePath == canonicalPath) ||
          newSongs.any((s) => s.filePath == path || s.filePath == canonicalPath)) {
        continue;
      }

      final metadata = await MetadataExtractor.extractFromFile(path);

      final titleNorm = metadata.title.trim().toLowerCase();
      final artistNorm = metadata.artist.trim().toLowerCase();

      // 2. Check metadata deduplication (same title + artist + close duration)
      if (titleNorm.isNotEmpty && titleNorm != '未知曲目' && titleNorm != '本地歌曲' && artistNorm != '未知歌手') {
        final isDupInCurrent = currentSongs.any((s) =>
            s.title.trim().toLowerCase() == titleNorm &&
            s.artist.trim().toLowerCase() == artistNorm &&
            (s.durationMs == 0 || metadata.durationMs == 0 || (s.durationMs - metadata.durationMs).abs() < 3000));
        final isDupInNew = newSongs.any((s) =>
            s.title.trim().toLowerCase() == titleNorm &&
            s.artist.trim().toLowerCase() == artistNorm &&
            (s.durationMs == 0 || metadata.durationMs == 0 || (s.durationMs - metadata.durationMs).abs() < 3000));

        if (isDupInCurrent || isDupInNew) {
          continue;
        }
      }

      final song = Song(
        id: _uuid.v4(),
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        durationMs: metadata.durationMs,
        filePath: canonicalPath.isNotEmpty ? canonicalPath : path,
        albumArtUri: metadata.albumArtUri,
        albumArtBytes: metadata.albumArtBytes,
        dateAdded: DateTime.now(),
        source: SongSource.local,
        year: metadata.year,
      );

      newSongs.add(song);
    }

    if (newSongs.isNotEmpty) {
      await _storageService.saveSongs(newSongs);
      _loadSongs();
    }

    return newSongs.length;
  }

  Future<int> batchAutoMatchOnlineMetadata(OnlineMetadataService onlineService) async {
    final targets = state.songs.where((s) => s.albumArtUri == null || s.lrcContent == null).toList();
    if (targets.isEmpty) return 0;

    state = state.copyWith(
      isScanning: true,
      scanProgressText: '正在跨库智能检索 ${targets.length} 首歌曲的封面与歌词...',
      scanProgressPercent: 0.0,
    );

    int enrichedCount = 0;
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
          final newLrc = song.lrcContent ?? result.syncedLyrics ?? result.plainLyrics;

          if (newArtUri != song.albumArtUri || newLrc != song.lrcContent) {
            final updated = song.copyWith(
              albumArtUri: newArtUri,
              lrcContent: newLrc,
            );
            await _storageService.saveSong(updated);
            enrichedCount++;
          }
        }
      } catch (_) {}
    }

    _loadSongs();
    state = state.copyWith(isScanning: false, scanProgressText: null, scanProgressPercent: null);
    return enrichedCount;
  }

  Future<void> deleteSong(Song song) async {
    await _storageService.deleteSong(song.id);
    _loadSongs();
  }

  Future<void> toggleFavorite(Song song) async {
    await _storageService.toggleFavorite(song.id);
    _loadSongs();
    final updated = _storageService.getSong(song.id);
    if (updated != null) {
      _audioHandler?.syncSong(updated);
    }
  }

  Future<void> updateSong(Song song) async {
    await _storageService.saveSong(song);
    _loadSongs();
    _audioHandler?.syncSong(song);
  }
}

final libraryNotifierProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final handler = ref.watch(audioHandlerProvider);
  return LibraryNotifier(storage, handler);
});

final filteredSongsProvider = Provider<List<Song>>((ref) {
  final library = ref.watch(libraryNotifierProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sortType = ref.watch(sortTypeProvider);
  final ascending = ref.watch(sortAscendingProvider);

  var list = List<Song>.from(library.songs);

  if (query.isNotEmpty) {
    list = list.where((s) {
      return s.title.toLowerCase().contains(query) ||
          s.artist.toLowerCase().contains(query) ||
          s.album.toLowerCase().contains(query);
    }).toList();
  }

  list.sort((a, b) {
    int cmp = 0;
    switch (sortType) {
      case SongSortType.title:
        cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        break;
      case SongSortType.artist:
        cmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        break;
      case SongSortType.duration:
        cmp = a.durationMs.compareTo(b.durationMs);
        break;
      case SongSortType.playCount:
        cmp = a.playCount.compareTo(b.playCount);
        break;
      case SongSortType.dateAdded:
        cmp = a.dateAdded.compareTo(b.dateAdded);
        break;
    }
    return ascending ? cmp : -cmp;
  });

  return list;
});
