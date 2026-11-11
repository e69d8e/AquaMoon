import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aquamoon/models/qq_music_config.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/providers/audio_provider.dart';
import 'package:aquamoon/providers/library_provider.dart';
import 'package:aquamoon/providers/playlist_provider.dart';
import 'package:aquamoon/providers/qq_music_provider.dart';
import 'package:aquamoon/services/qq_music_service.dart';
import 'package:aquamoon/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QQMusicConfig parsing & serialization', () {
    test('extracts uin and authKey from Cookie string', () {
      const cookie =
          'pgv_pvid=111; uin=o012345678; qm_keyst=Q_H_L_5abc123; ts_uid=999';
      expect(QQMusicConfig.extractUinFromCookie(cookie), '12345678');
      expect(QQMusicConfig.extractAuthKeyFromCookie(cookie), 'Q_H_L_5abc123');

      const config = QQMusicConfig(cookie: cookie);
      expect(config.effectiveUin, '12345678');
      expect(config.hasCookie, isTrue);
      expect(config.isBound, isTrue);
    });

    test('parses playlist dissid from share URLs and QQ numbers', () {
      expect(
        QQMusicConfig.parseAccountOrPlaylistInput(
          'https://y.qq.com/n/ryqq/playlist/8899001122',
        ),
        (uin: '', dissid: '8899001122'),
      );
      expect(
        QQMusicConfig.parseAccountOrPlaylistInput(
          '分享歌单 https://i.y.qq.com/n2/m/share/details/taoge.html?id=765432109&hosteuin=abc',
        ),
        (uin: '', dissid: '765432109'),
      );
      expect(
        QQMusicConfig.parseAccountOrPlaylistInput('o098765432'),
        (uin: '98765432', dissid: ''),
      );
    });
  });

  group('Song model QQ Music fields & backward compatibility', () {
    test('round-trips qqSongMid, qqSongId, qqMediaMid, and isVip', () {
      final onlineSong = Song(
        id: 'qq_0039MnYb0qxYhV',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        durationMs: 269000,
        filePath: 'qqmusic://0039MnYb0qxYhV',
        dateAdded: DateTime(2026, 5, 1),
        isFavorite: true,
        source: SongSource.online,
        qqSongMid: '0039MnYb0qxYhV',
        qqSongId: 97773,
        qqMediaMid: '002202B43Cq4V4',
        isVip: true,
      );

      expect(onlineSong.hasLocalFile, isFalse);
      expect(onlineSong.isQQMusicOnline, isTrue);

      final restored = Song.fromMap(onlineSong.toMap());
      expect(restored.qqSongMid, '0039MnYb0qxYhV');
      expect(restored.qqSongId, 97773);
      expect(restored.qqMediaMid, '002202B43Cq4V4');
      expect(restored.isVip, isTrue);
      expect(restored.isQQMusicOnline, isTrue);
    });

    test('loads legacy map without QQ Music fields safely', () {
      final legacy = Song.fromMap({
        'id': 'local-1',
        'title': '兰亭序',
        'artist': '周杰伦',
        'album': '魔杰座',
        'durationMs': 253000,
        'filePath': '/music/lantingxu.flac',
      });
      expect(legacy.qqSongMid, isNull);
      expect(legacy.qqSongId, isNull);
      expect(legacy.isVip, isFalse);
      expect(legacy.hasLocalFile, isTrue);
      expect(legacy.isQQMusicOnline, isFalse);
    });
  });

  group('QQMusicService API interactions', () {
    test(
      'syncFavoritePlaylist resolves dissid from profile and parses songs',
      () async {
        final client = MockClient((request) async {
          if (request.url.path.contains('fcg_get_profile_homepage.fcg')) {
            return http.Response.bytes(
              utf8.encode(
                json.encode({
                  'code': 0,
                  'data': {
                    'creator': {'nick': '水墨琴客'},
                    'mymusic': [
                      {'title': '我喜欢', 'id': '700123456', 'num0': 2},
                    ],
                  },
                }),
              ),
              200,
            );
          }
          if (request.url.path.contains('fcg_ucc_getcdinfo_byids_cp.fcg')) {
            // Simulate JSONP-wrapped response to verify stripJsonp as well
            final payload = json.encode({
              'code': 0,
              'cdlist': [
                {
                  'dissname': '我喜欢',
                  'nickname': '水墨琴客',
                  'total_song_num': 2,
                  'songlist': [
                    {
                      'mid': '001abc',
                      'id': 1001,
                      'title': '青花瓷',
                      'singer': [
                        {'name': '周杰伦'},
                      ],
                      'album': {'name': '我很忙', 'mid': '002efg'},
                      'file': {'media_mid': '003media'},
                      'interval': 239,
                      'pay': {'pay_play': 1},
                    },
                    {
                      'mid': '002xyz',
                      'id': 1002,
                      'title': '高山流水',
                      'singer': [
                        {'name': '古琴名家'},
                      ],
                      'album': {'name': '国乐大典', 'mid': ''},
                      'interval': 200,
                      'pay': {'pay_play': 0},
                    },
                  ],
                },
              ],
            });
            return http.Response.bytes(
              utf8.encode('jsonCallback($payload)'),
              200,
            );
          }
          return http.Response('not found', 404);
        });

        final service = QQMusicService(client: client);
        final res = await service.syncFavoritePlaylist(
          const QQMusicConfig(uin: '12345678'),
        );

        expect(res.dissid, '700123456');
        expect(res.nickname, '水墨琴客');
        expect(res.songs.length, 2);
        expect(res.songs[0].title, '青花瓷');
        expect(res.songs[0].qqSongMid, '001abc');
        expect(res.songs[0].qqSongId, 1001);
        expect(res.songs[0].qqMediaMid, '003media');
        expect(res.songs[0].isVip, isTrue);
        expect(
          res.songs[0].albumArtUri,
          'https://y.gtimg.cn/music/photo_new/T002R800x800M000002efg.jpg',
        );
        expect(res.songs[1].title, '高山流水');
        expect(res.songs[1].isVip, isFalse);
      },
    );

    test(
      'resolvePlayUrl assembles HTTPS stream URL and returns null on empty purl',
      () async {
        final client = MockClient((request) async {
          final body = json.decode(request.body) as Map<String, dynamic>;
          final req0 = body['req_0'] as Map<String, dynamic>;
          final param = req0['param'] as Map<String, dynamic>;
          final mids = param['songmid'] as List<dynamic>;
          final mid = mids.first as String;

          if (mid == 'vip_blocked_mid') {
            return http.Response(
              json.encode({
                'req_0': {
                  'data': {
                    'sip': ['http://ws.stream.qqmusic.qq.com/'],
                    'midurlinfo': [
                      {'songmid': mid, 'purl': ''},
                    ],
                  },
                },
              }),
              200,
            );
          }

          return http.Response(
            json.encode({
              'req_0': {
                'data': {
                  'sip': ['http://ws.stream.qqmusic.qq.com/'],
                  'midurlinfo': [
                    {
                      'songmid': mid,
                      'purl': 'C400$mid.m4a?guid=10000&vkey=MOCK_VKEY',
                    },
                  ],
                },
              },
            }),
            200,
          );
        });

        final service = QQMusicService(client: client);
        final streamUrl = await service.resolvePlayUrl(songMid: '001abc');
        expect(
          streamUrl,
          'https://ws.stream.qqmusic.qq.com/C400001abc.m4a?guid=10000&vkey=MOCK_VKEY',
        );

        final blockedUrl = await service.resolvePlayUrl(
          songMid: 'vip_blocked_mid',
        );
        expect(blockedUrl, isNull);
      },
    );

    test('fetchLyricsBySongMid decodes Base64 LRC content', () async {
      const sampleLrc = '[00:01.00]天青色等烟雨\n[00:05.00]而我在等你';
      final b64 = base64.encode(utf8.encode(sampleLrc));

      final client = MockClient((request) async {
        return http.Response(
          json.encode({'retcode': 0, 'lyric': b64}),
          200,
        );
      });

      final service = QQMusicService(client: client);
      final lrc = await service.fetchLyricsBySongMid('001abc');
      expect(lrc, sampleLrc);
    });

    test(
      'fetchCloudListeningHistory parses PlayRecentlyRead listenCnt on the desktop private channel',
      () async {
        Uri? capturedUrl;
        Map<String, dynamic>? capturedBody;
        final client = MockClient((request) async {
          capturedUrl = request.url;
          capturedBody = json.decode(request.body) as Map<String, dynamic>;
          const key =
              'music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo';
          final payload = json.encode({
            'code': 0,
            key: {
              'code': 0,
              'data': {
                'type': 2,
                'code': 0,
                'updateTime': 1700000000,
                'data': {
                  'songList': [
                    {
                      'track': {
                        'mid': '003hist',
                        'id': 3001,
                        'title': '稻香',
                        'singer': [
                          {'name': '周杰伦'},
                        ],
                        'album': {'name': '魔杰座', 'mid': '003alb'},
                        'interval': 223,
                      },
                      'lastTime': 1700000000,
                      'listenCnt': 5,
                      'lastPlayDevice': 0,
                    },
                  ],
                },
              },
            },
          });
          return http.Response.bytes(utf8.encode(payload), 200);
        });

        final service = QQMusicService(
          client: client,
          desktopGuid: '0123456789ABCDEF0123456789ABCDEF',
        );
        final history = await service.fetchCloudListeningHistory(
          const QQMusicConfig(
            uin: '123456',
            cookie: 'uin=o123456; qm_keyst=testkey;',
          ),
        );

        // 走 PC 私有通道，请求键是 module.method
        expect(capturedUrl?.host, 'u6.y.qq.com');
        expect(
          capturedBody?.containsKey(
            'music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo',
          ),
          isTrue,
        );
        expect(
          capturedBody?['music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo']
              ?['param']?['type'],
          2,
        );

        expect(history.length, 1);
        final entry = history.first;
        expect(entry.song.qqSongMid, '003hist');
        expect(entry.song.title, '稻香');
        expect(entry.song.qqSongId, 3001);
        expect(entry.playCount, 5);
        expect(
          entry.lastPlayedAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
      },
    );

    test(
      'fetchCloudListeningHistory returns empty without Cookie (endpoint requires login)',
      () async {
        var called = false;
        final client = MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        });
        final service = QQMusicService(client: client);
        final history = await service.fetchCloudListeningHistory(
          const QQMusicConfig(uin: '123456'),
        );
        expect(history, isEmpty);
        expect(called, isFalse);
      },
    );

    test('fetchTodayListenSeconds reads todayLT from SoundPowerSvr', () async {
      final client = MockClient((request) async {
        final payload = json.encode({
          'code': 0,
          'req_0': {
            'code': 0,
            'data': {
              'powerInfo': {'level': 3, 'name': 'S3'},
              'todayLT': 4321,
            },
          },
        });
        return http.Response.bytes(utf8.encode(payload), 200);
      });

      final service = QQMusicService(client: client);
      final seconds = await service.fetchTodayListenSeconds(
        const QQMusicConfig(
          uin: '123456',
          cookie: 'uin=o123456; qm_keyst=testkey;',
        ),
      );
      expect(seconds, 4321);
    });

    test(
      'reportSongPlayback posts PlayRecentlyWrite payload and requires data.ret == 0',
      () async {
        Map<String, dynamic>? capturedBody;
        final client = MockClient((request) async {
          capturedBody = json.decode(request.body) as Map<String, dynamic>;
          const key =
              'music.musicasset.PlayRecentlyWrite.ReportPlayRecentlyInfo';
          final payload = json.encode({
            'code': 0,
            key: {
              'code': 0,
              'data': {'ret': 0},
            },
          });
          return http.Response.bytes(utf8.encode(payload), 200);
        });

        final service = QQMusicService(
          client: client,
          desktopGuid: '0123456789ABCDEF0123456789ABCDEF',
        );
        final song = Song(
          id: 'qq_003hist',
          title: '稻香',
          artist: '周杰伦',
          album: '魔杰座',
          durationMs: 223000,
          filePath: 'qqmusic://003hist',
          dateAdded: DateTime(2026, 1, 1),
          source: SongSource.online,
          qqSongMid: '003hist',
          qqSongId: 3001,
        );

        final ok = await service.reportSongPlayback(
          song: song,
          config: const QQMusicConfig(
            uin: '123456',
            cookie: 'uin=o123456; qm_keyst=testkey;',
          ),
        );
        expect(ok, isTrue);

        final param =
            capturedBody?['music.musicasset.PlayRecentlyWrite.ReportPlayRecentlyInfo']
                ?['param'];
        final list = param?['data'] as List?;
        expect(list, isNotNull);
        final first = list!.first as Map;
        expect(first['id'], '3001');
        expect(first['listenCnt'], 1);
        expect(first['type'], 2);
        expect(first['lastTime'], isA<int>());
      },
    );

    test('reportSongPlayback is skipped when the song has no numeric id', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = QQMusicService(client: client);
      final song = Song(
        id: 'qq_missing_id',
        title: '无 ID 曲目',
        artist: '未知',
        album: '未知',
        durationMs: 1000,
        filePath: 'qqmusic://missing_id',
        dateAdded: DateTime(2026, 1, 1),
        source: SongSource.online,
        qqSongMid: 'missing_id',
      );
      final ok = await service.reportSongPlayback(
        song: song,
        config: const QQMusicConfig(
          uin: '123456',
          cookie: 'uin=o123456; qm_keyst=testkey;',
        ),
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });
  });

  group('QQMusicFavoritesNotifier & hybrid local-online merge', () {
    late Directory tempDir;
    late StorageService storageService;

    final localMatchedSong = Song(
      id: 'local-gaoshan',
      title: '高山流水',
      artist: '古琴名家',
      album: '未知专辑',
      durationMs: 200500,
      filePath: '/music/gaoshan.flac',
      dateAdded: DateTime(2026, 1, 1),
      isFavorite: false,
      source: SongSource.local,
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_qq_fav_test_');
      storageService = StorageService();
      await storageService.init(tempDir.path);
      await storageService.saveSongs([localMatchedSong]);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'merges remote QQ Music favorites with local library without polluting local song list',
      () async {
        final mockService = QQMusicService(
          client: MockClient((request) async {
            final payload = json.encode({
              'code': 0,
              'cdlist': [
                {
                  'dissname': '我喜欢',
                  'nickname': '测试用户',
                  'total_song_num': 2,
                  'songlist': [
                    {
                      'mid': '001online',
                      'id': 2001,
                      'title': '晴天',
                      'singer': [
                        {'name': '周杰伦'},
                      ],
                      'album': {'name': '叶惠美', 'mid': '002album'},
                      'interval': 269,
                      'pay': {'pay_play': 1},
                    },
                    {
                      'mid': '002localmatch',
                      'id': 2002,
                      'title': '高山流水',
                      'singer': [
                        {'name': '古琴名家'},
                      ],
                      'album': {'name': '国乐大典', 'mid': '003album'},
                      'interval': 200,
                      'pay': {'pay_play': 0},
                    },
                  ],
                },
              ],
            });
            return http.Response.bytes(utf8.encode(payload), 200);
          }),
        );

        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            qqMusicServiceProvider.overrideWithValue(mockService),
          ],
        );
        addTearDown(container.dispose);

        final qqNotifier = container.read(qqMusicFavoritesProvider.notifier);
        await qqNotifier.saveConfigAndSync(
          const QQMusicConfig(dissid: '88888888'),
        );

        final favorites = container.read(favoritesSongsProvider);
        expect(favorites.length, 2);

        // First song is pure online
        expect(favorites[0].title, '晴天');
        expect(favorites[0].isQQMusicOnline, isTrue);
        expect(favorites[0].hasLocalFile, isFalse);

        // Second song matched local file '/music/gaoshan.flac'
        expect(favorites[1].id, 'local-gaoshan');
        expect(favorites[1].hasLocalFile, isTrue);
        expect(favorites[1].filePath, '/music/gaoshan.flac');
        expect(favorites[1].qqSongMid, '002localmatch');
        expect(favorites[1].album, '国乐大典');

        // Local library still only has the 1 local song (not polluted by online tracks)
        final localLibrarySongs = container.read(libraryNotifierProvider).songs;
        expect(localLibrarySongs.length, 1);
        expect(localLibrarySongs.first.id, 'local-gaoshan');
        expect(localLibrarySongs.first.isFavorite, isTrue);
      },
    );

    test(
      'local songs with mismatched metadata are still matched instead of showing an unplayable online duplicate',
      () async {
        // 本地标签写法与 QQ 音乐不同：合唱歌手分隔符、版本后缀、缺歌手标签
        final locals = [
          Song(
            id: 'local-qianli',
            title: '千里之外',
            artist: '周杰伦、费玉清',
            album: '',
            durationMs: 261000,
            filePath: '/music/qianli.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
          Song(
            id: 'local-daoxiang',
            title: '稻香',
            artist: '周杰伦',
            album: '',
            durationMs: 226000,
            filePath: '/music/daoxiang.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
          Song(
            id: 'local-yequ',
            title: '夜曲',
            artist: '未知歌手',
            album: '',
            durationMs: 226000,
            filePath: '/music/yequ.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
        ];

        final remotes = [
          _qqSong('001qianli', '千里之外', '周杰伦/费玉清', 261, id: 1),
          _qqSong('002daoxiang', '稻香 (Live)', '周杰伦', 226, id: 2),
          _qqSong('003yequ', '夜曲', '周杰伦', 226, id: 3),
        ];

        final (merged, _) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
        );

        expect(merged, hasLength(3));
        // 三首都必须落到本地文件上，而不是留下无法播放的在线副本
        expect(merged.every((s) => s.hasLocalFile), isTrue);
        expect(merged.map((s) => s.id), [
          'local-qianli',
          'local-daoxiang',
          'local-yequ',
        ]);
        // 合并后仍带上 QQ 侧标识，便于在线回退与上报
        expect(merged[0].qqSongMid, '001qianli');
        expect(merged[1].qqSongMid, '002daoxiang');
        expect(merged[2].qqSongId, 3);
      },
    );

    test(
      'a local file is claimed by at most one cloud track (no duplicate rows)',
      () async {
        final locals = [
          Song(
            id: 'local-dup',
            title: '稻香',
            artist: '周杰伦',
            album: '',
            durationMs: 226000,
            filePath: '/music/daoxiang.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
        ];
        // 云端出现同一首歌的两个版本（如录音室版与 Live 版）
        final remotes = [
          _qqSong('001studio', '稻香', '周杰伦', 226, id: 1),
          _qqSong('002live', '稻香 (Live)', '周杰伦', 400, id: 2),
        ];

        final (merged, _) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
        );

        expect(merged, hasLength(2));
        // 只有时长吻合的那一条占用本地文件，另一条保持在线副本
        expect(merged.where((s) => s.hasLocalFile).length, 1);
        expect(merged.firstWhere((s) => s.hasLocalFile).id, 'local-dup');
        expect(
          merged.firstWhere((s) => !s.hasLocalFile).qqSongMid,
          '002live',
        );
      },
    );

    test(
      'different songs are not force-matched just because titles are similar',
      () async {
        final locals = [
          Song(
            id: 'local-aiqing',
            title: '爱情',
            artist: '周杰伦',
            album: '',
            durationMs: 250000,
            filePath: '/music/aiqing.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
        ];
        final remotes = [_qqSong('001ai', '爱', '周杰伦', 200, id: 1)];

        final (merged, _) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
        );

        expect(merged, hasLength(1));
        expect(merged.single.hasLocalFile, isFalse);
        expect(merged.single.qqSongMid, '001ai');
      },
    );

    test(
      'manual link overrides a wrong automatic match and survives re-merge',
      () async {
        final locals = [
          Song(
            id: 'local-wrong',
            title: '稻香',
            artist: '周杰伦',
            album: '',
            durationMs: 226000,
            filePath: '/music/wrong.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
          Song(
            id: 'local-right',
            title: '稻香 (2008 现场版)',
            artist: '未知歌手',
            album: '',
            durationMs: 400000,
            filePath: '/music/right.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
        ];
        final remotes = [_qqSong('001daoxiang', '稻香', '周杰伦', 226, id: 1)];

        // 自动匹配会选中时长吻合的 local-wrong
        final (auto, _) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
        );
        expect(auto.single.id, 'local-wrong');

        // 用户手动指定 local-right 后，手动关联优先
        final (manual, _) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
          manualLinks: const {'001daoxiang': 'local-right'},
        );
        expect(manual.single.id, 'local-right');
        expect(manual.single.hasLocalFile, isTrue);
        expect(manual.single.qqSongMid, '001daoxiang');
      },
    );

    test(
      'manual exclusion stops automatic matching for that cloud track',
      () async {
        final locals = [
          Song(
            id: 'local-daoxiang',
            title: '稻香',
            artist: '周杰伦',
            album: '',
            durationMs: 226000,
            filePath: '/music/daoxiang.flac',
            dateAdded: DateTime(2026, 1, 1),
            source: SongSource.local,
          ),
        ];
        final remotes = [_qqSong('001daoxiang', '稻香', '周杰伦', 226, id: 1)];

        final (before, _) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
        );
        expect(before.single.hasLocalFile, isTrue);

        // 用户取消关联后：即使标题歌手完全一致也不再自动接上
        final (after, upgraded) = QQMusicFavoritesNotifier.mergeWithLocalSongs(
          remotes,
          locals,
          manualExclusions: const {'001daoxiang'},
        );
        expect(after.single.hasLocalFile, isFalse);
        expect(after.single.id, 'qq_001daoxiang');
        expect(upgraded, isEmpty);
      },
    );

    test('manual link and exclusion sets round-trip through storage', () async {
      expect(storageService.getQQMusicManualLinks(), isEmpty);
      expect(storageService.getQQMusicManualExclusions(), isEmpty);

      await storageService.saveQQMusicManualLink(
        songMid: '001mid',
        songId: 'local-a',
      );
      expect(storageService.getQQMusicManualLinks(), {'001mid': 'local-a'});

      // 取消关联写入排除集，且移除手动关联
      await storageService.removeQQMusicManualLink('001mid');
      await storageService.addQQMusicManualExclusion('001mid');
      expect(storageService.getQQMusicManualLinks(), isEmpty);
      expect(storageService.getQQMusicManualExclusions(), {'001mid'});

      // 重新关联会清掉排除标记
      await storageService.saveQQMusicManualLink(
        songMid: '001mid',
        songId: 'local-b',
      );
      expect(storageService.getQQMusicManualLinks(), {'001mid': 'local-b'});
      expect(storageService.getQQMusicManualExclusions(), isEmpty);

      // 解绑时一并清空
      await storageService.saveQQMusicConfig(const QQMusicConfig(uin: '123'));
      await storageService.clearQQMusicConfig();
      expect(storageService.getQQMusicManualLinks(), isEmpty);
      expect(storageService.getQQMusicManualExclusions(), isEmpty);
    });

    test(
      'linkLocalSong writes QQ ids onto the local song and unlink clears them',
      () async {
        final local = Song(
          id: 'local-target',
          title: '随便一首本地歌',
          artist: '本地歌手',
          album: '',
          durationMs: 200000,
          filePath: '/music/target.flac',
          dateAdded: DateTime(2026, 1, 1),
          source: SongSource.local,
        );
        await storageService.saveSongs([local]);

        final remote = _qqSong('009link', '云端曲目', '云端歌手', 200, id: 9);

        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            qqMusicServiceProvider.overrideWithValue(
              QQMusicService(
                client: MockClient((request) async => http.Response('{}', 200)),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(qqMusicFavoritesProvider.notifier);
        await notifier.linkLocalSong(remote: remote, local: local);

        // 手动关联已落盘，且本地文件带上了 QQ 标识（可上报播放/拉云端歌词）
        expect(
          storageService.getQQMusicManualLinks(),
          {'009link': 'local-target'},
        );
        final linked = storageService.getSong('local-target')!;
        expect(linked.qqSongMid, '009link');
        expect(linked.qqSongId, 9);
        expect(linked.isFavorite, isTrue);

        await notifier.unlinkLocalSong(linked);
        expect(storageService.getQQMusicManualLinks(), isEmpty);
        expect(storageService.getQQMusicManualExclusions(), {'009link'});
        final unlinked = storageService.getSong('local-target')!;
        expect(unlinked.qqSongMid ?? '', isEmpty);
        expect(unlinked.isFavorite, isFalse);
      },
    );

    test(
      'favorites keep local-only red hearts after binding a QQ account',
      () async {
        final mockService = QQMusicService(
          client: MockClient((request) async {
            final payload = json.encode({
              'code': 0,
              'cdlist': [
                {
                  'dissname': '我喜欢',
                  'nickname': '测试用户',
                  'total_song_num': 1,
                  'songlist': [
                    {
                      'mid': '001online',
                      'id': 2001,
                      'title': '晴天',
                      'singer': [
                        {'name': '周杰伦'},
                      ],
                      'album': {'name': '叶惠美', 'mid': '002album'},
                      'interval': 269,
                    },
                  ],
                },
              ],
            });
            return http.Response.bytes(utf8.encode(payload), 200);
          }),
        );

        // 绑定前就在本地标了红心、但不在 QQ 歌单里的歌
        final localOnlyFavorite = Song(
          id: 'local-only-fav',
          title: '本地私藏',
          artist: '独立音乐人',
          album: '',
          durationMs: 180000,
          filePath: '/music/private.flac',
          dateAdded: DateTime(2026, 1, 1),
          isFavorite: true,
          source: SongSource.local,
        );
        await storageService.saveSongs([localMatchedSong, localOnlyFavorite]);

        final container = ProviderContainer(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            qqMusicServiceProvider.overrideWithValue(mockService),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(qqMusicFavoritesProvider.notifier)
            .saveConfigAndSync(const QQMusicConfig(dissid: '88888888'));

        final favorites = container.read(favoritesSongsProvider);
        expect(favorites.map((s) => s.id), contains('qq_001online'));
        expect(favorites.map((s) => s.id), contains('local-only-fav'));
      },
    );
  });
}

/// 构造一条 QQ 音乐侧的在线曲目（interval 为秒）。
Song _qqSong(String mid, String title, String artist, int intervalSec, {required int id}) =>
    Song(
      id: 'qq_$mid',
      title: title,
      artist: artist,
      album: '',
      durationMs: intervalSec * 1000,
      filePath: 'qqmusic://$mid',
      dateAdded: DateTime(2026, 1, 1),
      source: SongSource.online,
      qqSongMid: mid,
      qqSongId: id,
      qqMediaMid: mid,
    );
