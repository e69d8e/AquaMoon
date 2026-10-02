import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart'
    show storageServiceProvider;
import 'package:aquamoon/providers/library_provider.dart';
import 'package:aquamoon/services/storage_service.dart';
import 'package:aquamoon/views/home/tabs/all_songs_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storageService;

  final songA = Song(
    id: 's-a',
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    durationMs: 180000,
    filePath: '/music/a.mp3',
    dateAdded: DateTime(2026, 1, 1),
  );

  final songB = Song(
    id: 's-b',
    title: '夜曲',
    artist: '林俊杰',
    album: '曹操',
    durationMs: 240000,
    filePath: '/music/b.mp3',
    dateAdded: DateTime(2026, 2, 1),
  );

  Future<ProviderContainer> pumpTab(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AllSongsTab())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('search_clear_test_');
    storageService = StorageService();
    await storageService.init(tempDir.path);
    await storageService.saveSongs([songA, songB]);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('曲库搜索栏取消输入', () {
    bool searchFieldFocused() {
      return FocusManager
              .instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() !=
          null;
    }

    testWidgets('输入文字后清除按钮立即可见（不等待 300ms 防抖）', (tester) async {
      await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      // Deliberately do NOT advance past the 300ms debounce window.
      await tester.pump();

      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
    });

    testWidgets('防抖生效后点 × 同时清空输入框与过滤条件', (tester) async {
      final container = await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(searchQueryProvider), '晴');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('夜曲'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      expect(container.read(searchQueryProvider), '');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('夜曲'), findsOneWidget);
    });

    testWidgets('输入法合成期间点 ×：清除后，合成提交不得复活过滤条件', (tester) async {
      final container = await pumpTab(tester);

      // Focus the field and simulate a platform-side IME composing update
      // (marked text still active, as with a Chinese IME).
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '晴',
        composing: TextRange(start: 0, end: 1),
        selection: TextSelection.collapsed(offset: 1),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(searchQueryProvider), '晴');

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();
      expect(container.read(searchQueryProvider), '');

      // A real desktop IME commits its marked text when the field's editing
      // state is reset; that commit arrives as a late platform message.
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '晴',
        composing: TextRange(start: 0, end: 1),
        selection: TextSelection.collapsed(offset: 1),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      // The user already cancelled the search: the filter must stay empty.
      expect(container.read(searchQueryProvider), '');
    });

    testWidgets('点 × 后输入框失去焦点（取消输入 = 同时断开 IME 连接）', (tester) async {
      await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump(const Duration(milliseconds: 400));
      expect(searchFieldFocused(), isTrue);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      expect(searchFieldFocused(), isFalse);
    });

    testWidgets('点其他操作（菜单按钮）时输入框失去焦点，输入法被收起', (tester) async {
      await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump();
      expect(searchFieldFocused(), isTrue);

      // Flutter's default keeps touch taps outside the field focused on
      // mobile; the explicit onTapOutside must drop it.
      await tester.tap(find.byTooltip('排序与更多操作'));
      await tester.pumpAndSettle();

      expect(searchFieldFocused(), isFalse);
    });

    testWidgets('菜单关闭后焦点不回到输入框（输入法不再被复唤）', (tester) async {
      await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump();

      await tester.tap(find.byTooltip('排序与更多操作'));
      await tester.pumpAndSettle();

      // Close the popup via the modal barrier.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byTooltip('排序与更多操作'), findsOneWidget);

      expect(searchFieldFocused(), isFalse);
    });

    testWidgets('State 重建（如桌面布局切换）后，过滤中的关键词回填到输入框', (tester) async {
      final container = await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('夜曲'), findsNothing);

      // Force the tab State to be recreated while the provider survives —
      // same as switching the desktop layout across the 720px breakpoint.
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
          child: const MaterialApp(home: Scaffold(body: AllSongsTab())),
        ),
      );
      await tester.pumpAndSettle();

      // The filter is still active, so the field must show the query and
      // offer the clear button — an empty-looking box with a filtered list
      // is the trap where search input becomes impossible to cancel.
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller;
      expect(controller!.text, '晴');
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
      expect(find.text('夜曲'), findsNothing);

      // And cancelling still works end to end.
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();
      expect(container.read(searchQueryProvider), '');
      expect(find.text('夜曲'), findsOneWidget);
    });

    testWidgets('清除后重新输入可以再次过滤', (tester) async {
      final container = await pumpTab(tester);

      await tester.enterText(find.byType(TextField), '晴');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '夜');
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(searchQueryProvider), '夜');
      expect(find.text('夜曲'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);
    });
  });
}
