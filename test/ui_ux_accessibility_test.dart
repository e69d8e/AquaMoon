import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:aquamoon/core/theme/app_palette.dart';
import 'package:aquamoon/core/theme/app_theme.dart';
import 'package:aquamoon/core/utils/app_toast.dart';
import 'package:aquamoon/models/playlist.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:aquamoon/views/home/tabs/all_songs_tab.dart';
import 'package:aquamoon/views/home/tabs/playlists_tab.dart';
import 'package:aquamoon/views/playlists/playlist_detail_page.dart';
import 'package:aquamoon/views/settings/lyrics_display_settings_page.dart';
import 'package:aquamoon/views/widgets/song_tile.dart';
import 'package:aquamoon/views/widgets/ui_helpers.dart';

double _relativeLuminance(Color c) {
  double linearize(double channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linearize(c.r);
  final g = linearize(c.g);
  final b = linearize(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

Color _compositeOver(Color foreground, Color background) {
  final a = foreground.a;
  final r = foreground.r * a + background.r * (1 - a);
  final g = foreground.g * a + background.g * (1 - a);
  final b = foreground.b * a + background.b * (1 - a);
  return Color.from(alpha: 1.0, red: r, green: g, blue: b);
}

List<Override> _baseOverrides(StorageService storage) => [
  storageServiceProvider.overrideWithValue(storage),
  currentSongProvider.overrideWith((ref) => const Stream.empty()),
  playbackStateStreamProvider.overrideWith((ref) => const Stream.empty()),
  playbackProgressStreamProvider.overrideWith((ref) => const Stream.empty()),
  playbackModeStreamProvider.overrideWith((ref) => const Stream.empty()),
  playlistQueueStreamProvider.overrideWith((ref) => const Stream.empty()),
  sleepTimerStreamProvider.overrideWith((ref) => const Stream.empty()),
];

Widget _wrapApp({
  required Widget child,
  Size size = const Size(390, 844),
  double textScale = 1.0,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme(AppPalette.inkwash.light),
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: appChild!,
    ),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Palette WCAG contrast invariants', () {
    test('all 6 palettes light & dark modes satisfy WCAG AA thresholds', () {
      for (final palette in AppPalette.all) {
        for (final entry in [('light', palette.light), ('dark', palette.dark)]) {
          final mode = entry.$1;
          final c = entry.$2;
          final label = '${palette.id}.$mode';

          expect(
            _contrastRatio(c.textPrimary, c.background),
            greaterThanOrEqualTo(4.5),
            reason: '$label textPrimary vs background',
          );
          expect(
            _contrastRatio(c.textPrimary, c.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$label textPrimary vs surface',
          );
          expect(
            _contrastRatio(c.textSecondary, c.background),
            greaterThanOrEqualTo(4.5),
            reason: '$label textSecondary vs background',
          );
          expect(
            _contrastRatio(c.textSecondary, c.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$label textSecondary vs surface',
          );
          expect(
            _contrastRatio(c.textTertiary, c.background),
            greaterThanOrEqualTo(3.0),
            reason: '$label textTertiary vs background',
          );
          expect(
            _contrastRatio(c.primary, c.background),
            greaterThanOrEqualTo(4.5),
            reason: '$label primary vs background',
          );
          expect(
            _contrastRatio(c.primary, c.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$label primary vs surface',
          );
          expect(
            _contrastRatio(c.onPrimary, c.primary),
            greaterThanOrEqualTo(4.5),
            reason: '$label onPrimary vs primary',
          );
          final snackEffective = _compositeOver(
            c.snackBarBackground,
            c.background,
          );
          expect(
            _contrastRatio(Colors.white, snackEffective),
            greaterThanOrEqualTo(4.5),
            reason: '$label white vs snackBarBackground',
          );
        }
      }
    });
  });

  group('UI Helpers: motion, dialogs & overlay toast', () {
    testWidgets('motionDuration and CollapsibleSection respect disableAnimations & focus exclusion', (
      tester,
    ) async {
      late Duration capturedNormal;
      late Duration capturedReduced;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedNormal = motionDuration(
                context,
                const Duration(milliseconds: 240),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(capturedNormal, const Duration(milliseconds: 240));

      final animController = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 200),
      );
      addTearDown(animController.dispose);

      await tester.pumpWidget(
        _wrapApp(
          disableAnimations: false,
          child: Scaffold(
            body: CollapsibleSection(
              animation: animController,
              collapsed: true,
              child: ElevatedButton(onPressed: () {}, child: const Text('隐藏按钮')),
            ),
          ),
        ),
      );

      final excludeFocus = tester.widget<ExcludeFocus>(
        find.descendant(
          of: find.byType(CollapsibleSection),
          matching: find.byType(ExcludeFocus),
        ),
      );
      expect(excludeFocus.excluding, isTrue);

      await tester.pumpWidget(
        _wrapApp(
          disableAnimations: true,
          child: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (context) {
                    capturedReduced = motionDuration(
                      context,
                      const Duration(milliseconds: 240),
                    );
                    return const SizedBox.shrink();
                  },
                ),
                CollapsibleSection(
                  animation: animController,
                  collapsed: true,
                  child: const Text('已收起文本'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(capturedReduced, Duration.zero);
      expect(find.text('已收起文本'), findsNothing);
    });

    testWidgets('showDestructiveConfirmDialog focuses safe cancel and styles destructive button', (
      tester,
    ) async {
      bool? lastResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppPalette.inkwash.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  lastResult = await showDestructiveConfirmDialog(
                    context,
                    title: '移除曲目',
                    message: '确认从曲库移除吗？',
                    confirmLabel: '移除',
                  );
                },
                child: const Text('打开确认框'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开确认框'));
      await tester.pumpAndSettle();

      final cancelFinder = find.text('取消');
      expect(cancelFinder, findsOneWidget);
      final cancelFocus = Focus.of(tester.element(cancelFinder));
      expect(cancelFocus.hasPrimaryFocus, isTrue);

      final removeButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '移除'),
      );
      final theme = Theme.of(tester.element(find.text('移除')));
      expect(
        removeButton.style?.backgroundColor?.resolve({}),
        theme.colorScheme.error,
      );

      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();
      expect(lastResult, isFalse);

      await tester.tap(find.text('打开确认框'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(lastResult, isTrue);
    });

    testWidgets('AppToast surfaces above open modal AlertDialog and dismisses via close button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppPalette.inkwash.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      title: const Text('模态框'),
                      content: ElevatedButton(
                        onPressed: () {
                          AppToast.show(dialogCtx, '模态框内触发的提示');
                        },
                        child: const Text('触发提示'),
                      ),
                    ),
                  );
                },
                child: const Text('打开模态框'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开模态框'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('触发提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('模态框内触发的提示'), findsOneWidget);
      expect(find.byTooltip('关闭提示'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.text('模态框内触发的提示'), findsNothing);
    });
  });

  group('Responsive layout, text scale & regression behaviors', () {
    late Directory tempDir;
    late StorageService storage;
    late Song songA;
    late Song songB;
    late Playlist playlist;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aquamoon_ui_a11y_');
      storage = StorageService();
      await storage.init(tempDir.path);
      songA = Song(
        id: 'a1',
        title: '空山鸟语 · 禅韵长卷版超长曲名测试适配效果',
        artist: '竹林演奏家',
        album: '山水清音集',
        durationMs: 245000,
        filePath: '/music/kongshan.flac',
        dateAdded: DateTime(2026, 1, 2),
      );
      songB = Song(
        id: 'b2',
        title: '平沙落雁',
        artist: '古琴名家',
        album: '琴韵',
        durationMs: 198000,
        filePath: '/music/pingsha.mp3',
        dateAdded: DateTime(2026, 1, 1),
      );
      playlist = Playlist(
        id: 'p1',
        name: '秋水共长天一色 · 超长歌单名称测试卡片布局自适应',
        description: '古琴与箫声合集',
        songIds: [songA.id, songB.id],
        createdAt: DateTime(2026, 1, 3),
      );
      await storage.saveSongs([songA, songB]);
      await storage.savePlaylist(playlist);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('AllSongsTab enters batch selection with 0 preselected and handles 320px + 2.0x textScale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(storage),
          child: _wrapApp(
            size: const Size(320, 720),
            textScale: 2.0,
            child: const Scaffold(body: AllSongsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SongTile), findsNWidgets(2));

      await tester.tap(find.byTooltip('排序与更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('批量管理（多选）'));
      await tester.pumpAndSettle();

      // Previously preselected songs.first; must now start with zero checked.
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PlaylistsTab & LyricsDisplaySettingsPage adapt at 320px with 2.0x textScale without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(storage),
          child: _wrapApp(
            size: const Size(320, 720),
            textScale: 2.0,
            child: const Scaffold(body: PlaylistsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('秋水共长天一色'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(storage),
          child: _wrapApp(
            size: const Size(320, 720),
            textScale: 2.0,
            child: const LyricsDisplaySettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('当前行停留位置'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('当前行停留位置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PlaylistDetailPage & cover sheet adapt at 320px + 2.0x textScale with explicit close button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(storage),
          child: _wrapApp(
            size: const Size(320, 720),
            textScale: 2.0,
            child: PlaylistDetailPage(playlist: playlist),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('更换歌单封面'));
      await tester.pumpAndSettle();
      expect(find.text('选择歌单封面'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('选择歌单封面'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
