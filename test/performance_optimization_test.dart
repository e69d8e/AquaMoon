import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rxdart/rxdart.dart';

import 'package:aquamoon/core/audio/audio_player_handler.dart';
import 'package:aquamoon/core/theme/app_palette.dart';
import 'package:aquamoon/core/theme/app_theme.dart';
import 'package:aquamoon/core/utils/metadata_extractor.dart';
import 'package:aquamoon/core/utils/song_matcher.dart';
import 'package:aquamoon/models/lyrics_display_settings.dart';
import 'package:aquamoon/models/playback_mode.dart';
import 'package:aquamoon/models/playback_progress.dart';
import 'package:aquamoon/models/qq_music_config.dart';
import 'package:aquamoon/models/listening_stats.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/lyrics_provider.dart';
import 'package:aquamoon/providers/qq_music_provider.dart';
import 'package:aquamoon/services/listening_stats_tracker.dart';
import 'package:aquamoon/services/online_metadata_service.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:aquamoon/views/player/lyrics_view.dart';
import 'package:aquamoon/views/stats/widgets/listening_heatmap.dart';
import 'package:aquamoon/views/widgets/aquamoon_mark.dart';
import 'package:aquamoon/views/widgets/glass_container.dart';

class _InMemoryLyricsStorage extends StorageService {
  @override
  LyricsDisplaySettings getSavedLyricsDisplaySettings() =>
      LyricsDisplaySettings.defaults;
}

class _FakeAudioHandler implements SoundCraftAudioHandler {
  final Song song;
  final BehaviorSubject<PlaybackState> _state = BehaviorSubject.seeded(
    PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
    ),
  );

  _FakeAudioHandler(this.song);

  @override
  BehaviorSubject<PlaybackState> get playbackState => _state;

  @override
  Stream<Song?> get currentSongStream => BehaviorSubject<Song?>.seeded(song);

  @override
  Stream<PlaybackMode> get playbackModeStream =>
      BehaviorSubject.seeded(PlaybackMode.sequence);

  @override
  Stream<List<Song>> get playlistStream => BehaviorSubject.seeded([song]);

  @override
  Stream<PlaybackProgress> get progressStream => BehaviorSubject.seeded(
    const PlaybackProgress(
      position: Duration(seconds: 5),
      bufferedPosition: Duration(seconds: 30),
      duration: Duration(minutes: 3),
    ),
  );

  @override
  Stream<Duration?> get sleepTimerStream =>
      BehaviorSubject<Duration?>.seeded(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<int> _beUint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _mp4Box(String fourCc, List<int> body) {
  return [..._beUint32(8 + body.length), ...latin1.encode(fourCc), ...body];
}

List<int> _mp4TagAtom(int a, int b, int c, int d, String value) {
  final strBytes = utf8.encode(value);
  final dataBox = [
    ..._beUint32(16 + strBytes.length),
    ...latin1.encode('data'),
    0x00, 0x00, 0x00, 0x01, // UTF-8 type indicator
    0x00, 0x00, 0x00, 0x00,
    ...strBytes,
  ];
  return [..._beUint32(8 + dataBox.length), a, b, c, d, ...dataBox];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track B: SongMatcher 单遍归一化与匹配性能', () {
    test('全角标点、特殊符号 ×、多语言字符集与空白折叠完全兼容', () {
      expect(SongMatcher.foldPunctuation('  稻香·（Live）  '), '稻香 (live)');
      expect(SongMatcher.foldPunctuation('A《测试》　B'), 'a测试 b');
      expect(SongMatcher.compact('A×B （日本語·한국어）!'), 'axb日本語한국어');
      expect(SongMatcher.baseTitle('晴天 (Live) [伴奏]'), '晴天');
      expect(SongMatcher.baseTitle('七里香 - 2023 Remaster'), '七里香');
      expect(SongMatcher.titleKey('未知曲目'), isNull);
    });

    test('大批量跨源匹配在不触发 RegExp 热点开销下结果准确', () {
      final locals = [
        for (var i = 0; i < 300; i++)
          Song(
            id: 'loc-$i',
            title: i == 188 ? '青花瓷 (Live)' : '本地曲目 $i',
            artist: i == 188 ? '周杰伦、费玉清' : '歌手 $i',
            album: '专辑',
            durationMs: 240000,
            filePath: '/music/$i.flac',
            dateAdded: DateTime(2026, 1, 1),
          ),
      ];
      final remote = Song(
        id: 'qq-1',
        title: '青花瓷',
        artist: '周杰伦',
        album: '我很忙',
        durationMs: 239500,
        filePath: 'qqmusic://001',
        dateAdded: DateTime(2026, 1, 1),
        source: SongSource.online,
        qqSongMid: '001',
      );

      final match = SongMatcher.findLocalMatch(remote, locals);
      expect(match?.id, 'loc-188');
    });
  });

  group('Track B/C: 值相等性与 StorageService 压缩队列及索引', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('perf_storage_test_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('PlaybackProgress、QQMusicConfig 与 QQMusicFavoritesState 值语义生效', () {
      const p1 = PlaybackProgress(
        position: Duration(seconds: 12),
        duration: Duration(minutes: 3),
        bufferedPosition: Duration(seconds: 40),
      );
      const p2 = PlaybackProgress(
        position: Duration(seconds: 12),
        duration: Duration(minutes: 3),
        bufferedPosition: Duration(seconds: 40),
      );
      const p3 = PlaybackProgress(
        position: Duration(seconds: 13),
        duration: Duration(minutes: 3),
        bufferedPosition: Duration(seconds: 40),
      );
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));

      const c1 = QQMusicConfig(uin: '123', nickname: '禅音');
      const c2 = QQMusicConfig(uin: '123', nickname: '禅音');
      expect(c1, equals(c2));

      const s1 = QQMusicCloudStatsSummary(importedSongCount: 5, reportedPlayCount: 2);
      const s2 = QQMusicCloudStatsSummary(importedSongCount: 5, reportedPlayCount: 2);
      expect(s1, equals(s2));

      final songLocal = Song(
        id: '1',
        title: 'A',
        artist: 'X',
        album: 'Al',
        durationMs: 1000,
        filePath: '/a.flac',
        dateAdded: DateTime(2026, 1, 1),
      );
      final songOnline = Song(
        id: '2',
        title: 'B',
        artist: 'Y',
        album: 'Al',
        durationMs: 1000,
        filePath: 'qqmusic://mid2',
        dateAdded: DateTime(2026, 1, 1),
        source: SongSource.online,
        qqSongMid: 'mid2',
      );
      final st1 = QQMusicFavoritesState.computed(
        config: c1,
        mergedSongs: [songLocal, songOnline],
        cloudStatsSummary: s1,
      );
      final st2 = QQMusicFavoritesState.computed(
        config: c2,
        mergedSongs: [songLocal, songOnline],
        cloudStatsSummary: s2,
      );
      expect(st1.localMatchedCount, 1);
      expect(st1, equals(st2));
    });

    test('savePlaybackSession 使用 gzip+json 压缩且完整恢复，同时兼容旧版 List 与备份恢复', () async {
      final songs = [
        for (var i = 0; i < 10; i++)
          Song(
            id: 'q-$i',
            title: '水墨曲 $i',
            artist: '古琴',
            album: '山居吟',
            durationMs: 200000 + i,
            filePath: '/m/$i.flac',
            dateAdded: DateTime(2026, 1, 1),
            lrcContent: '[00:01.00]第$i句歌词',
          ),
      ];

      await storage.savePlaybackSession(songs, 4);

      final rawStored = Hive.box('soundcraft_settings').get('playback_queue');
      expect(rawStored, isA<Map>());
      expect((rawStored as Map)['codec'], 'gzip+json');

      final session = storage.getPlaybackSession();
      expect(session, isNotNull);
      expect(session!.index, 4);
      expect(session.songMaps, hasLength(10));
      final restored = Song.fromMap(session.songMaps[4]);
      expect(restored.id, 'q-4');
      expect(restored.lrcContent, '[00:01.00]第4句歌词');

      // 备份导出 -> JSON 往返 -> 恢复应保留压缩队列
      final encodedBackup = jsonEncode(storage.exportBackup());
      await storage.savePlaybackSession(const [], -1);
      expect(storage.getPlaybackSession(), isNull);
      await storage.restoreBackup(
        Map<String, dynamic>.from(jsonDecode(encodedBackup) as Map),
      );
      final afterRestore = storage.getPlaybackSession();
      expect(afterRestore?.songMaps.length, 10);
      expect(Song.fromMap(afterRestore!.songMaps[4]).lrcContent, '[00:01.00]第4句歌词');

      // 向后兼容历史未压缩 List<Map>
      await Hive.box('soundcraft_settings').put('playback_queue', [
        songs.first.toMap(),
      ]);
      await Hive.box('soundcraft_settings').put('playback_queue_index', 0);
      final legacySession = storage.getPlaybackSession();
      expect(legacySession?.songMaps.length, 1);
      expect(Song.fromMap(legacySession!.songMaps.first).id, 'q-0');
    });

    test('findSongIdByQQMid 索引缓存随增删同步失效并刷新', () async {
      final s1 = Song(
        id: 'local-mid-1',
        title: '曲一',
        artist: '歌手',
        album: '专辑',
        durationMs: 180000,
        filePath: '/m/1.mp3',
        dateAdded: DateTime(2026, 1, 1),
        qqSongMid: 'MID_ONE',
      );
      await storage.saveSong(s1);
      expect(storage.findSongIdByQQMid('MID_ONE'), 'local-mid-1');

      await storage.deleteSong('local-mid-1');
      expect(storage.findSongIdByQQMid('MID_ONE'), isNull);
    });

    test('ListeningStatsTracker 在无 1Hz 轮询下仍正确跟踪停止与销毁结算', () async {
      final song = Song(
        id: 'stat-1',
        title: '统计曲',
        artist: '乐师',
        album: '专',
        durationMs: 120000,
        filePath: '/m/s.flac',
        dateAdded: DateTime(2026, 1, 1),
      );
      final tracker = ListeningStatsTracker(storage);
      tracker.onPlay(song);
      tracker.recordSimulatedSeconds(15);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      tracker.onPause();
      tracker.onStop();
      tracker.dispose();

      final todayStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final rec = storage.getDailyListeningRecord(todayStr);
      expect(rec.songPlayCounts['stat-1'], 1);
      expect(rec.totalDurationSeconds, greaterThanOrEqualTo(15));
    });
  });

  group('Track C: MetadataExtractor 层次化 MP4 解析与零冗余封面内存滞留', () {
    test('层级式 _parseM4a 能跨越前置大型 mdat 定位并解析尾部 moov 元数据', () async {
      final tempDir = await Directory.systemTemp.createTemp('perf_m4a_test_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final ilst = _mp4Box('ilst', [
        ..._mp4TagAtom(0xA9, 0x6E, 0x61, 0x6D, '高山流水'), // ©nam
        ..._mp4TagAtom(0xA9, 0x41, 0x52, 0x54, '管平湖'), // ©ART
      ]);
      // Standard ISO BMFF FullBox header (4 zero bytes) before ilst
      final meta = _mp4Box('meta', [0x00, 0x00, 0x00, 0x00, ...ilst]);
      final udta = _mp4Box('udta', meta);
      final moov = _mp4Box('moov', udta);

      // Put > 100KB mdat BEFORE moov (beyond the 64KB initial probe window)
      final ftyp = _mp4Box('ftyp', latin1.encode('M4A \x00\x00\x00\x00M4A '));
      final mdat = _mp4Box('mdat', Uint8List(100 * 1024));

      final file = File('${tempDir.path}/late_moov.m4a');
      await file.writeAsBytes([...ftyp, ...mdat, ...moov]);

      final result = await MetadataExtractor.extractFromFileIsolated(
        file.path,
        '',
      );
      expect(result.title, '高山流水');
      expect(result.artist, '管平湖');
    });

    test('已写入封面磁盘缓存时自动清空 albumArtBytes；批处理共享目录缓存目录覆盖', () async {
      final tempDir = await Directory.systemTemp.createTemp('perf_id3_test_');
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final titleBytes = utf8.encode('幽兰');
      final jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x01, 0xFF, 0xD9];
      final tit2Frame = <int>[
        ...utf8.encode('TIT2'),
        0x00, 0x00, 0x00, titleBytes.length + 1,
        0x00, 0x00,
        0x03, // UTF-8 encoding
        ...titleBytes,
      ];
      final mime = utf8.encode('image/jpeg');
      final apicBody = <int>[0x00, ...mime, 0x00, 0x03, 0x00, ...jpegBytes];
      final apicFrame = <int>[
        ...utf8.encode('APIC'),
        0x00, 0x00, 0x00, apicBody.length,
        0x00, 0x00,
        ...apicBody,
      ];
      final tagSize = tit2Frame.length + apicFrame.length;
      final mp3Bytes = <int>[
        ...utf8.encode('ID3'),
        0x03, 0x00, 0x00,
        (tagSize >> 21) & 0x7F,
        (tagSize >> 14) & 0x7F,
        (tagSize >> 7) & 0x7F,
        tagSize & 0x7F,
        ...tit2Frame,
        ...apicFrame,
      ];

      final mp3File = File('${tempDir.path}/sample.mp3');
      await mp3File.writeAsBytes(mp3Bytes);

      final cachedBatch = await MetadataExtractor.extractChunkIsolated(
        [mp3File.path],
        cacheDir.path,
      );
      expect(cachedBatch, hasLength(1));
      expect(cachedBatch.single.title, '幽兰');
      expect(cachedBatch.single.albumArtUri, isNotNull);
      expect(cachedBatch.single.albumArtBytes, isNull);

      final memoryOnly = await MetadataExtractor.extractFromFileIsolated(
        mp3File.path,
        '',
      );
      expect(memoryOnly.albumArtBytes, jpegBytes);
    });
  });

  group('Track A: 渲染隔离、分级模糊与 GPU 合成回归验证', () {
    testWidgets('GlassContainer enableBlur: false 不渲染 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppPalette.inkwash.light),
          home: const Scaffold(
            body: Column(
              children: [
                GlassContainer(
                  enableBlur: true,
                  child: SizedBox(width: 40, height: 40),
                ),
                GlassContainer(
                  enableBlur: false,
                  child: SizedBox(width: 40, height: 40),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('PlayingWaveIndicator 使用 RepaintBoundary + Transform.scale 避免每帧重排', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppPalette.inkwash.light),
          home: const Scaffold(
            body: PlayingWaveIndicator(isPlaying: true, size: 18),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.descendant(
          of: find.byType(PlayingWaveIndicator),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PlayingWaveIndicator),
          matching: find.byType(Transform),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('LyricsView 采用渐变边缘替代全视口 ShaderMask saveLayer', (tester) async {
      final song = Song(
        id: 'ly-1',
        title: '渔舟唱晚',
        artist: '古筝',
        album: '古韵',
        durationMs: 180000,
        filePath: '/m/yzcw.flac',
        dateAdded: DateTime(2026, 1, 1),
        lrcContent: '[00:01.00]<00:01.00>夕<00:01.50>阳<00:02.00>映<00:02.50>江<00:03.00>面',
      );
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(_InMemoryLyricsStorage()),
          audioHandlerProvider.overrideWithValue(_FakeAudioHandler(song)),
          lyricsNotifierProvider.overrideWith(
            (ref) => LyricsNotifier(OnlineMetadataService(), ref),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme(AppPalette.inkwash.light),
            home: Scaffold(body: LyricsView(song: song)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('ListeningHeatmap 移除 365+ 枚 eager Tooltip，并支持点选日期提示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppPalette.inkwash.light),
          home: const Scaffold(
            body: ListeningHeatmap(
              year: 2026,
              dailySeconds: {'2026-01-01': 1800},
            ),
          ),
        ),
      );

      expect(find.byType(Tooltip), findsNothing);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(find.text('1月1日 · 30 分钟'), findsOneWidget);
    });
  });
}
