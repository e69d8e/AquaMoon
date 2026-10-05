import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/lyrics_provider.dart';
import 'package:aquamoon/services/online_metadata_service.dart';
import 'package:aquamoon/views/widgets/online_candidate_dialog.dart';

/// 搜索返回不含歌词的 QQ 音乐候选，ensureLyricsLoaded 补出同步歌词。
class _FakeOnlineService implements OnlineMetadataService {
  @override
  Future<List<OnlineSearchResult>> searchCandidates({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    return const [
      OnlineSearchResult(
        source: 'QQ音乐',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        durationMs: 269000,
        matchScore: 90,
        extraId: 'qq-mid-1',
      ),
      OnlineSearchResult(
        source: 'QQ音乐',
        title: '晴天（Live）',
        artist: '周杰伦',
        album: '叶惠美',
        durationMs: 300000,
        matchScore: 60,
        extraId: 'qq-mid-2',
      ),
    ];
  }

  @override
  Future<OnlineSearchResult> ensureLyricsLoaded(
    OnlineSearchResult candidate,
  ) async {
    return candidate.copyWith(syncedLyrics: '[00:01.00]预取的LRC歌词');
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 回归：候选卡片的歌词标签必须在搜索返回后自动就位（“LRC 滚动歌词”），
/// 不能等用户点过“预览歌词”才从“无歌词”翻正。
void main() {
  testWidgets('candidate lyric tag resolves via prefetch without preview tap', (
    tester,
  ) async {
    final song = Song(
      id: 's1',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      durationMs: 269000,
      filePath: '/music/qingtian.mp3',
      dateAdded: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMetadataServiceProvider.overrideWithValue(_FakeOnlineService()),
        ],
        child: MaterialApp(
          home: Scaffold(body: OnlineCandidateSelectDialog(song: song)),
        ),
      ),
    );

    await tester.pump(); // initState 触发首轮检索
    await tester.pumpAndSettle(); // 检索与首选歌词预取全部落定

    // 只有推荐首选被自动预取；其余候选保持按需拉取，不并发预取全部。
    expect(find.text('LRC 滚动歌词'), findsOneWidget);
    expect(find.text('无歌词'), findsOneWidget);

    // 首选展开预览无需再触发拉取，直接能看到已补齐的歌词。
    await tester.tap(find.text('预览歌词').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('预取的LRC歌词'), findsOneWidget);
  });
}
