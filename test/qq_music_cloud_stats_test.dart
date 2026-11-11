import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aquamoon/models/listening_stats.dart';
import 'package:aquamoon/models/qq_music_config.dart';
import 'package:aquamoon/models/song.dart';
import 'package:aquamoon/services/qq_music_service.dart';
import 'package:aquamoon/services/storage_service.dart';

/// 回放从真实 QQ 音乐账号抓取的响应（test/fixtures/qq_*.json），
/// 锁定云端统计接口的请求形状与字段解析，避免再退回已失效的接口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = QQMusicConfig(
    uin: '12345678',
    cookie: 'uin=12345678; qm_keyst=testkey;',
  );

  String fixture(String name) =>
      File('test/fixtures/$name').readAsStringSync();

  group('QQ Music cloud stats against captured response shapes', () {
    test('parses listenCnt and lastTime from GetPlayRecentlyInfo', () async {
      final raw = fixture('qq_play_recently.json');
      final client = MockClient((request) async {
        // 必须是 PC 私有通道 + module.method 请求键
        expect(request.url.host, 'u6.y.qq.com');
        final body = json.decode(request.body) as Map;
        expect(
          body.keys,
          contains(
            'music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo',
          ),
        );
        expect(
          request.headers['Content-Type'],
          'application/x-www-form-urlencoded',
        );
        // 私有通道需要登录 Cookie
        expect(request.headers['Cookie'], contains('qm_keyst='));
        return http.Response.bytes(utf8.encode(raw), 200);
      });

      final service = QQMusicService(
        client: client,
        desktopGuid: '0123456789ABCDEF0123456789ABCDEF',
      );
      final history = await service.fetchCloudListeningHistory(config);

      expect(history, hasLength(3));

      final first = history.first;
      expect(first.song.qqSongMid, '00SAMPLE100000');
      expect(first.song.qqSongId, 1000001);
      expect(first.song.title, '示例曲目A');
      expect(first.song.artist, '示例歌手甲');
      expect(first.song.album, '示例专辑一');
      expect(first.song.durationMs, 246000);
      // listenCnt 是云端累计次数，必须原样落到 Song.playCount
      expect(first.playCount, 2);
      expect(first.song.isVip, isTrue);
      expect(
        first.lastPlayedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000067 * 1000),
      );

      // 多歌手曲目按 / 拼接，且非 VIP 曲目 isVip 为 false
      final third = history[2];
      expect(third.song.artist, '示例歌手丙/示例歌手丁');
      expect(third.song.isVip, isFalse);
      expect(third.playCount, 4);

      // 每首曲目都带数字 songId（写回本地后上报才可用）
      expect(history.every((e) => (e.song.qqSongId ?? 0) > 0), isTrue);
      // lastTime 解析成真实时间而非 1970
      expect(history.every((e) => e.lastPlayedAt!.year > 2000), isTrue);
    });

    test('reads todayLT from the captured SoundPower response', () async {
      final raw = fixture('qq_sound_power.json');
      final client = MockClient((request) async {
        final body = json.decode(request.body) as Map;
        expect(
          body['req_0']['module'],
          'music.soundPower.SoundPowerSvr',
        );
        expect(body['req_0']['method'], 'QueryLevelDetailPage');
        expect(body['comm']['uin'], '12345678');
        return http.Response.bytes(utf8.encode(raw), 200);
      });

      final service = QQMusicService(client: client);
      final seconds = await service.fetchTodayListenSeconds(config);

      // 抓取时刻该账号今日有效听歌时长为 0 秒（当天尚未听歌），
      // 关键是不能把 0 当成失败、也不能返回 null。
      expect(seconds, 0);
    });

    test('rejects responses whose envelope code is non-zero', () async {
      final client = MockClient((request) async {
        // 未登录时真实返回 shape：外层 code=0，请求业务 code=1000
        final payload = json.encode({
          'code': 0,
          'music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo': {
            'code': 1000,
          },
        });
        return http.Response.bytes(utf8.encode(payload), 200);
      });

      final service = QQMusicService(client: client);
      final history = await service.fetchCloudListeningHistory(config);
      expect(history, isEmpty);
    });

    test('parses non-zero todayLT when the account listened today', () async {
      final client = MockClient((request) async {
        final payload = json.encode({
          'code': 0,
          'req_0': {
            'code': 0,
            'data': {'todayLT': 1830},
          },
        });
        return http.Response.bytes(utf8.encode(payload), 200);
      });

      final service = QQMusicService(client: client);
      expect(await service.fetchTodayListenSeconds(config), 1830);
    });
  });

  group('merged cloud data feeds per-song play counts and today duration', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('qq_cloud_stats_');
      storage = StorageService();
      await storage.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    QQMusicService replayingClient() => QQMusicService(
      client: MockClient((request) async {
        if (request.url.host == 'u6.y.qq.com') {
          return http.Response.bytes(
            utf8.encode(fixture('qq_play_recently.json')),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(fixture('qq_sound_power.json')),
          200,
        );
      }),
      desktopGuid: '0123456789ABCDEF0123456789ABCDEF',
    );

    test(
      'cloud listenCnt reaches Song.playCount and only today listen time enters daily stats',
      () async {
        final service = replayingClient();
        final history = await service.fetchCloudListeningHistory(config);
        final todaySeconds = await service.fetchTodayListenSeconds(config);

        expect(history, hasLength(3));
        expect(todaySeconds, 0);

        // 「我喜欢」缓存里已有这三首（同步收藏得到），次数初始为 0。
        await storage.saveQQMusicFavoritesCache([
          for (final e in history) e.song.copyWith(playCount: 0),
        ]);

        final refDate = DateTime(2026, 11, 12, 20, 0);
        final updated = await storage.mergeQQMusicCloudListeningSongs(
          history,
          timestamp: refDate,
          todayListenSeconds: todaySeconds,
        );
        expect(updated, 3);

        // 1) 每首曲目的云端播放次数已写回缓存（song_tile 的次数徽标来源）。
        final cache = storage.getQQMusicFavoritesCache();
        final countsByMid = {
          for (final s in cache) s.qqSongMid: s.playCount,
        };
        expect(countsByMid['00SAMPLE100000'], 2);
        expect(countsByMid['00SAMPLE200000'], 1);
        expect(countsByMid['00SAMPLE300000'], 4);

        // 2) todayLT 为 0 时不得凭空造出今日时长。
        final record = storage.getDailyListeningRecord('2026-11-12');
        expect(record.totalDurationSeconds, 0);
        expect(record.songDurationSeconds, isEmpty);
        // lastTime 不是今天的曲目也不能被当成今天播放过
        expect(record.songPlayCounts, isEmpty);

        // 3) 摘要暴露云端累计次数与今日时长。
        final summary = storage.getQQMusicCloudStatsSummary();
        expect(summary.importedSongCount, 3);
        expect(summary.importedPlayCount, 7);
        expect(summary.todayListenSeconds, 0);

        // 4) 重复同步完全幂等。
        final again = await storage.mergeQQMusicCloudListeningSongs(
          history,
          timestamp: refDate,
          todayListenSeconds: todaySeconds,
        );
        expect(again, 0);
        expect(
          storage.getDailyListeningRecord('2026-11-12').totalDurationSeconds,
          0,
        );
      },
    );

    test(
      'matched local songs receive cloud playCount and the missing qqSongId',
      () async {
        final service = replayingClient();
        final history = await service.fetchCloudListeningHistory(config);

        // 本地曲库已有同名曲目，且此前只关联了 mid、缺数字 songId。
        final local = Song(
          id: 'local-sample-a',
          title: '示例曲目A',
          artist: '示例歌手甲',
          album: '',
          durationMs: 246000,
          filePath: '/music/sample_a.flac',
          dateAdded: DateTime(2026, 1, 1),
          source: SongSource.local,
          qqSongMid: '00SAMPLE100000',
        );
        await storage.saveSong(local);

        await storage.mergeQQMusicCloudListeningSongs(
          history,
          timestamp: DateTime(2026, 11, 12, 20, 0),
        );

        final stored = storage.getSong('local-sample-a')!;
        // 云端累计次数写回本地 playCount，缺失的数字 songId 一并补齐，
        // 之后播放时才能成功上报到云端。
        expect(stored.playCount, 2);
        expect(stored.qqSongId, 1000001);
      },
    );

    test(
      're-sync backfills missing play counts for legacy inconsistent daily records',
      () async {
        final refDate = DateTime(2026, 11, 12, 20, 0);

        // 先跑一次同步，把「今日时长基准」写成 1545（此后 delta 为 0）
        await storage.mergeQQMusicCloudListeningSongs(
          [],
          timestamp: refDate,
          todayListenSeconds: 1545,
        );

        // 再复现修复前的持久化状态：当天已有云端分摊时长，但 songPlayCounts 为空，
        // 于是「收听曲目 N 首」与「播放次数 0 次」自相矛盾。
        await storage.saveDailyListeningRecord(
          const DailyListeningRecord(
            dateStr: '2026-11-12',
            totalDurationSeconds: 1545,
            songDurationSeconds: {'qq_00SAMPLE100000': 1545},
            songPlayCounts: {},
            hourlyDurationSeconds: {20: 1545},
          ),
        );

        final service = replayingClient();
        final history = await service.fetchCloudListeningHistory(config);
        final todayEntries = <QQMusicCloudHistoryEntry>[
          for (final e in history.take(1))
            QQMusicCloudHistoryEntry(
              song: e.song,
              lastPlayedAt: DateTime(2026, 11, 12, 18, 0),
            ),
        ];

        await storage.mergeQQMusicCloudListeningSongs(
          todayEntries,
          timestamp: DateTime(2026, 11, 12, 20, 30),
          todayListenSeconds: 1545,
        );

        final fixed = storage.getDailyListeningRecord('2026-11-12');
        // delta 为 0：时长不得再增长
        expect(fixed.totalDurationSeconds, 1545);
        expect(fixed.songDurationSeconds['qq_00SAMPLE100000'], 1545);
        // 但缺失的播放次数要补上，统计恢复自洽
        expect(fixed.songPlayCounts['qq_00SAMPLE100000'], 1);

        // 再次同步仍然幂等
        await storage.mergeQQMusicCloudListeningSongs(
          todayEntries,
          timestamp: DateTime(2026, 11, 12, 21, 0),
          todayListenSeconds: 1545,
        );
        final again = storage.getDailyListeningRecord('2026-11-12');
        expect(again.songPlayCounts['qq_00SAMPLE100000'], 1);
        expect(again.totalDurationSeconds, 1545);
      },
    );

    test(
      'today listen seconds are imported incrementally and spread across today plays',
      () async {
        final service = replayingClient();
        final history = await service.fetchCloudListeningHistory(config);
        final refDate = DateTime(2026, 11, 12, 20, 0);

        // 把前两条记录的播放时间标成「今天」，模拟当天在云端听过的曲目。
        final today = <QQMusicCloudHistoryEntry>[
          for (final e in history)
            QQMusicCloudHistoryEntry(
              song: e.song,
              lastPlayedAt: DateTime(2026, 11, 12, 18, 30),
            ),
        ];

        await storage.mergeQQMusicCloudListeningSongs(
          today.take(2).toList(),
          timestamp: refDate,
          todayListenSeconds: 1800,
        );
        final r1 = storage.getDailyListeningRecord('2026-11-12');
        expect(r1.totalDurationSeconds, 1800);
        // 今日时长按当天听过的曲目分摊。
        expect(r1.songDurationSeconds['qq_00SAMPLE100000'], 900);
        expect(r1.songDurationSeconds['qq_00SAMPLE200000'], 900);
        expect(r1.hourlyDurationSeconds[20], 1800);

        // 关键不变量：被计入「收听曲目」的每首歌至少要有 1 次播放，
        // 否则会出现「收听曲目 19 首 / 播放次数 8 次」这种自相矛盾的统计。
        expect(r1.songPlayCounts['qq_00SAMPLE100000'], 1);
        expect(r1.songPlayCounts['qq_00SAMPLE200000'], 1);
        expect(
          r1.songDurationSeconds.keys.toSet(),
          r1.songPlayCounts.keys.toSet(),
        );

        // 云端时长增长到 2400 秒：只补 600 秒差值，不重复累加。
        await storage.mergeQQMusicCloudListeningSongs(
          today.take(2).toList(),
          timestamp: refDate,
          todayListenSeconds: 2400,
        );
        final r2 = storage.getDailyListeningRecord('2026-11-12');
        expect(r2.totalDurationSeconds, 2400);
        expect(r2.songDurationSeconds['qq_00SAMPLE100000'], 1200);
        // 播放次数仍为 1，不因时长增量而重复计数。
        expect(r2.songPlayCounts['qq_00SAMPLE100000'], 1);
        expect(r2.songPlayCounts['qq_00SAMPLE200000'], 1);

        expect(
          storage.getQQMusicCloudStatsSummary().todayListenSeconds,
          2400,
        );

        // 跨日不再影响前一天：新的一天从 0 重新累计。
        await storage.mergeQQMusicCloudListeningSongs(
          today.take(1).toList(),
          timestamp: DateTime(2026, 11, 13, 9, 0),
          todayListenSeconds: 300,
        );
        expect(
          storage.getDailyListeningRecord('2026-11-13').totalDurationSeconds,
          300,
        );
        expect(
          storage.getDailyListeningRecord('2026-11-12').totalDurationSeconds,
          2400,
        );
      },
    );
  });
}
