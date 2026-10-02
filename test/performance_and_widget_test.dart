import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/models/playback_progress.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/views/widgets/custom_progress_bar.dart';
import 'package:aquamoon/views/widgets/song_artwork.dart';
import 'package:aquamoon/views/widgets/song_tile.dart';

void main() {
  group('Widget & UI Component Performance Tests', () {
    final testSong = Song(
      id: 'test-s1',
      title: '彩云追月',
      artist: '广东民乐团',
      album: '岭南春色',
      durationMs: 185000,
      filePath: '/dummy/caiyun.mp3',
      dateAdded: DateTime(2026, 1, 1),
      isFavorite: false,
    );

    testWidgets('SongArtwork renders rounded and circle shapes with custom sizes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SongArtwork(
                  song: testSong,
                  size: 64,
                  borderRadius: 12,
                  isRound: false,
                ),
                SongArtwork(
                  song: testSong,
                  size: 48,
                  isRound: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(SongArtwork), findsNWidgets(2));
      expect(find.byIcon(Icons.music_note_rounded), findsNWidgets(2));

      // Check size of first container
      final firstContainer = tester.widget<Container>(find.byType(Container).first);
      final boxDeco = firstContainer.decoration as BoxDecoration?;
      expect(boxDeco?.shape, BoxShape.rectangle);
      expect(boxDeco?.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('CustomProgressBar displays formatted duration and handles seek events', (tester) async {
      Duration? seekTarget;
      Duration? seekingTarget;

      const progress = PlaybackProgress(
        position: Duration(seconds: 45),
        bufferedPosition: Duration(seconds: 90),
        duration: Duration(minutes: 3, seconds: 5), // 185 seconds
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomProgressBar(
              progress: progress,
              onSeek: (pos) => seekTarget = pos,
              onSeeking: (pos) => seekingTarget = pos,
              showTimeLabels: true,
            ),
          ),
        ),
      );

      // Verify time labels are displayed
      expect(find.text('00:45'), findsOneWidget);
      expect(find.text('03:05'), findsOneWidget);

      // Verify Slider widget exists
      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.max, 185000.0);
      expect(slider.value, 45000.0);

      // Simulate dragging slider
      slider.onChanged?.call(60000.0);
      expect(seekingTarget, const Duration(seconds: 60));

      slider.onChangeEnd?.call(75000.0);
      expect(seekTarget, const Duration(seconds: 75));
    });

    testWidgets('SongTile renders song info, duration, and handles tap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SongTile(
                song: testSong,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify song title and artist rendered
      expect(find.text('彩云追月'), findsOneWidget);
      expect(find.text('广东民乐团 · 岭南春色'), findsOneWidget);
      expect(find.text('03:05'), findsOneWidget);

      // Tap the tile
      await tester.tap(find.byType(InkWell).first);
      expect(tapped, isTrue);
    });

    testWidgets('SongTile shows play count when > 0 and hides it when 0', (
      tester,
    ) async {
      final playedSong = testSong.copyWith(playCount: 42);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: SongTile(song: playedSong, onTap: () {})),
          ),
        ),
      );

      expect(find.text('42'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Unplayed song (playCount defaults to 0): no count UI.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: Scaffold(body: SongTile(song: testSong))),
        ),
      );

      expect(find.text('42'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.text('03:05'), findsOneWidget);
    });
  });
}
