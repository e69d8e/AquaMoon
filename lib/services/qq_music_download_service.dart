import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/platform/media_scanner.dart';
import '../models/qq_music_config.dart';
import '../models/qq_music_discovery.dart';
import '../models/song.dart';
import 'qq_music_service.dart';

/// QQ 音乐下载失败。`message` 可直接展示给用户。
class QQMusicDownloadException implements Exception {
  const QQMusicDownloadException(this.message, {this.needsCookie = false});

  final String message;

  /// 失败原因是所选音质需要登录 Cookie（界面可据此引导绑定账号）。
  final bool needsCookie;

  @override
  String toString() => message;
}

/// 一次下载的结果。
///
/// [quality] 是用户请求的音质，[actualQuality] 是 CDN 实际给出的音质：
/// 高音质无授权时服务端会降级（无损 → 320K MP3），此时两者不同，界面需要
/// 如实提示用户下载到的到底是什么。
class QQMusicDownloadResult {
  const QQMusicDownloadResult({
    required this.filePath,
    required this.directory,
    required this.quality,
    required this.bytes,
    this.actualQuality,
    this.lyricsPath,
  });

  final String filePath;
  final String directory;
  final QQMusicStreamQuality quality;
  final QQMusicStreamQuality? actualQuality;
  final int bytes;
  final String? lyricsPath;

  String get fileName => p.basename(filePath);

  bool get isDowngraded =>
      actualQuality != null && actualQuality != quality;
}

/// QQ 音乐歌曲下载器。
///
/// 协议要点见 `docs/qq_music_protocol.md`：先用 [QQMusicService.resolvePlayUrl]
/// 拿到带 vkey 的直链，再把音频流原样写入用户指定的文件夹。文件名采用
/// 「歌手 - 歌名.扩展名」，即使音频内没有标签，曲库的元数据兜底解析也能
/// 从文件名里还原歌手与歌名。
class QQMusicDownloadService {
  QQMusicDownloadService({QQMusicService? musicService, http.Client? client})
    : _musicService = musicService ?? QQMusicService(),
      _client = client ?? http.Client(),
      _ownsMusicService = musicService == null,
      _ownsClient = client == null;

  final QQMusicService _musicService;
  final http.Client _client;
  final bool _ownsMusicService;
  final bool _ownsClient;

  /// Android 公共下载目录的默认子文件夹。
  static const String androidDefaultDirectory = '/storage/emulated/0/Download/AquaMoon';

  static const Set<String> _audioExtensions = <String>{
    'flac',
    'mp3',
    'm4a',
    'ogg',
    'opus',
    'wav',
    'aac',
    'ape',
  };

  static const String _downloadUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 下载 [song] 到 [targetDirectory]（为空时落到默认下载文件夹）。
  ///
  /// 成功返回落盘结果；失败抛出 [QQMusicDownloadException]。
  Future<QQMusicDownloadResult> downloadSong({
    required Song song,
    required QQMusicStreamQuality quality,
    String? targetDirectory,
    QQMusicConfig config = const QQMusicConfig(),
    bool saveLyrics = true,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final songMid = song.qqSongMid;
    if (songMid == null || songMid.isEmpty) {
      throw const QQMusicDownloadException('该曲目缺少 QQ 音乐 songmid，无法下载');
    }

    final url = await _musicService.resolvePlayUrl(
      songMid: songMid,
      mediaMid: song.qqMediaMid,
      config: config,
      quality: quality,
    );
    if (url == null || url.trim().isEmpty) {
      if (quality.requiresCookie && !config.hasCookie) {
        throw QQMusicDownloadException(
          '「${quality.label}」音质需要先在设置中绑定 QQ 音乐 Cookie',
          needsCookie: true,
        );
      }
      throw QQMusicDownloadException(
        '《${song.title}》受 QQ 音乐 VIP 或版权限制无法下载'
        '${config.hasCookie ? '' : '，绑定绿钻 Cookie 后可再试'}',
      );
    }

    final directory = await prepareDownloadDirectory(preferred: targetDirectory);
    final extension = extensionFromUrl(url) ?? quality.extension;
    final targetPath = _uniquePath(
      directory,
      baseName: fileNameFor(song),
      extension: extension,
    );

    final bytes = await _downloadTo(targetPath, url, onProgress: onProgress);

    String? lyricsPath;
    if (saveLyrics) {
      lyricsPath = await _saveLyrics(
        songMid: songMid,
        targetPath: targetPath,
        config: config,
      );
    }

    // 公共目录里新写入的文件需要登记进媒体库，其它音乐 App 才能看到。
    unawaited(MediaScanner.scanAudioFile(targetPath));

    return QQMusicDownloadResult(
      filePath: targetPath,
      directory: directory,
      quality: quality,
      actualQuality: qualityFromUrl(url),
      bytes: bytes,
      lyricsPath: lyricsPath,
    );
  }

  /// 解析并准备下载目录。
  ///
  /// 优先使用用户在设置里指定的 [preferred]；不可写时回退到默认下载目录，
  /// 默认目录也不可用时再回退到应用专属外部目录，保证下载不会无处可写。
  Future<String> prepareDownloadDirectory({String? preferred}) async {
    final custom = (preferred ?? '').trim();
    if (custom.isNotEmpty && await _ensureWritableDirectory(custom)) {
      return custom;
    }

    if (Platform.isAndroid &&
        await _ensureWritableDirectory(androidDefaultDirectory)) {
      return androidDefaultDirectory;
    }

    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    if (base == null) {
      try {
        base = await getDownloadsDirectory();
      } catch (_) {
        base = null;
      }
    }
    base ??= await getApplicationDocumentsDirectory();

    final fallback = p.join(base.path, 'AquaMoon');
    if (await _ensureWritableDirectory(fallback)) return fallback;
    throw const QQMusicDownloadException('无法创建下载文件夹，请到设置中选择其它文件夹');
  }

  /// 目录是否可写（会顺带创建目录）。供设置页与下载流程判断是否需要
  /// 申请「所有文件访问权限」。
  static Future<bool> isDirectoryWritable(String path) =>
      _ensureWritableDirectory(path.trim());

  /// 目录不存在时创建，并写入一个探针文件确认真的可写
  /// （Android 11+ 没有「所有文件访问权限」时，公共目录能建目录但写不进去）。
  static Future<bool> _ensureWritableDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File(p.join(path, '.aquamoon_write_probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _downloadTo(
    String targetPath,
    String url, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = _downloadUserAgent;
    request.headers['Referer'] = 'https://y.qq.com/';

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      throw const QQMusicDownloadException('下载失败，请检查网络后重试');
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw QQMusicDownloadException('下载失败 (HTTP ${response.statusCode})');
    }
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('json') || contentType.contains('text/plain')) {
      // 音源无效时 CDN 会回 200 + JSON 错误体，不能当作音频写入磁盘。
      throw const QQMusicDownloadException('音源文件不存在或已下架，请换一首或换音质重试');
    }

    final total = response.contentLength;
    final part = File('$targetPath.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } catch (_) {
      await _closeQuietly(sink);
      await _deleteQuietly(part);
      throw const QQMusicDownloadException('下载中断，请检查网络后重试');
    }
    await _closeQuietly(sink);

    if (received == 0) {
      await _deleteQuietly(part);
      throw const QQMusicDownloadException('音源返回了空文件，请换音质重试');
    }
    if (total != null && total > 0 && received != total) {
      await _deleteQuietly(part);
      throw const QQMusicDownloadException('下载不完整，请重试');
    }

    try {
      await part.rename(targetPath);
      return received;
    } catch (_) {
      await _deleteQuietly(part);
      throw const QQMusicDownloadException('写入下载文件夹失败，请检查存储权限');
    }
  }

  Future<String?> _saveLyrics({
    required String songMid,
    required String targetPath,
    required QQMusicConfig config,
  }) async {
    try {
      final lrc = await _musicService.fetchLyricsBySongMid(
        songMid,
        config: config,
      );
      if (lrc == null || lrc.trim().isEmpty) return null;
      // 与曲库的 sidecar 歌词约定一致：与音频同目录同名的 .lrc。
      final lrcPath = '${p.withoutExtension(targetPath)}.lrc';
      await File(lrcPath).writeAsString(lrc, flush: true);
      unawaited(MediaScanner.scanAudioFile(lrcPath));
      return lrcPath;
    } catch (_) {
      // 歌词只是附带产物，失败不能影响歌曲下载成功的结论。
      return null;
    }
  }

  /// 由直链推断实际音质（服务端降级时与请求音质不同）。
  static QQMusicStreamQuality? qualityFromUrl(String url) {
    final name = p.basename(Uri.tryParse(url)?.path ?? url).toUpperCase();
    if (name.isEmpty) return null;
    for (final quality in QQMusicStreamQuality.values) {
      if (name.startsWith(quality.filenamePrefix.toUpperCase())) {
        return quality;
      }
    }
    return null;
  }

  /// 从直链路径取音频扩展名；不是已知音频扩展名时返回 null。
  static String? extensionFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (ext.isEmpty) return null;
    return _audioExtensions.contains(ext) ? ext : null;
  }

  /// 下载文件名（不含扩展名）：优先「歌手 - 歌名」。
  static String fileNameFor(Song song) {
    final artist = song.artist.trim();
    final title = song.title.trim();
    final String base;
    if (title.isEmpty) {
      base = artist.isEmpty ? 'QQ音乐曲目' : artist;
    } else if (artist.isEmpty || artist == '未知歌手') {
      base = title;
    } else {
      base = '$artist - $title';
    }
    return sanitizeFileName(base);
  }

  /// 去掉文件名里各平台不接受的字符，并限制长度。
  static String sanitizeFileName(String raw) {
    var name = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Android/FAT 类文件系统不允许以点或空格结尾。
    name = name.replaceAll(RegExp(r'[. ]+$'), '').trim();
    if (name.isEmpty) name = 'QQ音乐曲目';
    if (name.length > 120) {
      name = name.substring(0, 120).trim();
    }
    return name;
  }

  /// 同名文件已存在时追加 ` (2)`、` (3)`…，绝不覆盖用户已有文件。
  static String _uniquePath(
    String directory, {
    required String baseName,
    required String extension,
  }) {
    final sanitized = sanitizeFileName(baseName);
    var candidate = p.join(directory, '$sanitized.$extension');
    var index = 2;
    while (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
      candidate = p.join(directory, '$sanitized ($index).$extension');
      index++;
      if (index > 999) break;
    }
    return candidate;
  }

  static Future<void> _closeQuietly(IOSink sink) async {
    try {
      await sink.close();
    } catch (_) {}
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void dispose() {
    if (_ownsClient) _client.close();
    if (_ownsMusicService) _musicService.dispose();
  }
}
