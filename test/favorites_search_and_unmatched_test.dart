import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aquamoon/models/listening_stats.dart';
import 'package:aquamoon/models/lyrics_display_settings.dart';
import 'package:aquamoon/models/playback_mode.dart';
import 'package:aquamoon/models/playlist.dart';
import 'package:aquamoon/models/qq_music_config.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart'
    show storageServiceProvider;
import 'package:aquamoon/providers/library_provider.dart';
import 'package:aquamoon/providers/playlist_provider.dart';
import 'package:aquamoon/providers/qq_music_provider.dart';
import 'package:aquamoon/services/qq_music_service.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:aquamoon/views/favorites/unmatched_songs_page.dart';
import 'package:aquamoon/views/home/home_page.dart';
import 'package:aquamoon/views/home/tabs/favorites_tab.dart';
import 'package:aquamoon/views/playlists/playlist_detail_page.dart';
import 'package:aquamoon/views/playlists/select_playlist_cover_dialog.dart';
import 'package:aquamoon/views/widgets/local_song_link_dialog.dart';

/// In-memory stand-in so widget tests never deadlock Hive locks inside FakeAsync.
class _InMemoryStorage extends StorageService {
  final Map<String, Song> _songs = {};
  final List<Playlist> _playlists = [];
  final List<String> _history = [];
  QQMusicConfig _qqConfig = const QQMusicConfig();
  List<Song> _qqCache = [];
  final Map<String, String> _manualLinks = {};
  final Set<String> _manualExclusions = {};

  void seed({
    List<Song> localSongs = const [],
    QQMusicConfig? qqConfig,
    List<Song> qqFavoritesCache = const [],
    List<Playlist> playlists = const [],
  }) {
    _playlists
      ..clear()
      ..addAll(playlists);
    for (final s in localSongs) {
      _songs[s.id] = s;
    }
    if (qqConfig != null) {
      _qqConfig = qqConfig;
    }
    if (qqFavoritesCache.isNotEmpty) {
      _qqCache = List.of(qqFavoritesCache);
    }
  }

  @override
  List<Song> getAllSongs() => _songs.values.toList();

  @override
  Song? getSong(String songId) => _songs[songId];

  @override
  Future<void> saveSong(Song song) async {
    _songs[song.id] = song;
  }

  @override
  Future<void> saveSongs(List<Song> songs) async {
    for (final s in songs) {
      _songs[s.id] = s;
    }
  }

  @override
  Future<Song?> toggleFavorite(String songId) async {
    final existing = _songs[songId];
    if (existing == null) return null;
    final updated = existing.copyWith(isFavorite: !existing.isFavorite);
    _songs[songId] = updated;
    return updated;
  }

  @override
  List<Playlist> getAllPlaylists() => List.unmodifiable(_playlists);

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    final index = _playlists.indexWhere((p) => p.id == playlist.id);
    if (index >= 0) {
      _playlists[index] = playlist;
    } else {
      _playlists.add(playlist);
    }
  }

  @override
  List<String> getHistoryIds() => List.unmodifiable(_history);

  @override
  ThemeMode getSavedThemeMode() => ThemeMode.light;

  @override
  String? getSavedThemeId() => null;

  @override
  LyricsDisplaySettings getSavedLyricsDisplaySettings() =>
      LyricsDisplaySettings.defaults;

  @override
  PlaybackMode getSavedPlaybackMode() => PlaybackMode.sequence;

  @override
  QQMusicConfig getQQMusicConfig() => _qqConfig;

  @override
  String getQQMusicDesktopGuid() => 'TESTGUID000000000000000000000000';

  @override
  Future<void> saveQQMusicConfig(QQMusicConfig config) async {
    _qqConfig = config;
  }

  @override
  Map<String, String> getQQMusicManualLinks() => Map.unmodifiable(_manualLinks);

  @override
  Future<void> saveQQMusicManualLink({
    required String songMid,
    required String songId,
  }) async {
    if (songMid.isEmpty || songId.isEmpty) return;
    _manualLinks[songMid] = songId;
    _manualExclusions.remove(songMid);
  }

  @override
  Future<void> removeQQMusicManualLink(String songMid) async {
    _manualLinks.remove(songMid);
  }

  @override
  Set<String> getQQMusicManualExclusions() =>
      Set.unmodifiable(_manualExclusions);

  @override
  Future<void> addQQMusicManualExclusion(String songMid) async {
    if (songMid.isNotEmpty) _manualExclusions.add(songMid);
  }

  @override
  Future<void> removeQQMusicManualExclusion(String songMid) async {
    _manualExclusions.remove(songMid);
  }

  @override
  List<Song> getQQMusicFavoritesCache() => List.unmodifiable(_qqCache);

  @override
  Future<void> saveQQMusicFavoritesCache(List<Song> songs) async {
    _qqCache = List.of(songs);
  }

  @override
  QQMusicCloudStatsSummary getQQMusicCloudStatsSummary() =>
      const QQMusicCloudStatsSummary();

  @override
  bool getAutoCheckUpdates() => false;

  @override
  bool getPreferLocalPlayback() => false;

  @override
  Future<void> savePreferLocalPlayback(bool enabled) async {}

  @override
  DateTime? getLastUpdateCheckTime() => null;
}

Song _localSong({
  required String id,
  required String title,
  required String artist,
  String album = '专辑',
  bool isFavorite = false,
  int durationMs = 220000,
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  filePath: '/music/$id.flac',
  dateAdded: DateTime(2026, 1, 1),
  isFavorite: isFavorite,
  source: SongSource.local,
);

Song _qqOnlineSong({
  required String mid,
  required String title,
  required String artist,
  String album = '云端专辑',
  int durationMs = 220000,
  String? albumArtUri,
}) => Song(
  id: 'qq_$mid',
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  filePath: 'qqmusic://$mid',
  dateAdded: DateTime(2026, 1, 1),
  isFavorite: true,
  source: SongSource.online,
  qqSongMid: mid,
  qqSongId: mid.hashCode,
  qqMediaMid: mid,
  albumArtUri: albumArtUri,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemoryStorage storageService;

  setUp(() {
    storageService = _InMemoryStorage();
  });

  ProviderContainer createContainer({bool autoSync = false}) {
    final mockService = QQMusicService(
      client: MockClient((_) async => http.Response(json.encode({}), 200)),
    );
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        qqMusicServiceProvider.overrideWithValue(mockService),
        qqMusicFavoritesProvider.overrideWith((ref) {
          final libraryNotifier = ref.watch(libraryNotifierProvider.notifier);
          return QQMusicFavoritesNotifier(
            storageService,
            mockService,
            libraryNotifier,
            null,
            autoSync,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void seedStorage({
    List<Song> localSongs = const [],
    QQMusicConfig? qqConfig,
    List<Song> qqFavoritesCache = const [],
    List<Playlist> playlists = const [],
  }) {
    storageService.seed(
      localSongs: localSongs,
      qqConfig: qqConfig,
      qqFavoritesCache: qqFavoritesCache,
      playlists: playlists,
    );
  }

  group('收藏页搜索框', () {
    testWidgets('无收藏歌曲时不显示搜索框', (tester) async {
      final container = createContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FavoritesTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('接入 QQ 音乐「我喜欢」'), findsOneWidget);
    });

    testWidgets('支持按歌名/歌手/专辑过滤收藏歌曲，并可通过 × 与「清空搜索」恢复', (tester) async {
      final fav1 = _localSong(
        id: 'f1',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        isFavorite: true,
      );
      final fav2 = _localSong(
        id: 'f2',
        title: '江南',
        artist: '林俊杰',
        album: '第二天堂',
        isFavorite: true,
      );
      seedStorage(localSongs: [fav1, fav2]);
      final container = createContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FavoritesTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('江南'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // 按专辑关键词搜索
      await tester.enterText(find.byType(TextField), '叶惠美');
      await tester.pump(const Duration(milliseconds: 350));

      expect(container.read(favoritesSearchQueryProvider), '叶惠美');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('江南'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);

      // 搜索无结果时显示空状态与「清空搜索」
      await tester.enterText(find.byType(TextField), '完全不存在的歌');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('收藏中未找到「完全不存在的歌」相关歌曲'), findsOneWidget);
      expect(find.text('0/2'), findsOneWidget);

      await tester.tap(find.text('清空搜索'));
      await tester.pump();

      expect(container.read(favoritesSearchQueryProvider), '');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('江南'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('State 重建（如切换布局）后保留收藏搜索词', (tester) async {
      final fav1 = _localSong(
        id: 'f1',
        title: '晴天',
        artist: '周杰伦',
        isFavorite: true,
      );
      final fav2 = _localSong(
        id: 'f2',
        title: '江南',
        artist: '林俊杰',
        isFavorite: true,
      );
      seedStorage(localSongs: [fav1, fav2]);
      final container = createContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FavoritesTab())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('江南'), findsNothing);

      // 重建 Tab State
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FavoritesTab())),
        ),
      );
      await tester.pumpAndSettle();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller;
      expect(controller?.text, '晴');
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
      expect(find.text('江南'), findsNothing);
    });
  });

  group('本地未匹配歌曲页', () {
    testWidgets('未绑定 QQ 音乐时引导连接', (tester) async {
      final container = createContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: UnmatchedSongsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('本地未匹配歌曲'), findsOneWidget);
      expect(find.text('尚未接入 QQ 音乐收藏'), findsOneWidget);
      expect(find.text('连接 QQ 音乐收藏'), findsOneWidget);
    });

    testWidgets('所有 QQ 收藏均已匹配本地音频时展示完成态', (tester) async {
      final localMatched = _localSong(id: 'l1', title: '稻香', artist: '周杰伦');
      final remoteMatched = _qqOnlineSong(
        mid: '001daoxiang',
        title: '稻香',
        artist: '周杰伦',
      );
      seedStorage(
        localSongs: [localMatched],
        qqConfig: const QQMusicConfig(uin: '123456'),
        qqFavoritesCache: [remoteMatched],
      );
      final container = createContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: UnmatchedSongsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(unmatchedFavoritesProvider), isEmpty);
      expect(find.text('全部收藏均已匹配本地音频'), findsOneWidget);
    });

    testWidgets('仅展示未匹配本地音频的 QQ 收藏，支持搜索与一键手动关联本地音频', (tester) async {
      final localMatched = _localSong(id: 'l1', title: '稻香', artist: '周杰伦');
      final localRenamed = _localSong(
        id: 'l2',
        title: 'MysteryTrack_09',
        artist: '未知歌手',
      );
      final remoteMatched = _qqOnlineSong(
        mid: '001daoxiang',
        title: '稻香',
        artist: '周杰伦',
      );
      final remoteUnmatched1 = _qqOnlineSong(
        mid: '002qingtian',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
      );
      final remoteUnmatched2 = _qqOnlineSong(
        mid: '003jiangnan',
        title: '江南',
        artist: '林俊杰',
        album: '第二天堂',
      );

      seedStorage(
        localSongs: [localMatched, localRenamed],
        qqConfig: const QQMusicConfig(uin: '123456'),
        qqFavoritesCache: [remoteMatched, remoteUnmatched1, remoteUnmatched2],
      );
      final container = createContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: UnmatchedSongsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(unmatchedFavoritesProvider).map((s) => s.qqSongMid),
        ['002qingtian', '003jiangnan'],
      );
      expect(find.text('共 2 首未匹配'), findsOneWidget);
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('江南'), findsOneWidget);
      expect(find.text('稻香'), findsNothing);

      // 搜索过滤
      await tester.enterText(find.byType(TextField), '林俊杰');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('未匹配 1/2 首'), findsOneWidget);
      expect(find.text('江南'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);

      // 清空搜索
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('江南'), findsOneWidget);

      // 点击第一条目的快捷关联按钮，弹出 LocalSongLinkDialog 并关联本地文件
      await tester.tap(find.byTooltip('关联本地音频').first);
      await tester.pumpAndSettle();
      expect(find.byType(LocalSongLinkDialog), findsOneWidget);

      await tester.tap(find.text('MysteryTrack_09'));
      await tester.pumpAndSettle();

      // 关联成功后立即从未匹配列表中移除，计数更新为 1
      expect(
        container.read(unmatchedFavoritesProvider).map((s) => s.qqSongMid),
        ['003jiangnan'],
      );
      expect(find.text('共 1 首未匹配'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);
      expect(find.text('江南'), findsOneWidget);
    });
  });

  group('首页右上角更多菜单与桌面顶栏入口', () {
    testWidgets('移动端：右上角「三个点」更多菜单包含「本地未匹配歌曲」且可跳转', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final remoteUnmatched = _qqOnlineSong(
        mid: '002qingtian',
        title: '晴天',
        artist: '周杰伦',
      );
      seedStorage(
        qqConfig: const QQMusicConfig(uin: '123456'),
        qqFavoritesCache: [remoteUnmatched],
      );
      final container = createContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.byTooltip('更多功能'));
      await tester.pumpAndSettle();

      expect(find.text('本地未匹配歌曲'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.text('本地未匹配歌曲'));
      await tester.pumpAndSettle();

      expect(find.byType(UnmatchedSongsPage), findsOneWidget);
      expect(find.text('共 1 首未匹配'), findsOneWidget);
    });

    testWidgets('桌面端：顶栏包含「本地未匹配歌曲」入口按钮且可跳转', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = createContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pump(const Duration(seconds: 4));

      final button = find.byTooltip('本地未匹配歌曲');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(UnmatchedSongsPage), findsOneWidget);
    });
  });

  group('歌单中的收藏歌曲', () {
    testWidgets('歌单详情可从收藏缓存解析 QQ 音乐歌曲', (tester) async {
      final cloud = _qqOnlineSong(
        mid: '003test',
        title: '茶花开了',
        artist: '王睿卓',
        album: '茶花开了',
      );
      seedStorage(
        qqConfig: const QQMusicConfig(uin: '123456'),
        qqFavoritesCache: [cloud],
      );
      final container = createContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PlaylistDetailPage(
              playlist: Playlist(
                id: 'p1',
                name: '测试歌单',
                songIds: [cloud.id],
                createdAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('茶花开了'), findsOneWidget);
      expect(find.text('QQ音乐'), findsOneWidget);
      expect(find.text('共 1 首歌曲'), findsOneWidget);
    });
  });

  group('歌单封面选择', () {
    testWidgets('歌单内歌曲 tab 包含 QQ 音乐云端收藏', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cloud = _qqOnlineSong(
        mid: '003cover',
        title: '茶花开了',
        artist: '王睿卓',
        albumArtUri: 'https://example.com/cover.jpg',
      );
      final playlist = Playlist(
        id: 'p-cover',
        name: '封面测试',
        songIds: [cloud.id],
        createdAt: DateTime(2026, 1, 1),
      );
      seedStorage(
        qqConfig: const QQMusicConfig(uin: '123456'),
        qqFavoritesCache: [cloud],
        playlists: [playlist],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: createContainer(),
          child: MaterialApp(
            home: Scaffold(body: SelectPlaylistCoverDialog(playlist: playlist)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('歌单内歌曲 (1)'), findsOneWidget);
      expect(find.text('茶花开了'), findsOneWidget);
    });
  });
}
