import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/library_provider.dart';
import 'package:aquamoon/providers/playback_preferences_provider.dart';
import 'package:aquamoon/services/storage_service.dart';

/// 只实现「本地优先」判定需要的读取口，避免测试触碰真实 Hive。
class _FakeStorage extends StorageService {
  _FakeStorage({
    this.preferLocal = false,
    List<Song> songs = const [],
  }) : _songs = List.of(songs);

  bool preferLocal;
  final List<Song> _songs;

  @override
  List<Song> getAllSongs() => List.of(_songs);

  @override
  bool getPreferLocalPlayback() => preferLocal;

  @override
  Future<void> savePreferLocalPlayback(bool enabled) async {
    preferLocal = enabled;
  }
}

Song _onlineSong({String mid = '001abc', String title = '青花瓷'}) => Song(
  id: 'qq_$mid',
  title: title,
  artist: '周杰伦',
  album: '我很忙',
  durationMs: 239000,
  filePath: 'qqmusic://$mid',
  dateAdded: DateTime(2026, 1, 1),
  source: SongSource.online,
  qqSongMid: mid,
  qqSongId: 1001,
);

Song _localSong({
  String id = 'local-1',
  String title = '青花瓷',
  String artist = '周杰伦',
  String filePath = '/music/qinghuaci.flac',
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: '我很忙',
  durationMs: 239000,
  filePath: filePath,
  dateAdded: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('优先播放本地音频开关', () {
    test('初始状态来自持久化设置，切换后立即落盘', () async {
      final storage = _FakeStorage(preferLocal: false);
      final notifier = PreferLocalPlaybackNotifier(storage);
      addTearDown(notifier.dispose);

      expect(notifier.state, isFalse);

      await notifier.setPreferLocalPlayback(true);
      expect(notifier.state, isTrue);
      expect(storage.preferLocal, isTrue);
      expect(storage.getPreferLocalPlayback(), isTrue);

      await notifier.setPreferLocalPlayback(false);
      expect(notifier.state, isFalse);
      expect(storage.preferLocal, isFalse);
    });

    test('已开启的用户重启后开关保持开启', () {
      final notifier = PreferLocalPlaybackNotifier(_FakeStorage(preferLocal: true));
      addTearDown(notifier.dispose);
      expect(notifier.state, isTrue);
    });
  });

  group('hasLocalCopyProvider：界面与引擎同一判定', () {
    ProviderContainer buildContainer(_FakeStorage storage) {
      final container = ProviderContainer(
        overrides: <Override>[
          storageServiceProvider.overrideWithValue(storage),
          libraryNotifierProvider.overrideWith(
            (ref) => LibraryNotifier(storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('开关关闭时不走本地副本（保持既有在线播放行为）', () {
      final container = buildContainer(
        _FakeStorage(preferLocal: false, songs: [_localSong()]),
      );
      expect(container.read(hasLocalCopyProvider(_onlineSong())), isFalse);
    });

    test('开关打开且曲库有同一首歌时命中本地副本', () {
      final container = buildContainer(
        _FakeStorage(preferLocal: true, songs: [_localSong()]),
      );
      expect(container.read(hasLocalCopyProvider(_onlineSong())), isTrue);
    });

    test('开关打开但曲库没有这首歌时不命中', () {
      final container = buildContainer(
        _FakeStorage(
          preferLocal: true,
          songs: [_localSong(id: 'other', title: '稻香')],
        ),
      );
      expect(container.read(hasLocalCopyProvider(_onlineSong())), isFalse);
    });

    test('本地曲目自身不参与「本地副本」判定', () {
      final container = buildContainer(
        _FakeStorage(preferLocal: true, songs: [_localSong()]),
      );
      expect(
        container.read(hasLocalCopyProvider(_localSong())),
        isFalse,
      );
    });

    test('带版本后缀的在线标题仍能匹配到本地同名曲目', () {
      final container = buildContainer(
        _FakeStorage(preferLocal: true, songs: [_localSong()]),
      );
      expect(
        container.read(hasLocalCopyProvider(_onlineSong(title: '青花瓷 (Live)'))),
        isTrue,
      );
    });
  });
}