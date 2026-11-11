import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_player_handler.dart';
import '../core/utils/song_matcher.dart';
import '../core/utils/formatters.dart';
import '../models/listening_stats.dart';
import '../models/qq_music_config.dart';
import '../models/song.dart';
import '../services/qq_music_service.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

final qqMusicServiceProvider = Provider<QQMusicService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final service = QQMusicService(
    desktopGuid: storage.getQQMusicDesktopGuid(),
  );
  ref.onDispose(service.dispose);
  return service;
});

class QQMusicFavoritesState {
  final QQMusicConfig config;
  final List<Song> remoteSongs;
  final List<Song> mergedSongs;
  final bool isSyncing;
  final String? syncError;
  final QQMusicCloudStatsSummary cloudStatsSummary;

  const QQMusicFavoritesState({
    this.config = const QQMusicConfig(),
    this.remoteSongs = const [],
    this.mergedSongs = const [],
    this.isSyncing = false,
    this.syncError,
    this.cloudStatsSummary = const QQMusicCloudStatsSummary(),
  });

  bool get isBound => config.isBound;

  int get localMatchedCount =>
      mergedSongs.where((s) => s.hasLocalFile).length;

  QQMusicFavoritesState copyWith({
    QQMusicConfig? config,
    List<Song>? remoteSongs,
    List<Song>? mergedSongs,
    bool? isSyncing,
    String? syncError,
    bool clearSyncError = false,
    QQMusicCloudStatsSummary? cloudStatsSummary,
  }) {
    return QQMusicFavoritesState(
      config: config ?? this.config,
      remoteSongs: remoteSongs ?? this.remoteSongs,
      mergedSongs: mergedSongs ?? this.mergedSongs,
      isSyncing: isSyncing ?? this.isSyncing,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      cloudStatsSummary: cloudStatsSummary ?? this.cloudStatsSummary,
    );
  }
}

class QQMusicFavoritesNotifier extends StateNotifier<QQMusicFavoritesState> {
  final StorageService _storageService;
  final QQMusicService _qqMusicService;
  final LibraryNotifier _libraryNotifier;
  final SoundCraftAudioHandler? _audioHandler;
  final bool _autoSyncOnInit;

  QQMusicFavoritesNotifier(
    this._storageService,
    this._qqMusicService,
    this._libraryNotifier, [
    this._audioHandler,
    this._autoSyncOnInit = true,
  ]) : super(const QQMusicFavoritesState()) {
    _initFromCache();
  }

  void _initFromCache() {
    final savedConfig = _storageService.getQQMusicConfig();
    final cachedRemote = _storageService.getQQMusicFavoritesCache();
    final localSongs = _libraryNotifier.state.songs;
    final cloudStats = _storageService.getQQMusicCloudStatsSummary();

    final (merged, _) = _mergeWithLocal(cachedRemote, localSongs);
    state = QQMusicFavoritesState(
      config: savedConfig,
      remoteSongs: cachedRemote,
      mergedSongs: merged,
      cloudStatsSummary: cloudStats,
    );

    if (_autoSyncOnInit && savedConfig.isBound) {
      // 启动后后台静默同步最新「我喜欢」歌单，不阻塞首屏缓存秒开。
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (mounted && state.config.isBound) {
          unawaited(syncFavorites(silent: true));
        }
      });
    }
  }

  /// 当本地曲库发生变化（如新扫描导入了本地音频）时，重新对齐本地文件与 QQ 音乐收藏。
  void onLocalLibraryUpdated(List<Song> localSongs) {
    if (!mounted) return;
    final (merged, _) = _mergeWithLocal(state.remoteSongs, localSongs);
    state = state.copyWith(mergedSongs: merged);
  }

  /// 当一首 QQ 音乐在线曲目或关联曲目开始播放后，从 StorageService 刷新内存中的播放次数与云端统计摘要。
  void refreshPlayCountFromStorage(String songId) {
    if (!mounted) return;
    final cachedRemote = _storageService.getQQMusicFavoritesCache();
    final cloudStats = _storageService.getQQMusicCloudStatsSummary();
    if (cachedRemote.isEmpty) {
      state = state.copyWith(cloudStatsSummary: cloudStats);
      return;
    }
    final (merged, _) = _mergeWithLocal(
      cachedRemote,
      _libraryNotifier.state.songs,
    );
    state = state.copyWith(
      remoteSongs: cachedRemote,
      mergedSongs: merged,
      cloudStatsSummary: cloudStats,
    );
  }

  /// 刷新云端听歌上报与同步摘要状态。
  void refreshCloudStatsSummary() {
    if (!mounted) return;
    state = state.copyWith(
      cloudStatsSummary: _storageService.getQQMusicCloudStatsSummary(),
    );
  }

  /// 绑定/更新 QQ 音乐配置并立即执行一次同步。
  /// 返回同步结果文案；若抛出 [QQMusicApiException] 则同步失败。
  Future<String> saveConfigAndSync(QQMusicConfig newConfig) async {
    await _storageService.saveQQMusicConfig(newConfig);
    state = state.copyWith(
      config: newConfig,
      clearSyncError: true,
    );
    return syncFavorites(silent: false);
  }

  /// 解除 QQ 音乐收藏绑定并清空收藏缓存。
  Future<void> unbind() async {
    await _storageService.clearQQMusicConfig();
    state = const QQMusicFavoritesState();
  }

  /// 从 QQ 音乐拉取最新「我喜欢」歌单及云端听歌记录并对齐本地曲库与统计。
  Future<String> syncFavorites({bool silent = false}) async {
    if (!state.config.isBound) {
      return '请先绑定 QQ 音乐账号或歌单';
    }
    if (state.isSyncing) {
      return '正在同步中，请稍候...';
    }

    state = state.copyWith(isSyncing: true, clearSyncError: true);

    try {
      final payload = await _qqMusicService.syncFavoritePlaylist(state.config);
      if (!mounted) return '';

      // 保留旧缓存中已获取过的在线歌词与播放次数
      final oldByMid = <String, Song>{
        for (final s in state.remoteSongs)
          if (s.qqSongMid != null && s.qqSongMid!.isNotEmpty)
            s.qqSongMid!: s,
      };

      var enrichedRemote = <Song>[
        for (final fresh in payload.songs)
          () {
            final prev = fresh.qqSongMid != null
                ? oldByMid[fresh.qqSongMid!]
                : null;
            if (prev == null) return fresh;
            return fresh.copyWith(
              lrcContent: fresh.lrcContent ?? prev.lrcContent,
              albumArtUri: fresh.albumArtUri ?? prev.albumArtUri,
              playCount:
                  fresh.playCount >= prev.playCount
                      ? fresh.playCount
                      : prev.playCount,
            );
          }(),
      ];

      final updatedConfig = state.config.copyWith(
        uin: payload.uin.isNotEmpty ? payload.uin : state.config.uin,
        dissid: payload.dissid.isNotEmpty ? payload.dissid : state.config.dissid,
        nickname: payload.nickname.isNotEmpty
            ? payload.nickname
            : state.config.nickname,
        playlistName: payload.playlistName.isNotEmpty
            ? payload.playlistName
            : state.config.playlistName,
        lastSyncMs: DateTime.now().millisecondsSinceEpoch,
      );

      await _storageService.saveQQMusicConfig(updatedConfig);
      await _storageService.saveQQMusicFavoritesCache(enrichedRemote);

      // 同步拉取 QQ 音乐云端听歌历史（每首曲目累计播放次数）与今日有效听歌时长
      var updatedCloudStats = 0;
      int? cloudTodaySeconds;
      try {
        final history = await _qqMusicService.fetchCloudListeningHistory(
          updatedConfig,
        );
        cloudTodaySeconds = await _qqMusicService.fetchTodayListenSeconds(
          updatedConfig,
        );
        if (history.isNotEmpty || (cloudTodaySeconds ?? 0) > 0) {
          updatedCloudStats = await _storageService
              .mergeQQMusicCloudListeningSongs(
                history,
                todayListenSeconds: cloudTodaySeconds,
              );
          enrichedRemote = _storageService.getQQMusicFavoritesCache();
        }
      } catch (_) {}

      final localSongs = _libraryNotifier.state.songs;
      final (merged, upgradedLocals) = _mergeWithLocal(
        enrichedRemote,
        localSongs,
      );

      // 将匹配到的本地歌曲的 qqSongMid 与 isFavorite 状态同步写回本地曲库
      for (final upgraded in upgradedLocals) {
        await _libraryNotifier.updateSongMerged(
          upgraded.id,
          (current) => current.copyWith(
            isFavorite: true,
            qqSongMid: current.qqSongMid ?? upgraded.qqSongMid,
            qqSongId: current.qqSongId ?? upgraded.qqSongId,
            qqMediaMid: current.qqMediaMid ?? upgraded.qqMediaMid,
            isVip: current.isVip || upgraded.isVip,
          ),
        );
      }

      if (!mounted) return '';
      state = state.copyWith(
        config: updatedConfig,
        remoteSongs: enrichedRemote,
        mergedSongs: merged,
        isSyncing: false,
        clearSyncError: true,
        cloudStatsSummary: _storageService.getQQMusicCloudStatsSummary(),
      );

      final matchedCount = merged.where((s) => s.hasLocalFile).length;
      final statsParts = <String>[
        if (updatedCloudStats > 0) '已更新 $updatedCloudStats 首云端播放次数',
        if ((cloudTodaySeconds ?? 0) > 0)
          '今日云端听歌 ${Formatters.formatListeningDuration(Duration(seconds: cloudTodaySeconds!), short: true)}',
      ];
      final statsSuffix = statsParts.isEmpty
          ? ''
          : '，${statsParts.join('，')}';
      return '已同步 QQ 音乐「${updatedConfig.playlistName}」共 ${merged.length} 首'
          '${matchedCount > 0 ? '（已关联 $matchedCount 首本地音频）' : ''}$statsSuffix';
    } on QQMusicApiException catch (e) {
      if (mounted) {
        state = state.copyWith(
          isSyncing: false,
          syncError: e.message,
        );
      }
      if (!silent) rethrow;
      return e.message;
    } catch (_) {
      const msg = '同步 QQ 音乐收藏失败，请检查网络连接后重试';
      if (mounted) {
        state = state.copyWith(
          isSyncing: false,
          syncError: msg,
        );
      }
      if (!silent) throw const QQMusicApiException(msg);
      return msg;
    }
  }

  /// 切换收藏状态（同时维护本地曲库、QQ 音乐收藏缓存及 Cookie 模式下的云端红心）。
  Future<({bool isFavorite, String? toastMessage})> toggleFavorite(
    Song song,
  ) async {
    if (!state.config.isBound) {
      final targetFav = !song.isFavorite;
      await _libraryNotifier.toggleFavorite(song);
      return (
        isFavorite: targetFav,
        toastMessage: targetFav ? '已添加到收藏' : '已取消收藏',
      );
    }

    final isCurrentlyInMerged = state.mergedSongs.any(
      (s) =>
          s.id == song.id ||
          (song.qqSongMid != null &&
              song.qqSongMid!.isNotEmpty &&
              s.qqSongMid == song.qqSongMid),
    );
    final nextFavorite = !isCurrentlyInMerged;

    if (nextFavorite) {
      final favSong = song.copyWith(isFavorite: true);
      final updatedRemote = [
        favSong,
        ...state.remoteSongs.where(
          (s) =>
              s.id != song.id &&
              (song.qqSongMid == null || s.qqSongMid != song.qqSongMid),
        ),
      ];
      await _storageService.saveQQMusicFavoritesCache(updatedRemote);

      if (_storageService.getSong(song.id) != null) {
        await _libraryNotifier.updateSongMerged(
          song.id,
          (c) => c.copyWith(isFavorite: true),
        );
      }
      _audioHandler?.syncSong(favSong);

      final (merged, _) = _mergeWithLocal(
        updatedRemote,
        _libraryNotifier.state.songs,
      );
      state = state.copyWith(
        remoteSongs: updatedRemote,
        mergedSongs: merged,
      );

      if (state.config.hasCookie &&
          song.qqSongMid != null &&
          song.qqSongMid!.isNotEmpty) {
        final synced = await _qqMusicService.addSongToQQFavorites(
          songMid: song.qqSongMid!,
          config: state.config,
        );
        return (
          isFavorite: true,
          toastMessage: synced
              ? '已收藏并同步至 QQ 音乐「我喜欢」'
              : '已加入本地收藏（QQ 音乐云端同步未成功）',
        );
      }
      return (
        isFavorite: true,
        toastMessage: state.config.hasCookie
            ? '已加入收藏'
            : '已加入本地收藏（配置 Cookie 可同步至 QQ 音乐云端）',
      );
    } else {
      final updatedRemote = state.remoteSongs
          .where(
            (s) =>
                s.id != song.id &&
                (song.qqSongMid == null ||
                    song.qqSongMid!.isEmpty ||
                    s.qqSongMid != song.qqSongMid),
          )
          .toList();
      await _storageService.saveQQMusicFavoritesCache(updatedRemote);

      if (_storageService.getSong(song.id) != null) {
        await _libraryNotifier.updateSongMerged(
          song.id,
          (c) => c.copyWith(isFavorite: false),
        );
      }
      final unfavSong = song.copyWith(isFavorite: false);
      _audioHandler?.syncSong(unfavSong);

      final (merged, _) = _mergeWithLocal(
        updatedRemote,
        _libraryNotifier.state.songs,
      );
      state = state.copyWith(
        remoteSongs: updatedRemote,
        mergedSongs: merged,
      );

      if (state.config.hasCookie &&
          song.qqSongId != null &&
          song.qqSongId! > 0) {
        final synced = await _qqMusicService.removeSongFromQQFavorites(
          songId: song.qqSongId!,
          config: state.config,
        );
        return (
          isFavorite: false,
          toastMessage: synced
              ? '已从 QQ 音乐「我喜欢」取消收藏'
              : '已从本地收藏移除（QQ 音乐云端同步未成功）',
        );
      }
      return (
        isFavorite: false,
        toastMessage: '已取消收藏',
      );
    }
  }

  /// 为纯在线 QQ 音乐收藏曲目持久化缓存歌词或封面。
  Future<void> cacheOnlineSongMetadata(
    String songId, {
    String? lrcContent,
    String? albumArtUri,
  }) async {
    final idx = state.remoteSongs.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
    final current = state.remoteSongs[idx];
    final updated = current.copyWith(
      lrcContent: lrcContent ?? current.lrcContent,
      albumArtUri: albumArtUri ?? current.albumArtUri,
    );
    final nextRemote = [...state.remoteSongs];
    nextRemote[idx] = updated;
    await _storageService.saveQQMusicFavoritesCache(nextRemote);

    final (merged, _) = _mergeWithLocal(
      nextRemote,
      _libraryNotifier.state.songs,
    );
    if (mounted) {
      state = state.copyWith(
        remoteSongs: nextRemote,
        mergedSongs: merged,
      );
    }
  }

  /// 将云端 QQ 曲目 [remote] 手动关联到本地文件 [local]。
  ///
  /// 用于自动匹配失败（元数据差异太大）或匹配错误的情况。关联会：
  /// 1. 写入手动关联表，优先级高于所有自动匹配，且重新同步不会丢；
  /// 2. 把 `qqSongMid` / `qqSongId` / `qqMediaMid` 写回本地曲库，
  ///    使本地文件也能解析在线流、上报播放与拉取云端歌词；
  /// 3. 清除该 mid 的「取消关联」标记。
  Future<String> linkLocalSong({
    required Song remote,
    required Song local,
  }) async {
    final mid = remote.qqSongMid?.trim() ?? '';
    if (mid.isEmpty) return '该曲目缺少 QQ 音乐标识，无法关联';

    await _storageService.saveQQMusicManualLink(
      songMid: mid,
      songId: local.id,
    );
    await _storageService.removeQQMusicManualExclusion(mid);
    await _libraryNotifier.updateSongMerged(
      local.id,
      (c) => c.copyWith(
        isFavorite: true,
        qqSongMid: mid,
        qqSongId: remote.qqSongId ?? c.qqSongId,
        qqMediaMid: remote.qqMediaMid ?? c.qqMediaMid,
        isVip: c.isVip || remote.isVip,
      ),
    );

    if (mounted) {
      final (merged, _) = _mergeWithLocal(
        state.remoteSongs,
        _libraryNotifier.state.songs,
      );
      state = state.copyWith(mergedSongs: merged);
    }
    return '已将《${remote.title}》关联到本地音频';
  }

  /// 取消云端曲目 [song] 与本地文件的关联。
  ///
  /// 同时加入排除集，否则下一次同步又会被自动匹配重新接上，
  /// 用户会觉得「取消不掉」。
  Future<String> unlinkLocalSong(Song song) async {
    final mid = song.qqSongMid?.trim() ?? '';
    if (mid.isEmpty) return '该曲目未关联本地文件';

    await _storageService.removeQQMusicManualLink(mid);
    await _storageService.addQQMusicManualExclusion(mid);

    // 清掉本地曲库上由关联写入的 QQ 标识与红心
    if (_storageService.getSong(song.id) != null) {
      await _libraryNotifier.updateSongMerged(
        song.id,
        (c) => c.copyWith(
          isFavorite: false,
          qqSongMid: '',
          qqSongId: 0,
          qqMediaMid: '',
        ),
      );
    }

    if (mounted) {
      final (merged, _) = _mergeWithLocal(
        state.remoteSongs,
        _libraryNotifier.state.songs,
      );
      state = state.copyWith(mergedSongs: merged);
    }
    return '已取消关联，后续同步不会再自动匹配';
  }

  /// 读取用户手动关联/排除设置后执行本地曲库合并（内部统一入口）。
  (List<Song>, List<Song>) _mergeWithLocal(List<Song> remoteSongs, List<Song> localSongs) {
    return mergeWithLocalSongs(
      remoteSongs,
      localSongs,
      manualLinks: _storageService.getQQMusicManualLinks(),
      manualExclusions: _storageService.getQQMusicManualExclusions(),
    );
  }

  /// 将 QQ 音乐收藏列表 [remoteSongs] 与本地曲库 [localSongs] 进行智能匹配对齐。
  ///
  /// 返回 `(合并后的收藏列表, 需要写回本地曲库的升级曲目列表)`。
  /// 将 QQ 音乐收藏列表 [remoteSongs] 与本地曲库 [localSongs] 进行智能匹配对齐。
  ///
  /// 匹配优先级：用户手动关联 [manualLinks] → `qqSongMid` 精确匹配 →
  /// 标题/歌手/时长模糊匹配。[manualExclusions] 中的云端曲目不参与任何匹配
  /// （用户已显式取消关联）。
  ///
  /// 返回 `(合并后的收藏列表, 需要写回本地曲库的升级曲目列表)`。
  static (List<Song>, List<Song>) mergeWithLocalSongs(
    List<Song> remoteSongs,
    List<Song> localSongs, {
    Map<String, String> manualLinks = const {},
    Set<String> manualExclusions = const {},
  }) {
    if (remoteSongs.isEmpty) return (const [], const []);

    final localByMid = <String, Song>{};
    final localById = <String, Song>{};
    final localByTitle = <String, List<Song>>{};

    for (final local in localSongs) {
      localById[local.id] = local;
      final mid = local.qqSongMid;
      if (mid != null && mid.isNotEmpty) {
        localByMid[mid] = local;
      }
      // 同时按「基础标题」与「完整标题」建索引，兼容一方带版本后缀的写法
      final baseKey = SongMatcher.titleKey(local.title);
      if (baseKey != null) {
        localByTitle.putIfAbsent(baseKey, () => []).add(local);
      }
      final fullKey = SongMatcher.compact(local.title);
      if (fullKey.isNotEmpty && fullKey != baseKey) {
        localByTitle.putIfAbsent(fullKey, () => []).add(local);
      }
    }

    final mergedList = <Song>[];
    final upgradedLocals = <Song>[];
    final upgradedIds = <String>{};
    // 一个本地文件只能被一首云端曲目认领，否则同一文件会在收藏页出现两次
    final claimedLocalIds = <String>{};

    for (final remote in remoteSongs) {
      Song? matchedLocal;
      final remoteMid = remote.qqSongMid;

      // 1) 用户手动关联优先于一切自动匹配
      if (remoteMid != null && remoteMid.isNotEmpty) {
        final manualId = manualLinks[remoteMid];
        if (manualId != null) {
          matchedLocal = localById[manualId];
        }
      }

      // 2) qqSongMid 精确匹配
      if (matchedLocal == null &&
          remoteMid != null &&
          remoteMid.isNotEmpty &&
          !manualExclusions.contains(remoteMid)) {
        matchedLocal = localByMid[remoteMid];
      }

      // 3) 标题/歌手/时长模糊匹配
      if (matchedLocal == null &&
          (remoteMid == null ||
              remoteMid.isEmpty ||
              !manualExclusions.contains(remoteMid))) {
        final baseKey = SongMatcher.titleKey(remote.title);
        final fullKey = SongMatcher.compact(remote.title);
        final candidates = <Song>{
          ...?localByTitle[baseKey],
          ...?localByTitle[fullKey],
        }.where((c) => !claimedLocalIds.contains(c.id));
        matchedLocal = SongMatcher.bestMatch(remote, candidates);
      }

      if (matchedLocal != null) {
        claimedLocalIds.add(matchedLocal.id);
        final merged = matchedLocal.copyWith(
          isFavorite: true,
          playCount: matchedLocal.playCount >= remote.playCount
              ? matchedLocal.playCount
              : remote.playCount,
          album: (matchedLocal.album.isEmpty ||
                      matchedLocal.album == '未知专辑') &&
                  remote.album.isNotEmpty
              ? remote.album
              : matchedLocal.album,
          albumArtUri: matchedLocal.albumArtUri ?? remote.albumArtUri,
          lrcContent: matchedLocal.lrcContent ?? remote.lrcContent,
          durationMs: matchedLocal.durationMs > 0
              ? matchedLocal.durationMs
              : remote.durationMs,
          qqSongMid: remote.qqSongMid ?? matchedLocal.qqSongMid,
          qqSongId: remote.qqSongId ?? matchedLocal.qqSongId,
          qqMediaMid: remote.qqMediaMid ?? matchedLocal.qqMediaMid,
          isVip: remote.isVip || matchedLocal.isVip,
        );
        mergedList.add(merged);

        if ((!matchedLocal.isFavorite ||
                matchedLocal.qqSongMid != merged.qqSongMid ||
                matchedLocal.qqSongId != merged.qqSongId) &&
            upgradedIds.add(merged.id)) {
          upgradedLocals.add(merged);
        }
      } else {
        mergedList.add(remote.copyWith(isFavorite: true));
      }
    }

    return (mergedList, upgradedLocals);
  }
}

final qqMusicFavoritesProvider =
    StateNotifierProvider<QQMusicFavoritesNotifier, QQMusicFavoritesState>((
      ref,
    ) {
      final storage = ref.watch(storageServiceProvider);
      final qqService = ref.watch(qqMusicServiceProvider);
      final libraryNotifier = ref.watch(libraryNotifierProvider.notifier);
      SoundCraftAudioHandler? handler;
      try {
        handler = ref.watch(audioHandlerProvider);
      } catch (_) {}

      final notifier = QQMusicFavoritesNotifier(
        storage,
        qqService,
        libraryNotifier,
        handler,
      );

      ref.listen<List<Song>>(
        libraryNotifierProvider.select((s) => s.songs),
        (prev, next) {
          notifier.onLocalLibraryUpdated(next);
        },
      );

      final songSub = handler?.currentSongStream.listen((song) {
        if (song != null) {
          notifier.refreshPlayCountFromStorage(song.id);
        }
      });
      final tickSub = handler?.statsTracker.liveTickStream.listen((_) {
        notifier.refreshCloudStatsSummary();
      });
      ref.onDispose(() {
        songSub?.cancel();
        tickSub?.cancel();
      });

      return notifier;
    });
