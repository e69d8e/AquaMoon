import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aquamoon/models/qq_music_discovery.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/services/qq_music_discovery_service.dart';

MockClient _client(
  Map<String, Object> Function(http.Request request) respond,
) {
  return MockClient((request) async {
    final body = respond(request);
    return http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

String _path(http.Request request) => request.url.path;

void main() {
  group('QQ 音乐分享链接解析', () {
    test('解析歌单链接与纯数字 ID', () {
      final fromPath = QQMusicDiscoveryService.parseShareInput(
        'https://y.qq.com/n/ryqq/playlist/8825279434',
      );
      expect(fromPath, isNotNull);
      expect(fromPath!.kind, QQMusicCollectionKind.playlist);
      expect(fromPath.id, '8825279434');

      final fromQuery = QQMusicDiscoveryService.parseShareInput(
        'https://i2.y.qq.com/n3/other/pages/details/playlist.html?id=734191243',
      );
      expect(fromQuery!.id, '734191243');

      final fromDisstid = QQMusicDiscoveryService.parseShareInput(
        'https://i.y.qq.com/n3/other/pages/details/playlist.html?disstid=734191243&foo=bar',
      );
      expect(fromDisstid!.id, '734191243');

      expect(
        QQMusicDiscoveryService.extractPlaylistId('dissid:1234567890'),
        '1234567890',
      );
    });

    test('解析专辑链接，拒绝单曲链接与非法 ID', () {
      final album = QQMusicDiscoveryService.parseShareInput(
        'https://y.qq.com/n/ryqq/albumDetail/002Neh8l1pRDIP',
      );
      expect(album!.kind, QQMusicCollectionKind.album);
      expect(album.id, '002Neh8l1pRDIP');

      expect(
        QQMusicDiscoveryService.parseShareInput(
          'https://y.qq.com/n/ryqq/songDetail/001abc',
        ),
        isNull,
      );
      expect(
        QQMusicDiscoveryService.extractPlaylistId('playlist.html?id=abc'),
        isNull,
      );
      expect(QQMusicDiscoveryService.parseShareInput('周杰伦'), isNull);
    });

    test('解析单曲分享链接的 songMid', () {
      expect(
        QQMusicDiscoveryService.parseSongMid(
          'https://y.qq.com/n/ryqq/songDetail/0039MnYb0qxYhV',
        ),
        '0039MnYb0qxYhV',
      );
      expect(
        QQMusicDiscoveryService.parseSongMid(
          'https://y.qq.com/n/ryqq/songDetail/0039MnYb0qxYhV?songmid=002abc',
        ),
        '0039MnYb0qxYhV',
      );
      expect(QQMusicDiscoveryService.parseSongMid('青花瓷'), isNull);
    });
  });

  group('QQMusicDiscoveryService 网络解析', () {
    test('单曲搜索走 search_for_qq_cp 并产出可播放在线 Song', () async {
      final service = QQMusicDiscoveryService(
        client: _client((request) {
          if (_path(request).contains('search_for_qq_cp')) {
            return <String, Object>{
              'code': 0,
              'data': <String, Object>{
                'song': <String, Object>{
                  'list': <Object>[
                    <String, Object>{
                      'songid': 123456,
                      'songmid': '001abc',
                      'songname': '青花瓷',
                      'albumname': '我很忙',
                      'albummid': '000MkMni19ClKG4',
                      'interval': 239,
                      'singer': <Object>[
                        <String, Object>{'name': '周杰伦'},
                      ],
                      'pay': <String, Object>{'payplay': 0},
                    },
                  ],
                },
              },
            };
          }
          return <String, Object>{'code': 0};
        }),
      );
      addTearDown(service.dispose);

      final songs = await service.searchSongs('青花瓷');
      expect(songs, hasLength(1));
      final song = songs.first;
      expect(song.id, 'qq_001abc');
      expect(song.title, '青花瓷');
      expect(song.artist, '周杰伦');
      expect(song.album, '我很忙');
      expect(song.durationMs, 239000);
      expect(song.filePath, 'qqmusic://001abc');
      expect(song.source, SongSource.online);
      expect(song.qqSongMid, '001abc');
      expect(song.qqSongId, 123456);
      expect(song.qqMediaMid, '001abc');
      expect(song.isVip, isFalse);
      expect(song.isQQMusicOnline, isTrue);
      expect(song.albumArtUri, contains('T002R800x800M000000MkMni19ClKG4.jpg'));
    });

    test('旧搜索端点空结果时回退 desktop musicu.fcg', () async {
      final service = QQMusicDiscoveryService(
        client: _client((request) {
          if (_path(request).contains('musicu.fcg')) {
            return <String, Object>{
              'code': 0,
              'req': <String, Object>{
                'code': 0,
                'data': <String, Object>{
                  'body': <String, Object>{
                    'song': <String, Object>{
                      'list': <Object>[
                        <String, Object>{
                          'id': 777,
                          'mid': '002xyz',
                          'name': '稻香',
                          'interval': 223,
                          'singer': <Object>[
                            <String, Object>{'name': '周杰伦'},
                          ],
                          'album': <String, Object>{
                            'name': '魔杰座',
                            'mid': '003album',
                          },
                          'file': <String, Object>{'media_mid': '004media'},
                          'pay': <String, Object>{'pay_play': 1},
                        },
                      ],
                    },
                  },
                },
              },
            };
          }
          return <String, Object>{
            'code': 0,
            'data': <String, Object>{'song': <String, Object>{'list': <Object>[]}},
          };
        }),
      );
      addTearDown(service.dispose);

      final songs = await service.searchSongs('稻香');
      expect(songs, hasLength(1));
      expect(songs.first.qqSongMid, '002xyz');
      expect(songs.first.qqMediaMid, '004media');
      expect(songs.first.isVip, isTrue);
      expect(songs.first.albumArtUri, contains('003album'));
    });

    test('推荐歌单与分类解析', () async {
      final service = QQMusicDiscoveryService(
        client: _client((request) {
          final path = _path(request);
          if (path.contains('fcg_get_diss_tag_conf')) {
            return <String, Object>{
              'code': 0,
              'data': <String, Object>{
                'categories': <Object>[
                  <String, Object>{
                    'categoryGroupName': '语种',
                    'items': <Object>[
                      <String, Object>{
                        'categoryId': 1,
                        'categoryName': '华语',
                        'usable': 1,
                      },
                      <String, Object>{
                        'categoryId': 2,
                        'categoryName': '隐藏',
                        'usable': 0,
                      },
                    ],
                  },
                ],
              },
            };
          }
          if (path.contains('musicu.fcg')) {
            return <String, Object>{
              'code': 0,
              'recomPlaylist': <String, Object>{
                'code': 0,
                'data': <String, Object>{
                  'v_hot': <Object>[
                    <String, Object>{
                      'content_id': 8825279434,
                      'title': '国风精选',
                      'cover': 'http://y.gtimg.cn/music/photo/a.jpg',
                      'song_cnt': 30,
                      'listen_num': 12345,
                      'username': '水月音',
                    },
                  ],
                },
              },
            };
          }
          return <String, Object>{'code': 0};
        }),
      );
      addTearDown(service.dispose);

      final recommended = await service.fetchRecommendedPlaylists();
      expect(recommended, hasLength(1));
      expect(recommended.first.id, '8825279434');
      expect(recommended.first.title, '国风精选');
      expect(recommended.first.kind, QQMusicCollectionKind.playlist);
      expect(recommended.first.coverUrl, startsWith('https://'));
      expect(recommended.first.badge, '推荐');

      final categories = await service.fetchPlaylistCategories();
      expect(categories.first.name, '全部');
      expect(categories.any((item) => item.name == '华语'), isTrue);
      expect(categories.any((item) => item.name == '隐藏'), isFalse);
    });

    test('榜单目录与榜单歌曲解析', () async {
      final service = QQMusicDiscoveryService(
        client: _client((request) {
          final path = _path(request);
          if (path.contains('fcg_v8_toplist_cp')) {
            return <String, Object>{
              'code': 0,
              'songlist': <Object>[
                <String, Object>{
                  'cur_count': '1',
                  'data': <String, Object>{
                    'songid': 999,
                    'songmid': '003top',
                    'songname': '起风了',
                    'albumname': '起风了',
                    'albummid': '005album',
                    'interval': 325,
                    'strMediaMid': '006media',
                    'singer': <Object>[
                      <String, Object>{'name': '买辣椒也用券'},
                    ],
                    'pay': <String, Object>{'payplay': 0},
                  },
                },
              ],
            };
          }
          if (path.contains('musicu.fcg')) {
            return <String, Object>{
              'code': 0,
              'topList': <String, Object>{
                'code': 0,
                'data': <String, Object>{
                  'group': <Object>[
                    <String, Object>{
                      'groupName': '内地',
                      'toplist': <Object>[
                        <String, Object>{
                          'topId': 26,
                          'title': '热歌榜',
                          'totalNum': 100,
                          'intro': '每周<br>更新',
                          'frontPicUrl': 'http://y.gtimg.cn/a.jpg',
                        },
                        <String, Object>{
                          'topId': 99,
                          'title': 'MV 榜',
                          'recType': 10010,
                        },
                      ],
                    },
                  ],
                },
              },
            };
          }
          return <String, Object>{'code': 0};
        }),
      );
      addTearDown(service.dispose);

      final charts = await service.fetchCharts();
      expect(charts, hasLength(1));
      expect(charts.first.id, '26');
      expect(charts.first.kind, QQMusicCollectionKind.chart);
      expect(charts.first.description, '每周 更新');
      expect(charts.first.coverUrl, startsWith('https://'));

      final songs = await service.fetchChartSongs('26');
      expect(songs, hasLength(1));
      expect(songs.first.qqSongMid, '003top');
      expect(songs.first.qqMediaMid, '006media');
      expect(songs.first.trackNumber, 1);
    });

    test('歌单详情解析 cdlist 并保留 VIP 标记', () async {
      final service = QQMusicDiscoveryService(
        client: _client((request) {
          if (_path(request).contains('getcdinfo')) {
            return <String, Object>{
              'code': 0,
              'subcode': 0,
              'cdlist': <Object>[
                <String, Object>{
                  'dissname': '水墨国风',
                  'logo': 'http://y.gtimg.cn/cover.jpg',
                  'nickname': '水月音',
                  'desc': '测试',
                  'songnum': 1,
                  'songlist': <Object>[
                    <String, Object>{
                      'songid': 555,
                      'songmid': '004qq',
                      'songname': '兰亭序',
                      'albumname': '魔杰座',
                      'albummid': '007album',
                      'interval': 260,
                      'singer': <Object>[
                        <String, Object>{'name': '周杰伦'},
                      ],
                      'pay': <String, Object>{'payplay': 1},
                    },
                  ],
                },
              ],
            };
          }
          return <String, Object>{'code': 0};
        }),
      );
      addTearDown(service.dispose);

      const collection = QQMusicCollection(
        id: '8899001122',
        kind: QQMusicCollectionKind.playlist,
        title: 'QQ 音乐歌单',
      );
      final detail = await service.fetchCollectionDetail(collection);
      expect(detail, isNotNull);
      expect(detail!.collection.title, '水墨国风');
      expect(detail.collection.songCount, 1);
      expect(detail.songs, hasLength(1));
      expect(detail.songs.first.title, '兰亭序');
      expect(detail.songs.first.isVip, isTrue);
      expect(detail.songs.first.isQQMusicOnline, isTrue);
    });

    test('专辑详情按 begin/num 分页并解析 songInfo', () async {
      var calls = 0;
      final service = QQMusicDiscoveryService(
        client: _client((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final album = body['album'] as Map<String, dynamic>;
          if (album['method'] == 'GetAlbumDetail') {
            return <String, Object>{
              'code': 0,
              'album': <String, Object>{
                'code': 0,
                'data': <String, Object>{
                  'basicInfo': <String, Object>{
                    'albumName': '范特西',
                    'desc': '经典',
                  },
                  'singer': <String, Object>{
                    'singerList': <Object>[
                      <String, Object>{'name': '周杰伦'},
                    ],
                  },
                },
              },
            };
          }
          final param = album['param'] as Map<String, dynamic>;
          final begin = param['begin'] as int;
          calls++;
          if (begin > 0) {
            return <String, Object>{
              'code': 0,
              'album': <String, Object>{
                'code': 0,
                'data': <String, Object>{'totalNum': 1, 'songList': <Object>[]},
              },
            };
          }
          return <String, Object>{
            'code': 0,
            'album': <String, Object>{
              'code': 0,
              'data': <String, Object>{
                'totalNum': 1,
                'songList': <Object>[
                  <String, Object>{
                    'songInfo': <String, Object>{
                      'id': 888,
                      'mid': '005albumSong',
                      'name': '爱在西元前',
                      'interval': 233,
                      'singer': <Object>[
                        <String, Object>{'name': '周杰伦'},
                      ],
                      'album': <String, Object>{
                        'name': '范特西',
                        'mid': '008album',
                      },
                      'file': <String, Object>{'media_mid': '009media'},
                      'pay': <String, Object>{'pay_play': 0},
                    },
                  },
                ],
              },
            },
          };
        }),
      );
      addTearDown(service.dispose);

      const collection = QQMusicCollection(
        id: '008album',
        kind: QQMusicCollectionKind.album,
        title: 'QQ 音乐专辑',
      );
      final detail = await service.fetchCollectionDetail(collection);
      expect(detail, isNotNull);
      expect(detail!.collection.title, '范特西');
      expect(detail.collection.subtitle, '周杰伦');
      expect(detail.songs, hasLength(1));
      expect(detail.songs.first.qqSongMid, '005albumSong');
      expect(detail.songs.first.qqMediaMid, '009media');
      expect(calls, 1);
    });

    test('JSONP 外壳的歌单搜索可被解析', () async {
      final client = MockClient((request) async {
        final payload = jsonEncode(<String, Object>{
          'code': 0,
          'data': <String, Object>{
            'list': <Object>[
              <String, Object>{
                'dissid': '734191243',
                'dissname': '禅意纯音',
                'imgurl': 'https://y.gtimg.cn/x.jpg',
                'song_count': 12,
                'listennum': 3456,
                'creator': <String, Object>{'name': '水月音'},
              },
            ],
          },
        });
        return http.Response.bytes(
          utf8.encode('MusicJsonCallback($payload)'),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final service = QQMusicDiscoveryService(client: client);
      addTearDown(service.dispose);

      final results = await service.searchPlaylists('禅意');
      expect(results, hasLength(1));
      expect(results.first.id, '734191243');
      expect(results.first.title, '禅意纯音');
      expect(results.first.songCount, 12);
      expect(results.first.subtitle, contains('12 首'));
    });
  });
}
