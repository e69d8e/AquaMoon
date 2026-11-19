import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'package:aquamoon/core/audio/audio_player_handler.dart';
import 'package:aquamoon/core/theme/app_palette.dart';
import 'package:aquamoon/core/theme/app_theme.dart';
import 'package:aquamoon/core/utils/app_toast.dart';
import 'package:aquamoon/models/lyrics_display_settings.dart';
import 'package:aquamoon/models/playback_mode.dart';
import 'package:aquamoon/models/playback_progress.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/lyrics_provider.dart';
import 'package:aquamoon/providers/lyrics_settings_provider.dart';
import 'package:aquamoon/services/online_metadata_service.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:aquamoon/views/player/full_player_page.dart';
import 'package:aquamoon/views/player/lyrics_view.dart';
import 'package:aquamoon/views/player/mini_player.dart';
import 'package:aquamoon/views/settings/theme_settings_page.dart';
import 'package:aquamoon/views/widgets/aquamoon_mark.dart';
import 'package:aquamoon/views/widgets/empty_state_view.dart';

class _InMemoryStorage extends StorageService {
  String _paletteId = AppPalette.defaultId;

  @override
  String? getSavedThemeId() => _paletteId;

  @override
  Future<void> saveThemeId(String id) async {
    _paletteId = id;
  }

  @override
  ThemeMode getSavedThemeMode() => ThemeMode.light;

  @override
  LyricsDisplaySettings getSavedLyricsDisplaySettings() =>
      LyricsDisplaySettings.defaults;
}

class _FakeHandler implements SoundCraftAudioHandler {
  final Song song;
  final BehaviorSubject<PlaybackState> _state;

  _FakeHandler(this.song, {bool playing = true})
    : _state = BehaviorSubject.seeded(
        PlaybackState(
          playing: playing,
          processingState: AudioProcessingState.ready,
        ),
      );

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
      position: Duration(seconds: 40),
      bufferedPosition: Duration(seconds: 95),
      duration: Duration(minutes: 3, seconds: 59),
    ),
  );

  @override
  Stream<Duration?> get sleepTimerStream =>
      BehaviorSubject<Duration?>.seeded(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SpyAudioController extends AudioPlayerController {
  int nextCount = 0;
  int previousCount = 0;

  _SpyAudioController(super.handler);

  @override
  Future<void> next() async => nextCount++;

  @override
  Future<void> previous() async => previousCount++;
}

void main() {
  final sampleSong = Song(
    id: 'ui-s1',
    title: '青花瓷',
    artist: '周杰伦',
    album: '我很忙',
    durationMs: 239000,
    filePath: '/music/qhc.flac',
    dateAdded: DateTime(2026, 3, 1),
    isFavorite: true,
    lrcContent: '[00:00.00]素胚勾勒出青花笔锋浓转淡\n[00:05.00]瓶身描绘的牡丹一如你初妆',
  );

  group('UI/UX 设计系统与核心交互回归', () {
    testWidgets('AppToast 遵循当前主题的 snackBarBackground（不再硬编码绿色）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppPalette.inkwash.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AppToast.show(context, '朱砂提示'),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, AppPalette.inkwash.light.snackBarBackground);
      expect(find.text('朱砂提示'), findsOneWidget);
    });

    testWidgets('AquaMoonMark、PlayingWaveIndicator 与 EmptyStateView 正常渲染', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(AppPalette.inkwash.dark),
          home: const Scaffold(
            body: Column(
              children: [
                AquaMoonMark(size: 28),
                PlayingWaveIndicator(isPlaying: true, size: 16),
                PlayingWaveIndicator(isPlaying: false, size: 16),
                Expanded(
                  child: EmptyStateView(
                    icon: Icons.music_note_rounded,
                    title: '空态标题',
                    subtitle: '空态说明文案',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AquaMoonMark), findsOneWidget);
      expect(find.byType(PlayingWaveIndicator), findsNWidgets(2));
      expect(find.text('空态标题'), findsOneWidget);
      expect(find.text('空态说明文案'), findsOneWidget);
    });

    testWidgets('FullPlayerPage 移动端显示「封面 / 歌词」切换胶囊，桌面宽屏自动展开双栏歌词', (
      tester,
    ) async {
      final storage = _InMemoryStorage();
      final handler = _FakeHandler(sampleSong);

      ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          audioHandlerProvider.overrideWithValue(handler),
          lyricsNotifierProvider.overrideWith(
            (ref) => LyricsNotifier(OnlineMetadataService(), ref),
          ),
          lyricsDisplaySettingsProvider.overrideWith(
            (ref) => LyricsDisplaySettingsNotifier(storage),
          ),
        ],
      );

      // 1. 移动端布局 (< 720px)
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mobileContainer = makeContainer();
      addTearDown(mobileContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: mobileContainer,
          child: MaterialApp(
            theme: AppTheme.lightTheme(AppPalette.inkwash.light),
            home: const FullPlayerPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('封面'), findsOneWidget);
      expect(find.text('歌词'), findsOneWidget);
      expect(find.text('青花瓷'), findsOneWidget);

      // 点击「歌词」胶囊平滑切至歌词页
      await tester.tap(find.text('歌词'));
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);

      // 2. 桌面宽屏布局 (>= 720px)：同时显示封面与 LyricsView，不显示双页胶囊
      tester.view.physicalSize = const Size(1100, 720);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final desktopContainer = makeContainer();
      addTearDown(desktopContainer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: desktopContainer,
          child: MaterialApp(
            theme: AppTheme.darkTheme(AppPalette.inkwash.dark),
            home: const FullPlayerPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LyricsView), findsOneWidget);
      expect(find.text('青花瓷'), findsOneWidget);
      expect(find.text('封面'), findsNothing);
    });

    testWidgets('MiniPlayer 支持左右轻扫切歌', (tester) async {
      final handler = _FakeHandler(sampleSong, playing: false);
      final spy = _SpyAudioController(handler);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(handler),
            audioControllerProvider.overrideWithValue(spy),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(AppPalette.inkwash.light),
            home: const Scaffold(body: Align(child: MiniPlayer())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 左滑切下一首
      await tester.fling(find.byType(MiniPlayer), const Offset(-180, 0), 900);
      await tester.pumpAndSettle();
      expect(spy.nextCount, 1);

      // 右滑切上一首
      await tester.fling(find.byType(MiniPlayer), const Offset(180, 0), 900);
      await tester.pumpAndSettle();
      expect(spy.previousCount, 1);
    });

    testWidgets('ThemeSettingsPage 展示全部 6 套配色并支持点选切换', (tester) async {
      final storage = _InMemoryStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: MaterialApp(
            theme: AppTheme.lightTheme(AppPalette.inkwash.light),
            home: const ThemeSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('水墨丹青'), findsOneWidget);
      expect(find.text('青花瓷'), findsOneWidget);
      await tester.tap(find.text('青花瓷'));
      await tester.pumpAndSettle();
      expect(storage.getSavedThemeId(), 'porcelain');
    });
  });
}
