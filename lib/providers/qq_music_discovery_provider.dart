import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/qq_music_config.dart';
import '../models/qq_music_discovery.dart';
import '../models/song.dart';
import '../services/qq_music_discovery_service.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';

/// 发现页的四个栏目：单曲搜索、歌单、专辑、排行榜。
enum QQMusicDiscoveryTab {
  songs('单曲'),
  playlists('歌单'),
  albums('专辑'),
  charts('榜单');

  const QQMusicDiscoveryTab(this.label);

  final String label;

  bool get isSongs => this == QQMusicDiscoveryTab.songs;
}

class QQMusicDiscoveryState {
  final QQMusicDiscoveryTab tab;
  final String query;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final List<Song> songs;
  final List<QQMusicCollection> collections;
  final int page;
  final bool hasMore;

  /// 当前打开的歌单 / 专辑 / 榜单详情。
  final QQMusicCollection? openedCollection;
  final bool isDetailLoading;
  final String? detailError;
  final QQMusicCollectionDetail? detail;

  final QQMusicStreamQuality quality;

  /// 官方歌单分类（仅「歌单」栏目使用）。
  final List<QQMusicCategory> categories;
  final String? selectedCategoryId;

  const QQMusicDiscoveryState({
    this.tab = QQMusicDiscoveryTab.songs,
    this.query = '',
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.songs = const [],
    this.collections = const [],
    this.page = 1,
    this.hasMore = false,
    this.openedCollection,
    this.isDetailLoading = false,
    this.detailError,
    this.detail,
    this.quality = QQMusicStreamQuality.high,
    this.categories = const [],
    this.selectedCategoryId,
  });

  QQMusicDiscoveryState copyWith({
    QQMusicDiscoveryTab? tab,
    String? query,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    List<Song>? songs,
    List<QQMusicCollection>? collections,
    int? page,
    bool? hasMore,
    QQMusicCollection? openedCollection,
    bool clearOpenedCollection = false,
    bool? isDetailLoading,
    String? detailError,
    bool clearDetailError = false,
    QQMusicCollectionDetail? detail,
    bool clearDetail = false,
    QQMusicStreamQuality? quality,
    List<QQMusicCategory>? categories,
    String? selectedCategoryId,
    bool clearSelectedCategory = false,
  }) {
    return QQMusicDiscoveryState(
      tab: tab ?? this.tab,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      songs: songs ?? this.songs,
      collections: collections ?? this.collections,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      openedCollection: clearOpenedCollection
          ? null
          : (openedCollection ?? this.openedCollection),
      isDetailLoading: isDetailLoading ?? this.isDetailLoading,
      detailError: clearDetailError
          ? null
          : (detailError ?? this.detailError),
      detail: clearDetail ? null : (detail ?? this.detail),
      quality: quality ?? this.quality,
      categories: categories ?? this.categories,
      selectedCategoryId: clearSelectedCategory
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
    );
  }
}

final qqMusicDiscoveryServiceProvider = Provider<QQMusicDiscoveryService>((ref) {
  final service = QQMusicDiscoveryService();
  ref.onDispose(service.dispose);
  return service;
});

/// QQ 音乐发现页状态机。
///
/// 只负责取数与界面状态；播放动作由视图经 [audioControllerProvider] 发起，
/// 详情返回的 [Song] 已带 `qqSongMid`，音频引擎会复用既有 vkey 取流链路。
class QQMusicDiscoveryNotifier extends StateNotifier<QQMusicDiscoveryState> {
  QQMusicDiscoveryNotifier({
    required this._storage,
    required this._service,
  }) : super(
          QQMusicDiscoveryState(
            quality: _storage.getQQMusicStreamQuality(),
          ),
        );

  final StorageService _storage;
  final QQMusicDiscoveryService _service;

  QQMusicConfig get _config => _storage.getQQMusicConfig();

  int _requestGeneration = 0;

  /// 切换栏目：保留各栏目的独立结果缓存意义不大，切回时重新拉默认内容。
  Future<void> setTab(QQMusicDiscoveryTab tab) async {
    if (state.tab == tab && state.openedCollection == null) return;
    _requestGeneration++;
    state = state.copyWith(
      tab: tab,
      isLoading: false,
      isLoadingMore: false,
      clearError: true,
      songs: const [],
      collections: const [],
      page: 1,
      hasMore: false,
      clearOpenedCollection: true,
      isDetailLoading: false,
      clearDetailError: true,
      clearDetail: true,
      query: '',
      clearSelectedCategory: true,
    );
    if (!tab.isSongs && tab != QQMusicDiscoveryTab.albums) {
      await _loadInitialCollections();
    }
  }

  /// 搜索框提交。若输入看起来是分享链接，先解析成歌单 / 专辑详情。
  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final parsed = QQMusicDiscoveryService.parseShareInput(query);
    if (parsed != null) {
      await openCollection(parsed);
      return;
    }

    final generation = ++_requestGeneration;
    state = state.copyWith(
      query: query,
      isLoading: true,
      clearError: true,
      songs: const [],
      collections: const [],
      page: 1,
      hasMore: false,
      clearOpenedCollection: true,
      clearDetail: true,
      clearDetailError: true,
      clearSelectedCategory: true,
    );

    try {
      if (state.tab.isSongs) {
        final songs = await _service.searchSongs(
          query,
          page: 1,
          config: _config,
        );
        if (generation != _requestGeneration) return;
        state = state.copyWith(
          isLoading: false,
          songs: songs,
          hasMore: songs.length >= QQMusicDiscoveryService.pageSize,
        );
      } else {
        final collections = await _searchCollections(query);
        if (generation != _requestGeneration) return;
        state = state.copyWith(
          isLoading: false,
          collections: collections,
          hasMore: false,
        );
      }
    } on QQMusicDiscoveryException catch (error) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (_) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(
        isLoading: false,
        error: '网络异常，请稍后重试',
      );
    }
  }

  Future<List<QQMusicCollection>> _searchCollections(String query) {
    switch (state.tab) {
      case QQMusicDiscoveryTab.playlists:
        return _service.searchPlaylists(query, page: 1, config: _config);
      case QQMusicDiscoveryTab.albums:
        return _service.searchAlbums(query, page: 1, config: _config);
      case QQMusicDiscoveryTab.charts:
        return _service.fetchCharts(config: _config);
      case QQMusicDiscoveryTab.songs:
        return Future.value(const <QQMusicCollection>[]);
    }
  }

  /// 单曲搜索结果触底翻页。
  Future<void> loadMore() async {
    if (state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore ||
        state.query.isEmpty ||
        !state.tab.isSongs) {
      return;
    }
    final generation = _requestGeneration;
    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true);
    try {
      final songs = await _service.searchSongs(
        state.query,
        page: nextPage,
        config: _config,
      );
      if (generation != _requestGeneration) return;
      final merged = <Song>[...state.songs, ...songs];
      state = state.copyWith(
        isLoadingMore: false,
        songs: merged,
        page: nextPage,
        hasMore: songs.length >= QQMusicDiscoveryService.pageSize,
      );
    } catch (_) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }

  Future<void> _loadInitialCollections() async {
    final generation = ++_requestGeneration;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final collections = state.tab == QQMusicDiscoveryTab.charts
          ? await _service.fetchCharts(config: _config)
          : await _service.fetchRecommendedPlaylists(config: _config);
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, collections: collections);
      if (state.tab == QQMusicDiscoveryTab.playlists) {
        await loadCategories(generation);
      }
    } on QQMusicDiscoveryException catch (error) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (_) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(
        isLoading: false,
        error: '获取 QQ 音乐推荐失败，请检查网络',
      );
    }
  }

  /// 拉取官方歌单分类，失败时静默降级（分类是可选增强）。
  Future<void> loadCategories([int? generation]) async {
    final token = generation ?? _requestGeneration;
    try {
      final categories = await _service.fetchPlaylistCategories(config: _config);
      if (token != _requestGeneration) return;
      state = state.copyWith(categories: categories);
    } catch (_) {
      // 分类不可用不影响主流程。
    }
  }

  /// 选择官方分类；传 null 回到推荐歌单。
  Future<void> selectCategory(String? categoryId) async {
    final generation = ++_requestGeneration;
    state = state.copyWith(
      tab: QQMusicDiscoveryTab.playlists,
      selectedCategoryId: categoryId,
      clearSelectedCategory: categoryId == null,
      clearOpenedCollection: true,
      clearDetail: true,
      clearDetailError: true,
      isLoading: true,
      clearError: true,
      query: '',
      songs: const [],
      collections: const [],
    );
    try {
      final collections = categoryId == null || categoryId.isEmpty
          ? await _service.fetchRecommendedPlaylists(config: _config)
          : await _service.fetchCategoryPlaylists(categoryId, config: _config);
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, collections: collections);
    } on QQMusicDiscoveryException catch (error) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (_) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, error: '获取分类歌单失败');
    }
  }

  /// 单曲分享链接解析：返回可直接播放的在线 Song，非链接返回 null。
  Future<Song?> resolveSongLink(String rawInput) async {
    final mid = QQMusicDiscoveryService.parseSongMid(rawInput);
    if (mid == null) return null;
    return _service.fetchSongByMid(mid, config: _config);
  }

  /// 打开歌单 / 专辑 / 榜单详情。
  Future<void> openCollection(QQMusicCollection collection) async {
    final generation = ++_requestGeneration;
    state = state.copyWith(
      openedCollection: collection,
      isDetailLoading: true,
      clearDetailError: true,
      clearDetail: true,
      isLoading: false,
    );
    try {
      final detail = await _service.fetchCollectionDetail(
        collection,
        config: _config,
      );
      if (generation != _requestGeneration) return;
      state = state.copyWith(
        isDetailLoading: false,
        detail: detail,
        detailError: detail == null ? '未能获取该合集曲目' : null,
      );
    } on QQMusicDiscoveryException catch (error) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(
        isDetailLoading: false,
        detailError: error.message,
      );
    } catch (_) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(
        isDetailLoading: false,
        detailError: '网络异常，请稍后重试',
      );
    }
  }

  void closeDetail() {
    state = state.copyWith(
      clearOpenedCollection: true,
      clearDetail: true,
      clearDetailError: true,
      isDetailLoading: false,
    );
  }

  Future<void> setQuality(QQMusicStreamQuality quality) async {
    state = state.copyWith(quality: quality);
    await _storage.saveQQMusicStreamQuality(quality);
  }

  Future<void> refresh() async {
    if (state.openedCollection != null) {
      await openCollection(state.openedCollection!);
      return;
    }
    if (state.tab.isSongs) {
      if (state.query.isEmpty) return;
      await search(state.query);
    } else {
      if (state.query.isNotEmpty) {
        await search(state.query);
      } else if (state.selectedCategoryId != null) {
        await selectCategory(state.selectedCategoryId);
      } else {
        await _loadInitialCollections();
      }
    }
  }
}

final qqMusicDiscoveryProvider =
    StateNotifierProvider<QQMusicDiscoveryNotifier, QQMusicDiscoveryState>(
  (ref) => QQMusicDiscoveryNotifier(
    storage: ref.watch(storageServiceProvider),
    service: ref.watch(qqMusicDiscoveryServiceProvider),
  ),
);
