import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/lyrics_provider.dart';
import 'package:aquamoon/services/online_metadata_service.dart';
import 'package:aquamoon/views/player/lyrics_view.dart';

/// Regression tests for the player page cover ↔ lyrics swipe:
///
/// 1. The lyric auto-scroll must never scroll the outer horizontal PageView
///    (Scrollable.ensureVisible walks every ancestor Scrollable and used to
///    yank the page mid-swipe).
/// 2. The first positioning must be instant, not a 700 ms "fly" from the top.
/// 3. The lyrics page must stay alive (scroll position preserved) across
///    cover ↔ lyrics page switches.
void main() {
  final testSong = Song(
    id: 'song_test',
    title: '测试歌曲',
    artist: '测试歌手',
    album: '测试专辑',
    durationMs: 240000,
    filePath: '/tmp/test.mp3',
    dateAdded: DateTime(2026),
    lrcContent: List.generate(120, (i) {
      final seconds = i * 2;
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      return '[$m:$s.00]歌词第${i + 1}行';
    }).join('\n'),
  );

  ScrollPosition lyricsPosition(
    WidgetTester tester, {
    bool skipOffstage = true,
  }) {
    final finder = find.descendant(
      of: find.byType(LyricsView, skipOffstage: skipOffstage),
      matching: find.byType(Scrollable, skipOffstage: skipOffstage),
    );
    return tester.state<ScrollableState>(finder.first).position;
  }

  /// Pumps frame by frame until the lyric ListView exists, then returns the
  /// scroll position captured on that very frame (before any later settling).
  Future<ScrollPosition> pumpUntilLyricsList(WidgetTester tester) async {
    ScrollPosition? position;
    for (var i = 0; i < 10 && position == null; i++) {
      await tester.pump();
      if (tester.any(find.byType(LyricsView))) {
        try {
          position = lyricsPosition(tester);
        } on StateError {
          // Lyric list not built yet (lyrics still loading); keep pumping.
        }
      }
    }
    expect(position, isNotNull, reason: 'lyric ListView never appeared');
    return position!;
  }

  Future<ProviderContainer> pumpPlayerHarness(
    WidgetTester tester, {
    required PageController pageController,
    required StateProvider<int> activeIndexProvider,
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentSongProvider.overrideWith((ref) => Stream.value(testSong)),
        currentLyricIndexProvider.overrideWith(
          (ref) => ref.watch(activeIndexProvider),
        ),
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
          home: Scaffold(
            body: PageView(
              controller: pageController,
              children: [
                const Center(child: Text('封面')),
                LyricsView(song: testSong, onTapBackground: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('entering lyrics page positions instantly at 34% alignment', (
    tester,
  ) async {
    final pageController = PageController();
    final activeIndexProvider = StateProvider<int>((ref) => 3);
    await pumpPlayerHarness(
      tester,
      pageController: pageController,
      activeIndexProvider: activeIndexProvider,
    );

    pageController.jumpToPage(1);
    final position = await pumpUntilLyricsList(tester);

    // On the very frame the list appears it must already be at the active
    // line (jumpTo), not still near the top of a 700 ms animation.
    final offsetOnFirstFrame = position.pixels;
    expect(
      offsetOnFirstFrame,
      greaterThan(100),
      reason: 'active line should be positioned, not at the list top',
    );

    await tester.pumpAndSettle();
    expect(
      lyricsPosition(tester).pixels,
      offsetOnFirstFrame,
      reason: 'first positioning is a jump, not a 700 ms glide',
    );

    // The active line sits in the upper-middle band (~34% from the top).
    final viewportHeight = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(LyricsView),
            matching: find.byType(Scrollable),
          ).first,
        )
        .position
        .viewportDimension;
    final activeLineTop = tester.getRect(find.text('歌词第4行')).top;
    expect(
      activeLineTop,
      inInclusiveRange(viewportHeight * 0.25, viewportHeight * 0.40),
    );
  });

  testWidgets('line change during an active page drag does not hijack it', (
    tester,
  ) async {
    final pageController = PageController();
    final activeIndexProvider = StateProvider<int>((ref) => 3);
    final container = await pumpPlayerHarness(
      tester,
      pageController: pageController,
      activeIndexProvider: activeIndexProvider,
    );

    pageController.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(
      lyricsPosition(tester).pixels,
      greaterThan(100),
    );

    final pageSize = tester.getSize(find.byType(PageView));

    // User starts dragging from the lyrics page back toward the cover and
    // keeps the finger down past the halfway point.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
    }
    final draggedPixels = pageController.position.pixels;
    expect(draggedPixels, lessThan(pageSize.width * 0.45));

    // Active lyric line advances mid-drag. The old Scrollable.ensureVisible
    // called here animated the PageView back to the lyrics page, yanking the
    // user's finger.
    container.read(activeIndexProvider.notifier).state = 8;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // User finishes the swipe and releases.
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // The swipe must land on the cover page the user dragged to.
    expect(pageController.page, 0.0);

    // The lyric list still followed the active line change (in the
    // keep-alive bucket now that page 1 is offstage).
    expect(
      lyricsPosition(tester, skipOffstage: false).pixels,
      greaterThan(300),
    );
    expect(find.text('歌词第9行', skipOffstage: false), findsOneWidget);
  });

  testWidgets('lyrics scroll position survives cover ↔ lyrics round trip', (
    tester,
  ) async {
    final pageController = PageController();
    final activeIndexProvider = StateProvider<int>((ref) => 3);
    await pumpPlayerHarness(
      tester,
      pageController: pageController,
      activeIndexProvider: activeIndexProvider,
    );

    pageController.jumpToPage(1);
    await tester.pumpAndSettle();

    // User scrolls the lyrics manually, then swipes back to the cover.
    lyricsPosition(tester).jumpTo(2000);
    await tester.pumpAndSettle();
    pageController.jumpToPage(0);
    await tester.pumpAndSettle();

    // Returning to the lyrics page must restore the manual position, not
    // rebuild from the top and re-scroll to the active line.
    pageController.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(lyricsPosition(tester).pixels, 2000);
  });
}
