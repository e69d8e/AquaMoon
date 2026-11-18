import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/views/widgets/song_tile.dart';

void main() {
  final cloudSong = Song(
    id: 'qq_002qU5aY3Qu24y',
    title: '青花瓷',
    artist: '周杰伦',
    album: '我很忙',
    durationMs: 239000,
    filePath: 'qqmusic://002qU5aY3Qu24y',
    dateAdded: DateTime(2026, 1, 1),
    source: SongSource.online,
    qqSongMid: '002qU5aY3Qu24y',
    isVip: true,
  );

  Future<void> openMenu(WidgetTester tester, Song song) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: SongTile(song: song))),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('云端 QQ 音乐曲目的「⋮」菜单提供下载入口', (tester) async {
    await openMenu(tester, cloudSong);

    expect(find.text('下载到本地'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('已落地为本地文件的曲目不显示下载入口', (tester) async {
    final local = cloudSong.copyWith(
      id: 'local-1',
      filePath: '/storage/emulated/0/Music/周杰伦 - 青花瓷.mp3',
      source: SongSource.local,
    );

    await openMenu(tester, local);

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('下载到本地'), findsNothing);
  });

  testWidgets('没有 QQ songmid 的曲目不显示下载入口', (tester) async {
    final onlineWithoutMid = Song(
      id: 'online-1',
      title: '在线曲目',
      artist: '未知',
      album: '',
      durationMs: 1000,
      filePath: 'https://example.com/a.mp3',
      dateAdded: DateTime(2026, 1, 1),
      source: SongSource.online,
    );

    await openMenu(tester, onlineWithoutMid);

    expect(find.text('下载到本地'), findsNothing);
  });
}
