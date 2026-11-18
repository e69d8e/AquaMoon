# QQ 音乐「发现 / 即点即播」协议参考

本文件记录 AquaMoon 中 QQ 音乐发现功能所复刻的 HTTP 协议，来源为开源项目
[guohuiyuan/go-music-dl](https://github.com/guohuiyuan/go-music-dl)（AGPL-3.0）及其核心库
[guohuiyuan/music-lib](https://github.com/guohuiyuan/music-lib) 的 `qq/` 包。
AquaMoon 未复制其 Go 源码，仅按公开接口协议用纯 Dart 重新实现；保留出处以表致谢。
协议可能随 QQ 音乐服务端调整而失效，代码内均做了多端点回退与容错。

## 通用请求约定

- 搜索类 `c.y.qq.com` 用 iPhone UA：`Mozilla/5.0 (iPhone; CPU iPhone OS 9_1 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13B143 Safari/601.1`；`Referer: http://m.y.qq.com`。
- 桌面 `musicu.fcg` 用 Windows/Chrome UA；`Referer: https://y.qq.com/`；`Content-Type: application/json`。
- 所有请求透传用户配置的 `Cookie`（VIP / 无损档位的前提）。
- music-lib 会随机注入 `X-Forwarded-For` / `X-Real-IP`（国内 IP），AquaMoon 不伪造来源 IP，
  仅保留必要的 UA / Referer / Cookie。
- 响应可能是 JSONP（歌单搜索、歌单详情），需剥掉 `xxx(...)` 外壳。

## 关键词搜索单曲

`GET https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp?w=<kw>&format=json&p=<page>&n=<size>`

响应 `data.song.list[]`：`songid`(int)、`songname`、`songmid`、`albumname`、`albummid`、
`interval`(秒)、`size128` / `size320` / `sizeflac`、`singer[].name`、`pay.payplay`。
`pay.payplay == 1` 表示 VIP 付费专属。封面：
`https://y.gtimg.cn/music/photo_new/T002R300x300M000<albummid>.jpg`（AquaMoon 用 800x800）。

备用（本项目既有、当前仍可用）：
`POST https://u.y.qq.com/cgi-bin/musicu.fcg`，body
`{"comm":{"ct":19,"cv":1859,"uin":0,"format":"json"},"req":{"module":"music.search.SearchCgiService","method":"DoSearchForQQMusicDesktop","param":{"search_type":0,"query":"<kw>","page_num":1,"num_per_page":20}}}`
→ `req.data.body.song.list[]`，字段 `mid` / `id` / `name` / `singer[].name` / `album.name` / `album.mid` / `interval` / `file.media_mid` / `pay.pay_play`。

## 单曲详情 / 链接解析

`GET https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg?songmid=<mid>&format=json`
→ `data[].{id, name, mid, album.{name,mid}, singer[].name, interval}`。
分享链接正则：`songDetail/(\w+)`、`[?&]songmid=([A-Za-z0-9]+)`、`[?&]songid=(\d+)`。
`core.DetectSource` 仅判 `contains('qq.com')`。

## 取流 vkey 与音质

`POST https://u.y.qq.com/cgi-bin/musicu.fcg`，`Referer: http://y.qq.com`：
```json
{"comm":{"cv":4747474,"ct":24,"format":"json","platform":"yqq.json","needNewCode":1,"uin":0},
 "req_1":{"module":"music.vkey.GetVkey","method":"UrlGetVkey",
          "param":{"guid":"<10位随机数字>","songmid":["<mid>"],"songtype":[0],
                   "uin":"0","loginflag":1,"platform":"20",
                   "filename":["<prefix><mid><mid>.<ext>"]}}}
```
响应 `req_1.data.midurlinfo[].purl`，拼 `https://ws.stream.qqmusic.qq.com/` + purl。
AquaMoon 既有实现用 `req_0` / `CgiGetVkey`，并支持 `sip` 数组，故保留为回退链路。

**音质档位（music-lib `qqQualityCandidates`，从高到低）**：

| prefix | ext | 名称 | 需 Cookie |
|---|---|---|---|
| `AI00` | flac | 臻品母带 | 是 |
| `Q001` | flac | 全景声 5.1 | 是 |
| `Q000` | flac | 全景声 2.0 | 是 |
| `F000` | flac | 无损音质 | 是 |
| `O801` | ogg | 超高品质 640K | 是 |
| `M800` | mp3 | 高品质 320K | 否 |
| `M500` | mp3 | 标准 128K | 否 |

music-lib 的文件名是 `prefix + songMID + songMID + "." + ext`（`qualityFilename` 逐字）；
AquaMoon 同时尝试经典形式 `prefix + <media_mid|song_mid> + "." + ext`，并保留既有
`M800/M500/C400` 回退链，兼容两种服务端行为。

`gtk33` 初值 5381（DJB2 `h += (h<<5)+c`，`& 0x7fffffff`）；`hash33` 初值 0。
music-lib 中除登录外所有 `g_tk` 硬编码 `5381`。

## 歌单

- 推荐：`POST https://u.y.qq.com/cgi-bin/musicu.fcg`
  `{"comm":{"ct":24},"recomPlaylist":{"method":"get_hot_recommend","module":"playlist.HotRecommendServer","param":{"async":1,"cmd":2}}}`
  → `recomPlaylist.data.v_hot[].{content_id, title, cover, listen_num, song_cnt, song_count, username}`。
- 分类：`GET https://c.y.qq.com/splcloud/fcgi-bin/fcg_get_diss_tag_conf.fcg?format=json&inCharset=utf8&outCharset=utf-8`
  → `data.categories[].{categoryGroupName, items[].{categoryId, categoryName, usable}}`。
- 分类歌单：`GET https://c.y.qq.com/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg?picmid=1&rnd=0.1&g_tk=5381&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0&categoryId=<id>&sortId=5&sin=<offset>&ein=<offset+limit-1>`
  → `data.list[].{dissid, dissname, imgurl, introduction, listennum, song_count, song_num, creator.name}`。
- 搜索：`GET https://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist?query=<kw>&page_no=0&num_per_page=20&format=json&remoteplace=txt.yqq.playlist&flag_qc=0`（JSONP）
  → `data.list[].{dissid, dissname, imgurl, song_count, listennum, creator.name}`。
- 详情（主）：`GET https://i.y.qq.com/qzone-music/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&disstid=<id>&format=json&g_tk=5381&loginUin=0&hostUin=0&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0`
  备用 `https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg` 与
  `https://c.y.qq.com/qzone/fcgi-bin/fcg_ucc_getcdinfo_byids_cp.fcg`。
  → `cdlist[0].{dissname, logo, nickname, desc, visitnum, songnum, songlist[]}`；
  曲目 `{songid, songname, songmid, albumname, albummid, interval, size128, size320, sizeflac, pay.payplay, singer[].name}`。
- 链接解析：path 含 `playlist` 时取下一段纯数字；或 query `id` / `disstid` / `dissid` 的纯数字值；
  正则 `(?:^|/)playlist/(\d+)(?:[/?#]|$)`。

## 专辑

- 搜索：`GET https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp?format=json&p=1&n=10&w=<kw>&t=8`
  → `data.album.list[].{albumID, albumMID, albumName, publicTime, singerName}`。
- 详情：`POST https://u.y.qq.com/cgi-bin/musicu.fcg`
  `{"comm":{"ct":24,"cv":0},"album":{"module":"music.musichallAlbum.AlbumInfoServer","method":"GetAlbumDetail","param":{"albumMid":"<mid>"}}}`
  → `album.data.basicInfo.{albumID, albumMid, albumName, publishDate, desc}`、`album.data.singer.singerList[].name`。
- 曲目：`{"album":{"module":"music.musichallAlbum.AlbumSongList","method":"GetAlbumSongList","param":{"albumMid":"<mid>","begin":0,"num":100,"order":2}}}`
  → `album.data.totalNum`、`album.data.songList[].songInfo.{mid, name, interval, singer[].name, album.{id,mid,name}, file.{size_128mp3,size_320mp3,size_flac}, pay.pay_play}`；`begin` 每页 +100。
- 链接解析：`albumDetail/([A-Za-z0-9]+)`、`album/([A-Za-z0-9]+)`、`albummid=([A-Za-z0-9]+)`。

## 排行榜

- 目录（**GET**）：`https://u.y.qq.com/cgi-bin/musicu.fcg?format=json&data=<urlencode(payload)>`，
  payload `{"comm":{"cv":4747474,"ct":24,"format":"json","inCharset":"utf-8","outCharset":"utf-8","notice":0,"platform":"yqq.json","needNewCode":1,"uin":"0","g_tk_new_20200303":5381,"g_tk":5381},"topList":{"module":"musicToplist.ToplistInfoServer","method":"GetAll","param":{}}}`
  → `topList.data.group[].toplist[].{topId, title, titleDetail, intro, period, updateTime, listenNum, totalNum, recType, frontPicUrl, mbFrontPicUrl, headPicUrl, mbHeadPicUrl, musichallPicUrl}`；跳过 `recType==10010`（MV 榜）。
- 曲目：`GET https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?topid=<id>&song_begin=<begin>&song_num=50&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=h5&needNewCode=1&tpl=3&page=detail&type=top`
  → `songlist[].{cur_count, data.{songid, songmid, songname, albumname, albummid, interval, strMediaMid, pay.payplay, singer[].name}}`；`song_begin` 每页 +50。

## 歌词（既有实现）

AquaMoon 现有 `QQMusicService.fetchLyricsBySongMid` 使用
`GET https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=<mid>&format=json&nobase64=0`
（`lyric` 字段 Base64）。music-lib 另用 `musicu.fcg` 的
`music.musichallSong.PlayLyricInfo` / `GetPlayLyricInfo` 返回加密 QRC 逐字歌词
（3DES-ECB + zlib 解密），本项目暂未移植逐字歌词。

## 登录 / Cookie

music-lib 支持 QQ 号与微信扫码登录（`xui.ptlogin2.qq.com`、`open.weixin.qq.com` →
`musicu.fcg` 的 `QQConnectLogin.LoginServer/QQLogin` 或 `music.login.LoginServer/Login`），
最终要求 Cookie 含 `qm_keyst`。AquaMoon 复用既有 `QQMusicAuthDialog` 让用户粘贴 Cookie，
暂不内置扫码流程（需要维护 cookie jar / 二维码轮询，超出本次范围）。

## go-music-dl Web API（可选自建后端，未启用）

`GET /music/search?q=&type=song&sources=qq`、`GET /music/inspect`（JSON，返回 `url`）、
`GET /music/download?stream=1&id=&source=qq&extra=&quality=`、`GET /music/lyric`、
`GET /music/playlist?id=&source=`、`GET /music/album?id=&source=`、`GET /music/toplists`、
`GET /music/recommend`、`GET /music/api/ai/index`。除 `/inspect` 等少数返回 JSON/文本外，
discover/details 路由默认返回 HTML。写操作需 `X-Requested-With: XMLHttpRequest`。

## 明确未确认 / 不臆造

`C400`、`F0M`、`O400`、`A000`、`FLAC` 前缀、`authst`、`u6.y.qq.com`、`sip` 多 CDN、
独立「每日推荐歌曲」端点、QQ 试听片段专用 URL —— 在 music-lib 源码中均未出现或另有实现。

## 实测记录（2026-11，真实 Cookie）

社区里流传的 `music.vkey.GetVkey` / `CgiGetVkey` 已被服务端废弃：无论免费曲还是 VIP 曲
都返回 `{"req_0":{"code":500003,"subcode":860400001}}` 且不带 `midurlinfo`，于是
`resolvePlayUrl` 的整条回退链（所选音质 → M800 → M500 → 默认流 → C400）全部拿不到
purl，免费曲也播不了。换成旧模块 `vkey.GetVkeyServer` / `CgiGetVkey` 后恢复正常，
这也是本项目现在使用的形态（有单测锁定模块名，避免回退）。

同一账号（含 `qm_keyst`）下的取流实测：

| 曲目 | M500 | M800 | F000 |
| --- | --- | --- | --- |
| 免费曲（如《夜的钢琴曲5》） | OK | 空 | 空 |
| VIP 曲（如《晴天》《稻香》《孤勇者》） | 空 | 空 | 空 |

- `songmid` 与 `file.media_mid` 对测试曲目一致，换命名不影响结果。
- 匿名 / 登录态 `comm.uin`+`authst` / 加 `X-Forwarded-For`+`X-Real-IP` / `u.y.qq.com`
  与 `u6.y.qq.com` / `platform=20` 或 `h5` / `loginflag=0` 或 `1`：结果均相同。
- 该 Cookie 的会话本身有效（`music.soundPower.SoundPowerSvr/QueryLevelDetailPage`
  返回 `code=0` 并带 nick / 等级信息），但 `GetVipInfo`、`UserAsset` 一类会员模块返回
  `500003`，vkey 侧也未授予 320K 或 VIP 音质。

结论：VIP 曲目能否播放完全取决于 vkey 服务端对该 Cookie 会员权益的判定，客户端不做
任何绕过。旧 Cookie 的 `qqmusic_key` 已轮换，表现为「会话还能读资料、但一律不给音源」；
换成同一账号新导出的 Cookie 后，VIP 曲目 128K/320K/无损全部拿到 purl 并成功取到字节
（`ID3` / `fLaC` 魔数校验通过）。

### filename 命名的坑

vkey 返回 purl ≠ 文件存在。`M500<mid>.mp3`、`M800<mid>.mp3`、`F000<mid>.flac`、
`C400<mid>.m4a` 这类「前缀+单 mid」命名照样返回 purl，但 CDN 取流报
`{"errorcode":-46628,"errormsg":"file not exist"}`。真实文件是 music-lib 的
`前缀+mid+mid+后缀` 双写命名（也可用解析出的 `media_mid` 单写）。因此
`resolvePlayUrl` 现在按「双写命名 → 单写命名」的顺序试探，DT 有单测锁定顺序。

另外注意：请求 `前缀+<songmid><songmid>+后缀` 时，服务端会把 purl 重写为它认可的
canonical 文件名（可能换成 `media_mid`），所以只要 purl 非空且该名字真实存在即可播放。
