import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioMetadataResult {
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String? albumArtUri;
  final Uint8List? albumArtBytes;
  final int? year;

  /// Embedded lyrics (USLT / ©lyr / LYRICS tag) when the file carries them —
  /// synced LRC content or plain text, verbatim from the tag.
  final String? lyrics;

  const AudioMetadataResult({
    required this.title,
    required this.artist,
    required this.album,
    this.durationMs = 0,
    this.albumArtUri,
    this.albumArtBytes,
    this.year,
    this.lyrics,
  });
}

class MetadataExtractor {
  static const int _initialHeaderBytes = 65536;
  static const int _maxTagBytes = 32 * 1024 * 1024;

  static Future<String> resolveCoverCacheDirPath() async {
    try {
      // 封面缓存放在应用支持目录：系统会随时清理临时目录，而这里返回的
      // file:// URI 会被长期持久化在曲库记录里，临时文件一旦被清就永久失效。
      final supportDir = await getApplicationSupportDirectory();
      return supportDir.path;
    } catch (_) {
      return '';
    }
  }

  /// Extracts metadata and embedded artwork from a local audio file (.mp3, .flac, .m4a, .ogg, .wav, etc.)
  ///
  /// Only the platform-channel lookup (cover cache directory) runs on the main
  /// isolate; all byte-level parsing is delegated to a background isolate so
  /// a large library scan never blocks the UI thread.
  static Future<AudioMetadataResult> extractFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return _fallbackFromFilename(filePath);
    }

    final coverCacheDirPath = await resolveCoverCacheDirPath();
    return Isolate.run(
      () => extractFromFileIsolated(filePath, coverCacheDirPath),
    );
  }

  /// Extracts metadata for a chunk of [filePaths] inside a single background
  /// isolate, sharing directory artwork listings across sibling tracks and
  /// avoiding one `Isolate.run` spawn per audio file.
  static Future<List<AudioMetadataResult>> extractChunkIsolated(
    List<String> filePaths,
    String coverCacheDirPath,
  ) async {
    final dirImageCache = <String, List<String>>{};
    final results = <AudioMetadataResult>[];
    for (final filePath in filePaths) {
      results.add(
        await extractFromFileIsolated(
          filePath,
          coverCacheDirPath,
          dirImageCache: dirImageCache,
        ),
      );
    }
    return results;
  }

  static Future<Uint8List> _readFileSlice(
    File file,
    int start,
    int length,
  ) async {
    if (length <= 0) return Uint8List(0);
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }

  /// CPU-heavy half of [extractFromFile]; always runs inside `Isolate.run`.
  /// `coverCacheDirPath` must be resolved by the caller beforehand because
  /// platform channels are not available in a background isolate.
  static Future<AudioMetadataResult> extractFromFileIsolated(
    String filePath,
    String coverCacheDirPath, {
    Map<String, List<String>>? dirImageCache,
  }) async {
    final file = File(filePath);

    try {
      if (!await file.exists()) {
        return _fallbackFromFilename(filePath);
      }
      final ext = p.extension(filePath).toLowerCase();

      // Read a small 64KB probe window upfront instead of 2MB per file;
      // larger ID3v2 / FLAC / MP4 moov headers are fetched on demand.
      final length = await file.length();
      final readLen =
          length > _initialHeaderBytes ? _initialHeaderBytes : length;
      final uint8 = await _readFileSlice(file, 0, readLen);

      AudioMetadataResult? result;

      // 1. FLAC format (Magic 'fLaC' = 0x66, 0x4C, 0x61, 0x43)
      if (ext == '.flac' ||
          (uint8.length >= 4 &&
              uint8[0] == 0x66 &&
              uint8[1] == 0x4C &&
              uint8[2] == 0x61 &&
              uint8[3] == 0x43)) {
        result = await _parseFlac(file, uint8, filePath, coverCacheDirPath);
      }
      // 2. MP4 / M4A / AAC container (contains 'ftyp' or 'moov' or ext .m4a/.aac)
      else if (ext == '.m4a' ||
          ext == '.aac' ||
          ext == '.mp4' ||
          (uint8.length >= 8 &&
              (uint8[4] == 0x66 &&
                  uint8[5] == 0x74 &&
                  uint8[6] == 0x79 &&
                  uint8[7] == 0x70))) {
        result = await _parseM4a(file, uint8, filePath, coverCacheDirPath);
      }
      // 3. ID3v2 (MP3, WAV with ID3 chunk, or FLAC with ID3 wrapper)
      else if (uint8.length >= 10 &&
          uint8[0] == 0x49 &&
          uint8[1] == 0x44 &&
          uint8[2] == 0x33) {
        result = await _parseId3v2(file, uint8, filePath, coverCacheDirPath);
      }
      // 4. OGG / Opus container
      else if (ext == '.ogg' ||
          ext == '.opus' ||
          (uint8.length >= 4 &&
              uint8[0] == 0x4F &&
              uint8[1] == 0x67 &&
              uint8[2] == 0x67 &&
              uint8[3] == 0x53)) {
        result = await _parseOgg(file, uint8, filePath, coverCacheDirPath);
      }

      // 5. Fallback to ID3v1 for MP3
      if (result == null ||
          result.title == '未知曲目' ||
          _isWatermark(result.title)) {
        final id3v1 = await _parseId3v1(file, filePath);
        if (id3v1 != null) {
          if (result == null) {
            result = id3v1;
          } else {
            // ID3v1 只有标题/歌手/专辑/年份——按字段合并，别让整对象替换
            // 丢掉 ID3v2 已解析出的内嵌封面、歌词和时长。
            result = AudioMetadataResult(
              title: (result.title == '未知曲目' || _isWatermark(result.title))
                  ? id3v1.title
                  : result.title,
              artist: (result.artist.isEmpty || _isWatermark(result.artist))
                  ? id3v1.artist
                  : result.artist,
              album: (result.album.isEmpty || _isWatermark(result.album))
                  ? id3v1.album
                  : result.album,
              durationMs: result.durationMs,
              albumArtUri: result.albumArtUri,
              albumArtBytes: result.albumArtBytes,
              year: result.year ?? id3v1.year,
              lyrics: result.lyrics,
            );
          }
        }
      }

      // 6. If no embedded cover art found, search local directory for folder.jpg / cover.jpg / album.jpg
      if (result == null || result.albumArtUri == null) {
        final folderCoverUri = await _findLocalDirectoryCover(
          filePath,
          dirImageCache: dirImageCache,
        );
        if (folderCoverUri != null) {
          if (result != null) {
            result = AudioMetadataResult(
              title: result.title,
              artist: result.artist,
              album: result.album,
              durationMs: result.durationMs,
              albumArtUri: folderCoverUri,
              albumArtBytes: result.albumArtBytes,
              year: result.year,
              lyrics: result.lyrics,
            );
          } else {
            final fb = _fallbackFromFilename(filePath);
            result = AudioMetadataResult(
              title: fb.title,
              artist: fb.artist,
              album: fb.album,
              albumArtUri: folderCoverUri,
            );
          }
        }
      }

      if (result != null) {
        if (result.durationMs <= 0) {
          int calcDuration = 0;
          if (ext == '.mp3') {
            calcDuration = await _calculateMp3Duration(file, 0);
          } else if (ext == '.wav') {
            calcDuration = await _calculateWavDuration(file, uint8);
          }
          if (calcDuration > 0) {
            result = AudioMetadataResult(
              title: result.title,
              artist: result.artist,
              album: result.album,
              durationMs: calcDuration,
              albumArtUri: result.albumArtUri,
              albumArtBytes: result.albumArtBytes,
              year: result.year,
              lyrics: result.lyrics,
            );
          }
        }
        return _sanitizeResult(result, filePath);
      }
    } catch (_) {}

    final fb = _fallbackFromFilename(filePath);
    int fallbackDur = 0;
    try {
      final ext = p.extension(filePath).toLowerCase();
      if (ext == '.mp3') {
        fallbackDur = await _calculateMp3Duration(file, 0);
      }
    } catch (_) {}
    return AudioMetadataResult(
      title: fb.title,
      artist: fb.artist,
      album: fb.album,
      durationMs: fallbackDur,
    );
  }

  // ==========================================
  // 1. FLAC Parser (Native fLaC stream & Vorbis Comment & Picture blocks)
  // ==========================================
  static Future<AudioMetadataResult?> _parseFlac(
    File file,
    Uint8List data,
    String filePath,
    String coverCacheDirPath,
  ) async {
    try {
      if (data.length < 4 ||
          data[0] != 0x66 ||
          data[1] != 0x4C ||
          data[2] != 0x61 ||
          data[3] != 0x43) {
        return null;
      }

      int offset = 4;
      bool isLast = false;

      String? title;
      String? artist;
      String? album;
      int durationMs = 0;
      Uint8List? artBytes;
      int? year;
      String? lyrics;

      while (!isLast && offset >= 0) {
        final int headerByte;
        final int blockLength;
        if (offset + 4 <= data.length) {
          headerByte = data[offset];
          blockLength =
              (data[offset + 1] << 16) |
              (data[offset + 2] << 8) |
              data[offset + 3];
        } else {
          final header = await _readFileSlice(file, offset, 4);
          if (header.length < 4) break;
          headerByte = header[0];
          blockLength = (header[1] << 16) | (header[2] << 8) | header[3];
        }

        isLast = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;
        offset += 4;
        if (blockLength <= 0 || blockLength > _maxTagBytes) break;

        // Skip padding / seektable / unknown blocks without reading them.
        if (blockType != 0 && blockType != 4 && blockType != 6) {
          offset += blockLength;
          continue;
        }

        final Uint8List blockData;
        if (offset + blockLength > data.length) {
          blockData = await _readFileSlice(file, offset, blockLength);
        } else {
          blockData = data.sublist(offset, offset + blockLength);
        }
        offset += blockLength;
        if (blockData.isEmpty) break;

        if (blockType == 0) {
          durationMs = _parseFlacStreamInfo(blockData);
        } else if (blockType == 4) {
          final comments = _parseVorbisComments(blockData);
          title ??= comments['TITLE'] ?? comments['title'];
          artist ??= comments['ARTIST'] ?? comments['artist'];
          album ??= comments['ALBUM'] ?? comments['album'];
          final yearStr =
              comments['DATE'] ??
              comments['date'] ??
              comments['YEAR'] ??
              comments['year'];
          if (yearStr != null && yearStr.length >= 4) {
            year ??= int.tryParse(yearStr.substring(0, 4));
          }
          lyrics ??= _vorbisLyrics(comments);
          if (comments.containsKey('METADATA_BLOCK_PICTURE')) {
            try {
              final picBase64 = comments['METADATA_BLOCK_PICTURE']!;
              artBytes ??= _parseFlacPictureBlock(base64.decode(picBase64));
            } catch (_) {}
          }
        } else if (blockType == 6) {
          artBytes ??= _parseFlacPictureBlock(blockData);
        }
      }

      String? artUri;
      if (artBytes != null && artBytes.isNotEmpty) {
        artUri = await _saveCoverArtCache(filePath, artBytes, coverCacheDirPath);
      }

      final fallback = _fallbackFromFilename(filePath);
      return AudioMetadataResult(
        title: (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : fallback.title,
        artist: (artist != null && artist.trim().isNotEmpty)
            ? artist.trim()
            : fallback.artist,
        album: (album != null && album.trim().isNotEmpty)
            ? album.trim()
            : fallback.album,
        durationMs: durationMs > 0 ? durationMs : fallback.durationMs,
        albumArtUri: artUri,
        albumArtBytes: artBytes,
        year: year,
        lyrics: lyrics,
      );
    } catch (_) {
      return null;
    }
  }

  static int _parseFlacStreamInfo(Uint8List block) {
    if (block.length < 18) return 0;
    final sampleRate = (block[10] << 12) | (block[11] << 4) | (block[12] >> 4);
    final totalSamples =
        ((block[13] & 0x0F) * 4294967296) +
        (block[14] << 24) +
        (block[15] << 16) +
        (block[16] << 8) +
        block[17];

    if (sampleRate > 0 && totalSamples > 0) {
      return ((totalSamples / sampleRate) * 1000).toInt();
    }
    return 0;
  }

  static Map<String, String> _parseVorbisComments(Uint8List block) {
    final Map<String, String> result = {};
    if (block.length < 8) return result;

    int offset = 0;
    final vendorLen =
        block[offset] |
        (block[offset + 1] << 8) |
        (block[offset + 2] << 16) |
        (block[offset + 3] << 24);
    offset += 4 + vendorLen;

    if (offset + 4 > block.length) return result;
    final commentCount =
        block[offset] |
        (block[offset + 1] << 8) |
        (block[offset + 2] << 16) |
        (block[offset + 3] << 24);
    offset += 4;

    for (int i = 0; i < commentCount && offset + 4 <= block.length; i++) {
      final len =
          block[offset] |
          (block[offset + 1] << 8) |
          (block[offset + 2] << 16) |
          (block[offset + 3] << 24);
      offset += 4;
      if (offset + len > block.length) break;

      final commentStr = utf8.decode(
        block.sublist(offset, offset + len),
        allowMalformed: true,
      );
      offset += len;

      final eqIdx = commentStr.indexOf('=');
      if (eqIdx > 0) {
        final key = commentStr.substring(0, eqIdx).toUpperCase();
        final value = commentStr.substring(eqIdx + 1);
        result[key] = value;
      }
    }
    return result;
  }

  static Uint8List? _parseFlacPictureBlock(List<int> block) {
    if (block.length < 32) return null;
    try {
      int offset = 4; // skip picture type (4 bytes)
      if (offset + 4 > block.length) return null;
      final mimeLen =
          (block[offset] << 24) |
          (block[offset + 1] << 16) |
          (block[offset + 2] << 8) |
          block[offset + 3];
      if (mimeLen < 0 || offset + 4 + mimeLen > block.length) return null;
      offset += 4 + mimeLen;

      if (offset + 4 > block.length) return null;
      final descLen =
          (block[offset] << 24) |
          (block[offset + 1] << 16) |
          (block[offset + 2] << 8) |
          block[offset + 3];
      if (descLen < 0 || offset + 4 + descLen > block.length) return null;
      offset += 4 + descLen;

      // Skip width (4), height (4), depth (4), colors (4) = 16 bytes
      if (offset + 16 + 4 > block.length) return null;
      offset += 16;

      final dataLen =
          (block[offset] << 24) |
          (block[offset + 1] << 16) |
          (block[offset + 2] << 8) |
          block[offset + 3];
      offset += 4;

      if (dataLen > 0 && offset + dataLen <= block.length) {
        return Uint8List.fromList(block.sublist(offset, offset + dataLen));
      }
    } catch (_) {}
    return null;
  }

  // ==========================================
  // 2. M4A / AAC (Hierarchical MP4 Box Parser: moov / udta / meta / ilst)
  // ==========================================
  static const int _boxMoov = 0x6D6F6F76; // 'moov'
  static const int _boxMvhd = 0x6D766864; // 'mvhd'
  static const int _boxTrak = 0x7472616B; // 'trak'
  static const int _boxMdia = 0x6D646961; // 'mdia'
  static const int _boxMdhd = 0x6D646864; // 'mdhd'
  static const int _boxUdta = 0x75647461; // 'udta'
  static const int _boxMeta = 0x6D657461; // 'meta'
  static const int _boxIlst = 0x696C7374; // 'ilst'
  static const int _boxNam = 0xA96E616D; // '©nam'
  static const int _boxArt = 0xA9415254; // '©ART'
  static const int _boxAlb = 0xA9616C62; // '©alb'
  static const int _boxDay = 0xA9646179; // '©day'
  static const int _boxLyr = 0xA96C7972; // '©lyr'
  static const int _boxCovr = 0x636F7672; // 'covr'
  static const int _boxData = 0x64617461; // 'data'

  static int _readUint32BE(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static Future<Uint8List?> _locateMoovAtom(
    File file,
    Uint8List probeData,
  ) async {
    final fileLen = await file.length();
    final raf = await file.open();
    try {
      int offset = 0;
      final headerBuf = Uint8List(8);
      final extBuf = Uint8List(8);
      while (offset + 8 <= fileLen) {
        int boxSize;
        int boxType;
        int headerSize = 8;

        if (offset + 8 <= probeData.length) {
          boxSize = _readUint32BE(probeData, offset);
          boxType = _readUint32BE(probeData, offset + 4);
        } else {
          await raf.setPosition(offset);
          final n = await raf.readInto(headerBuf);
          if (n < 8) break;
          boxSize = _readUint32BE(headerBuf, 0);
          boxType = _readUint32BE(headerBuf, 4);
        }

        if (boxSize == 1) {
          if (offset + 16 > fileLen) break;
          if (offset + 16 <= probeData.length) {
            boxSize =
                (_readUint32BE(probeData, offset + 8) << 32) |
                _readUint32BE(probeData, offset + 12);
          } else {
            await raf.setPosition(offset + 8);
            if (await raf.readInto(extBuf) < 8) break;
            boxSize =
                (_readUint32BE(extBuf, 0) << 32) | _readUint32BE(extBuf, 4);
          }
          headerSize = 16;
        } else if (boxSize == 0) {
          boxSize = fileLen - offset;
        }

        if (boxSize < headerSize || offset + boxSize > fileLen) break;

        if (boxType == _boxMoov) {
          if (boxSize > _maxTagBytes) return null;
          if (offset + boxSize <= probeData.length) {
            return Uint8List.sublistView(
              probeData,
              offset + headerSize,
              offset + boxSize,
            );
          }
          await raf.setPosition(offset + headerSize);
          return await raf.read(boxSize - headerSize);
        }

        offset += boxSize;
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  static Future<AudioMetadataResult?> _parseM4a(
    File file,
    Uint8List data,
    String filePath,
    String coverCacheDirPath,
  ) async {
    try {
      final moovPayload = await _locateMoovAtom(file, data);
      if (moovPayload == null || moovPayload.isEmpty) return null;

      String? title;
      String? artist;
      String? album;
      Uint8List? artBytes;
      int? year;
      int durationMs = 0;
      String? lyrics;

      void walk(int start, int end) {
        int i = start;
        while (i + 8 <= end) {
          final boxSize = _readUint32BE(moovPayload, i);
          if (boxSize < 8 || i + boxSize > end) break;
          final boxType = _readUint32BE(moovPayload, i + 4);
          final bodyStart = i + 8;
          final bodyEnd = i + boxSize;

          if (boxType == _boxTrak ||
              boxType == _boxMdia ||
              boxType == _boxUdta ||
              boxType == _boxIlst) {
            walk(bodyStart, bodyEnd);
          } else if (boxType == _boxMeta) {
            // Standard ISO BMFF 'meta' is a FullBox (4 bytes version+flags);
            // fall back to direct child atoms for legacy QuickTime variants.
            if (bodyStart + 12 <= bodyEnd &&
                _readUint32BE(moovPayload, bodyStart) == 0) {
              walk(bodyStart + 4, bodyEnd);
            } else {
              walk(bodyStart, bodyEnd);
            }
          } else if (boxType == _boxMvhd && bodyStart + 16 <= bodyEnd) {
            final version = moovPayload[bodyStart];
            if (version == 0 && bodyStart + 20 <= bodyEnd) {
              final timescale = _readUint32BE(moovPayload, bodyStart + 12);
              final duration = _readUint32BE(moovPayload, bodyStart + 16);
              if (timescale > 0) {
                durationMs = ((duration * 1000) / timescale).toInt();
              }
            } else if (version == 1 && bodyStart + 32 <= bodyEnd) {
              final timescale = _readUint32BE(moovPayload, bodyStart + 20);
              final duration =
                  ((moovPayload[bodyStart + 24] & 0x7F) << 56) |
                  (moovPayload[bodyStart + 25] << 48) |
                  (moovPayload[bodyStart + 26] << 40) |
                  (moovPayload[bodyStart + 27] << 32) |
                  _readUint32BE(moovPayload, bodyStart + 28);
              if (timescale > 0) {
                durationMs = ((duration * 1000) / timescale).toInt();
              }
            }
          } else if (boxType == _boxMdhd &&
              durationMs == 0 &&
              bodyStart + 20 <= bodyEnd) {
            final version = moovPayload[bodyStart];
            if (version == 0) {
              final timescale = _readUint32BE(moovPayload, bodyStart + 12);
              final duration = _readUint32BE(moovPayload, bodyStart + 16);
              if (timescale > 0) {
                durationMs = ((duration * 1000) / timescale).toInt();
              }
            }
          } else if (boxType == _boxNam) {
            title ??= _extractM4aStringRange(moovPayload, bodyStart, bodyEnd);
          } else if (boxType == _boxArt) {
            artist ??= _extractM4aStringRange(moovPayload, bodyStart, bodyEnd);
          } else if (boxType == _boxAlb) {
            album ??= _extractM4aStringRange(moovPayload, bodyStart, bodyEnd);
          } else if (boxType == _boxDay) {
            final yearStr =
                _extractM4aStringRange(moovPayload, bodyStart, bodyEnd);
            if (yearStr != null && yearStr.length >= 4) {
              year ??= int.tryParse(yearStr.substring(0, 4));
            }
          } else if (boxType == _boxLyr) {
            lyrics ??= _extractM4aStringRange(moovPayload, bodyStart, bodyEnd);
          } else if (boxType == _boxCovr) {
            artBytes ??= _extractM4aCoverRange(moovPayload, bodyStart, bodyEnd);
          }

          i = bodyEnd;
        }
      }

      walk(0, moovPayload.length);

      String? artUri;
      if (artBytes != null && artBytes!.isNotEmpty) {
        artUri = await _saveCoverArtCache(
          filePath,
          artBytes!,
          coverCacheDirPath,
        );
      }

      final fallback = _fallbackFromFilename(filePath);
      return AudioMetadataResult(
        title: (title != null && title!.trim().isNotEmpty)
            ? title!.trim()
            : fallback.title,
        artist: (artist != null && artist!.trim().isNotEmpty)
            ? artist!.trim()
            : fallback.artist,
        album: (album != null && album!.trim().isNotEmpty)
            ? album!.trim()
            : fallback.album,
        durationMs: durationMs > 0 ? durationMs : fallback.durationMs,
        albumArtUri: artUri,
        albumArtBytes: artBytes,
        year: year,
        lyrics: lyrics,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractM4aStringRange(Uint8List data, int start, int end) {
    int i = start;
    while (i + 16 <= end) {
      final size = _readUint32BE(data, i);
      if (size < 8 || i + size > end) break;
      if (_readUint32BE(data, i + 4) == _boxData && size > 16) {
        return utf8
            .decode(
              Uint8List.sublistView(data, i + 16, i + size),
              allowMalformed: true,
            )
            .trim();
      }
      i += size;
    }
    return null;
  }

  static Uint8List? _extractM4aCoverRange(Uint8List data, int start, int end) {
    int i = start;
    while (i + 16 <= end) {
      final size = _readUint32BE(data, i);
      if (size < 8 || i + size > end) break;
      if (_readUint32BE(data, i + 4) == _boxData && size > 16) {
        return Uint8List.fromList(data.sublist(i + 16, i + size));
      }
      i += size;
    }
    return null;
  }

  // ==========================================
  // 3. OGG / Opus Parser
  // ==========================================
  static Future<AudioMetadataResult?> _parseOgg(
    File file,
    Uint8List data,
    String filePath,
    String coverCacheDirPath,
  ) async {
    try {
      final comments = _parseOggVorbisComments(data);
      final title = comments['TITLE'] ?? comments['title'];
      final artist = comments['ARTIST'] ?? comments['artist'];
      final album = comments['ALBUM'] ?? comments['album'];
      final lyrics = _vorbisLyrics(comments);

      Uint8List? artBytes;
      if (comments.containsKey('METADATA_BLOCK_PICTURE')) {
        try {
          artBytes = _parseFlacPictureBlock(
            base64.decode(comments['METADATA_BLOCK_PICTURE']!),
          );
        } catch (_) {}
      }

      String? artUri;
      if (artBytes != null && artBytes.isNotEmpty) {
        artUri = await _saveCoverArtCache(filePath, artBytes, coverCacheDirPath);
      }

      final fallback = _fallbackFromFilename(filePath);
      return AudioMetadataResult(
        title: title ?? fallback.title,
        artist: artist ?? fallback.artist,
        album: album ?? fallback.album,
        albumArtUri: artUri,
        albumArtBytes: artBytes,
        lyrics: lyrics,
      );
    } catch (_) {
      return null;
    }
  }

  /// OGG/Opus 的注释头包在 OggS 页结构里：Vorbis 以 `\x03vorbis` 开头，
  /// Opus 以 `OpusTags` 开头。直接把整段页流喂给裸 Vorbis 注释解析器会把
  /// "OggS" 魔数当成 vendor 长度（~1.4GB），导致 OGG/Opus 元数据永远解析
  /// 失败。这里先定位注释头包，再从包体解析。
  static Map<String, String> _parseOggVorbisComments(Uint8List data) {
    final vorbisMarker = <int>[0x03, ...'vorbis'.codeUnits];
    final opusMarker = 'OpusTags'.codeUnits;
    var start = _indexOfBytes(data, vorbisMarker);
    var markerLen = vorbisMarker.length;
    final opusStart = _indexOfBytes(data, opusMarker);
    if (start == null || (opusStart != null && opusStart < start)) {
      start = opusStart;
      markerLen = opusMarker.length;
    }
    if (start == null) return const {};
    return _parseVorbisComments(
      Uint8List.fromList(data.sublist(start + markerLen)),
    );
  }

  static int? _indexOfBytes(Uint8List data, List<int> pattern) {
    if (pattern.isEmpty || data.length < pattern.length) return null;
    outer:
    for (var i = 0; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return null;
  }

  /// Standard Vorbis-comment lyric fields (FLAC / OGG / Opus).
  static String? _vorbisLyrics(Map<String, String> comments) {
    final value =
        comments['LYRICS'] ??
        comments['UNSYNCEDLYRICS'] ??
        comments['UNSYNCED LYRICS'];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  // ==========================================
  // 4. ID3v2 Parser (MP3, WAV, FLAC wrappers)
  // ==========================================
  static Future<AudioMetadataResult?> _parseId3v2(
    File file,
    Uint8List headerBytes,
    String filePath,
    String coverCacheDirPath,
  ) async {
    final version = headerBytes[3];
    final tagSize = _readSynchsafeInt(headerBytes, 6);
    if (tagSize <= 0 || tagSize > _maxTagBytes) return null;

    final Uint8List data;
    if (10 + tagSize <= headerBytes.length) {
      data = Uint8List.sublistView(headerBytes, 10, 10 + tagSize);
    } else {
      data = await _readFileSlice(file, 10, tagSize);
    }

    String? title;
    String? artist;
    String? album;
    int durationMs = 0;
    Uint8List? artBytes;
    int? year;
    String? lyrics;

    int offset = 0;
    while (offset + 10 < data.length) {
      if (data[offset] == 0) {
        offset++;
        continue;
      }

      String frameId = '';
      int frameSize = 0;

      if (version == 2) {
        if (offset + 6 > data.length) break;
        frameId = String.fromCharCodes(data.sublist(offset, offset + 3));
        frameSize =
            (data[offset + 3] << 16) |
            (data[offset + 4] << 8) |
            data[offset + 5];
        offset += 6;
      } else {
        if (offset + 10 > data.length) break;
        frameId = String.fromCharCodes(data.sublist(offset, offset + 4));
        if (version == 4) {
          frameSize = _readSynchsafeInt(data, offset + 4);
        } else {
          frameSize =
              (data[offset + 4] << 24) |
              (data[offset + 5] << 16) |
              (data[offset + 6] << 8) |
              data[offset + 7];
        }
        offset += 10;
      }

      if (frameSize <= 0 || offset + frameSize > data.length) break;

      final frameData = data.sublist(offset, offset + frameSize);
      offset += frameSize;

      if (frameId == 'TIT2' || frameId == 'TT2') {
        title = _decodeTextFrame(frameData);
      } else if (frameId == 'TPE1' || frameId == 'TP1') {
        artist = _decodeTextFrame(frameData);
      } else if (frameId == 'TALB' || frameId == 'TAL') {
        album = _decodeTextFrame(frameData);
      } else if (frameId == 'TLEN') {
        final lenStr = _decodeTextFrame(frameData);
        durationMs = int.tryParse(lenStr) ?? 0;
      } else if (frameId == 'TYER' || frameId == 'TDRC') {
        final yearStr = _decodeTextFrame(frameData);
        if (yearStr.length >= 4) {
          year = int.tryParse(yearStr.substring(0, 4));
        }
      } else if (frameId == 'USLT' || frameId == 'ULT') {
        lyrics ??= _decodeUnsyncedLyricsFrame(frameData);
      } else if (frameId == 'APIC' || frameId == 'PIC') {
        artBytes = _extractApicArtwork(frameData, isV22: version == 2);
      }
    }

    if (durationMs <= 0) {
      // MP3 帧扫描只对真正的 MP3 有意义：对带 ID3 头的 WAV/FLAC 会在
      // PCM/其他数据里误认 MPEG 同步字得出垃圾时长，顶掉按容器算出的
      // 正确结果（dispatcher 只在 durationMs<=0 时才走容器算法）。
      final ext = p.extension(filePath).toLowerCase();
      if (ext == '.mp3' || ext.isEmpty) {
        durationMs = await _calculateMp3Duration(file, 10 + tagSize);
      } else if (ext == '.wav') {
        durationMs = await _calculateWavDurationAfter(file, 10 + tagSize);
      } else if (ext == '.flac') {
        durationMs = await _calculateFlacDurationAfter(file, 10 + tagSize);
      }
    }

    String? artUri;
    if (artBytes != null && artBytes.isNotEmpty) {
      artUri = await _saveCoverArtCache(filePath, artBytes, coverCacheDirPath);
    }

    final fallback = _fallbackFromFilename(filePath);
    return AudioMetadataResult(
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : fallback.title,
      artist: (artist != null && artist.trim().isNotEmpty)
          ? artist.trim()
          : fallback.artist,
      album: (album != null && album.trim().isNotEmpty)
          ? album.trim()
          : fallback.album,
      durationMs: durationMs > 0 ? durationMs : fallback.durationMs,
      albumArtUri: artUri,
      albumArtBytes: artBytes,
      year: year,
      lyrics: lyrics,
    );
  }

  /// Decodes an ID3v2 USLT (unsynchronized lyrics) frame:
  /// [encoding:1][language:3][content descriptor:\0][lyrics text].
  static String? _decodeUnsyncedLyricsFrame(Uint8List frameData) {
    if (frameData.length < 5) return null;
    final encoding = frameData[0];
    try {
      final textStart = _skipNullTerminatedString(frameData, 4, encoding);
      if (textStart >= frameData.length) return null;
      final text = _decodeString(frameData.sublist(textStart), encoding);
      final cleaned = text.replaceAll('\u0000', '').trim();
      return cleaned.isEmpty ? null : cleaned;
    } catch (_) {
      return null;
    }
  }

  static Future<int> _calculateMp3Duration(File file, int tagSize) async {
    try {
      final fileLength = await file.length();
      if (fileLength <= tagSize) return 0;

      final readLen = (fileLength - tagSize) > 65536
          ? 65536
          : (fileLength - tagSize);
      final bytes = await _readFileSlice(file, tagSize, readLen);

      const bitratesV1L3 = [
        0,
        32,
        40,
        48,
        56,
        64,
        80,
        96,
        112,
        128,
        160,
        192,
        224,
        256,
        320,
        0,
      ];
      const sampleRatesV1 = [44100, 48000, 32000, 0];
      const bitratesV2L3 = [
        0,
        8,
        16,
        24,
        32,
        40,
        48,
        56,
        64,
        80,
        96,
        112,
        128,
        144,
        160,
        0,
      ];
      const sampleRatesV2 = [22050, 24000, 16000, 0];

      for (int i = 0; i + 4 < bytes.length; i++) {
        if (bytes[i] == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) {
          final mpegVersion = (bytes[i + 1] >> 3) & 0x03;
          final layer = (bytes[i + 1] >> 1) & 0x03;
          if (layer != 1) continue;

          final bitrateIdx = (bytes[i + 2] >> 4) & 0x0F;
          final sampleRateIdx = (bytes[i + 2] >> 2) & 0x03;
          final isMono = ((bytes[i + 3] >> 6) & 0x03) == 3;

          final bitrate = (mpegVersion == 3)
              ? bitratesV1L3[bitrateIdx]
              : bitratesV2L3[bitrateIdx];
          final sampleRate = (mpegVersion == 3)
              ? sampleRatesV1[sampleRateIdx]
              : sampleRatesV2[sampleRateIdx];

          if (bitrate == 0 || sampleRate == 0) continue;

          // Check Xing / Info Header
          final xingOffset = (mpegVersion == 3)
              ? (isMono ? i + 21 : i + 36)
              : (isMono ? i + 13 : i + 21);
          if (xingOffset + 12 <= bytes.length) {
            final headerTag = String.fromCharCodes(
              bytes.sublist(xingOffset, xingOffset + 4),
            );
            if (headerTag == 'Xing' || headerTag == 'Info') {
              final flags =
                  (bytes[xingOffset + 4] << 24) |
                  (bytes[xingOffset + 5] << 16) |
                  (bytes[xingOffset + 6] << 8) |
                  bytes[xingOffset + 7];
              if ((flags & 0x0001) != 0 && xingOffset + 12 <= bytes.length) {
                final frames =
                    (bytes[xingOffset + 8] << 24) |
                    (bytes[xingOffset + 9] << 16) |
                    (bytes[xingOffset + 10] << 8) |
                    bytes[xingOffset + 11];
                final samplesPerFrame = (mpegVersion == 3) ? 1152 : 576;
                if (frames > 0 && sampleRate > 0) {
                  return ((frames * samplesPerFrame * 1000) / sampleRate)
                      .toInt();
                }
              }
            }
          }

          // Check VBRI Header
          final vbriOffset = i + 36;
          if (vbriOffset + 18 <= bytes.length &&
              bytes[vbriOffset] == 0x56 &&
              bytes[vbriOffset + 1] == 0x42 &&
              bytes[vbriOffset + 2] == 0x52 &&
              bytes[vbriOffset + 3] == 0x49) {
            final frames =
                (bytes[vbriOffset + 14] << 24) |
                (bytes[vbriOffset + 15] << 16) |
                (bytes[vbriOffset + 16] << 8) |
                bytes[vbriOffset + 17];
            final samplesPerFrame = (mpegVersion == 3) ? 1152 : 576;
            if (frames > 0 && sampleRate > 0) {
              return ((frames * samplesPerFrame * 1000) / sampleRate).toInt();
            }
          }

          // Fallback CBR estimation from audio data size and bitrate
          final audioDataSize = fileLength - tagSize;
          if (audioDataSize > 0 && bitrate > 0) {
            return ((audioDataSize * 8 * 1000) / (bitrate * 1000)).toInt();
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  static Future<int> _calculateWavDuration(
    File file,
    Uint8List header, {
    int dataStart = 44,
  }) async {
    try {
      if (header.length < 44) return 0;
      if (String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
        return 0;
      }
      final byteRate =
          (header[28]) |
          (header[29] << 8) |
          (header[30] << 16) |
          (header[31] << 24);
      final fileSize = await file.length();
      if (byteRate > 0 && fileSize > dataStart) {
        return (((fileSize - dataStart) * 1000) ~/ byteRate);
      }
    } catch (_) {}
    return 0;
  }

  /// WAV 带 ID3v2 前导时，RIFF 头在标签之后——从标签尾读头部再算时长。
  static Future<int> _calculateWavDurationAfter(File file, int start) async {
    try {
      final headerBytes = await _readFileSlice(file, start, 64);
      return await _calculateWavDuration(
        file,
        headerBytes,
        dataStart: start + 44,
      );
    } catch (_) {
      return 0;
    }
  }

  /// FLAC 带 ID3v2 前导时，dispatcher 的 fLaC 魔数检测看不到流头——
  /// 从标签尾定位 STREAMINFO 块补算时长。
  static Future<int> _calculateFlacDurationAfter(File file, int start) async {
    try {
      final data = await _readFileSlice(file, start, 65536);
      if (data.length < 26 ||
          data[0] != 0x66 ||
          data[1] != 0x4C ||
          data[2] != 0x61 ||
          data[3] != 0x43) {
        return 0;
      }
      int offset = 4;
      while (offset + 4 <= data.length) {
        final headerByte = data[offset];
        final isLast = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;
        final blockLength =
            (data[offset + 1] << 16) |
            (data[offset + 2] << 8) |
            data[offset + 3];
        offset += 4;
        if (blockType == 0) {
          if (offset + blockLength > data.length) return 0;
          return _parseFlacStreamInfo(
            data.sublist(offset, offset + blockLength),
          );
        }
        if (isLast) break;
        offset += blockLength;
      }
    } catch (_) {}
    return 0;
  }

  static Future<AudioMetadataResult?> _parseId3v1(
    File file,
    String filePath,
  ) async {
    try {
      final len = await file.length();
      if (len < 128) return null;

      final id3v1Bytes = await _readFileSlice(file, len - 128, 128);
      if (id3v1Bytes.length == 128 &&
          id3v1Bytes[0] == 0x54 && // 'T'
          id3v1Bytes[1] == 0x41 && // 'A'
          id3v1Bytes[2] == 0x47) {
        // 'G'
        final title = latin1
            .decode(id3v1Bytes.sublist(3, 33))
            .replaceAll('\u0000', '')
            .trim();
        final artist = latin1
            .decode(id3v1Bytes.sublist(33, 63))
            .replaceAll('\u0000', '')
            .trim();
        final album = latin1
            .decode(id3v1Bytes.sublist(63, 93))
            .replaceAll('\u0000', '')
            .trim();
        final yearStr = latin1
            .decode(id3v1Bytes.sublist(93, 97))
            .replaceAll('\u0000', '')
            .trim();

        final fallback = _fallbackFromFilename(filePath);
        return AudioMetadataResult(
          title: title.isNotEmpty ? title : fallback.title,
          artist: artist.isNotEmpty ? artist : fallback.artist,
          album: album.isNotEmpty ? album : fallback.album,
          year: int.tryParse(yearStr),
        );
      }
    } catch (_) {}
    return null;
  }

  static Uint8List? _extractApicArtwork(
    Uint8List frameData, {
    bool isV22 = false,
  }) {
    if (frameData.length < 5) return null;
    final encoding = frameData[0];
    int offset = 1;

    if (isV22) {
      offset += 3;
      offset += 1;
      offset = _skipNullTerminatedString(frameData, offset, encoding);
    } else {
      while (offset < frameData.length && frameData[offset] != 0) {
        offset++;
      }
      offset++;
      if (offset >= frameData.length) return null;
      offset += 1;
      offset = _skipNullTerminatedString(frameData, offset, encoding);
    }

    if (offset < frameData.length) {
      return Uint8List.fromList(frameData.sublist(offset));
    }
    return null;
  }

  static int _skipNullTerminatedString(
    Uint8List data,
    int offset,
    int encoding,
  ) {
    if (encoding == 1 || encoding == 2) {
      while (offset + 1 < data.length) {
        if (data[offset] == 0 && data[offset + 1] == 0) {
          return offset + 2;
        }
        offset += 2;
      }
      return data.length;
    } else {
      while (offset < data.length) {
        if (data[offset] == 0) {
          return offset + 1;
        }
        offset++;
      }
      return data.length;
    }
  }

  static String _decodeTextFrame(Uint8List frameData) {
    if (frameData.isEmpty) return '';
    final encoding = frameData[0];
    return _decodeString(frameData.sublist(1), encoding);
  }

  /// Decodes tag text bytes with the given ID3 encoding byte
  /// (0 = latin1, 1 = UTF-16 w/ BOM, 2 = UTF-16BE, 3 = UTF-8).
  static String _decodeString(Uint8List content, int encoding) {
    try {
      if (encoding == 0) {
        return latin1.decode(content).replaceAll('\u0000', '');
      } else if (encoding == 1) {
        if (content.length >= 2) {
          final isLE = content[0] == 0xFF && content[1] == 0xFE;
          final uint16List = <int>[];
          for (int i = 2; i + 1 < content.length; i += 2) {
            final val = isLE
                ? (content[i] | (content[i + 1] << 8))
                : ((content[i] << 8) | content[i + 1]);
            if (val != 0) uint16List.add(val);
          }
          return String.fromCharCodes(uint16List);
        }
      } else if (encoding == 2) {
        final uint16List = <int>[];
        for (int i = 0; i + 1 < content.length; i += 2) {
          final val = (content[i] << 8) | content[i + 1];
          if (val != 0) uint16List.add(val);
        }
        return String.fromCharCodes(uint16List);
      } else if (encoding == 3) {
        return utf8
            .decode(content, allowMalformed: true)
            .replaceAll('\u0000', '');
      }
    } catch (_) {}

    return latin1.decode(content).replaceAll('\u0000', '');
  }

  static int _readSynchsafeInt(Uint8List bytes, int offset) {
    return ((bytes[offset] & 0x7F) << 21) |
        ((bytes[offset + 1] & 0x7F) << 14) |
        ((bytes[offset + 2] & 0x7F) << 7) |
        (bytes[offset + 3] & 0x7F);
  }

  // ==========================================
  // 5. Local Folder Artwork Scanner
  // ==========================================
  static Future<String?> _findLocalDirectoryCover(
    String audioFilePath, {
    Map<String, List<String>>? dirImageCache,
  }) async {
    try {
      final dirPath = p.dirname(audioFilePath);
      final songBaseName = p
          .basenameWithoutExtension(audioFilePath)
          .toLowerCase();

      List<String>? cachedImages = dirImageCache?[dirPath];
      if (cachedImages == null) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          dirImageCache?[dirPath] = const [];
          return null;
        }
        final listed = <String>[];
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.jpg' ||
                ext == '.jpeg' ||
                ext == '.png' ||
                ext == '.webp') {
              listed.add(entity.path);
            }
          }
        }
        dirImageCache?[dirPath] = listed;
        cachedImages = listed;
      }

      if (cachedImages.isEmpty) return null;

      final byLowerName = <String, String>{
        for (final path in cachedImages) p.basename(path).toLowerCase(): path,
      };
      final commonCoverNames = [
        'cover.jpg',
        'cover.png',
        'cover.jpeg',
        'cover.webp',
        'folder.jpg',
        'folder.png',
        'folder.jpeg',
        'album.jpg',
        'album.png',
        'album.jpeg',
        'front.jpg',
        'front.png',
        'front.jpeg',
        '$songBaseName.jpg',
        '$songBaseName.png',
        '$songBaseName.jpeg',
      ];

      for (final name in commonCoverNames) {
        final matched = byLowerName[name];
        if (matched != null) {
          return File(matched).uri.toString();
        }
      }
      return File(cachedImages.first).uri.toString();
    } catch (_) {}
    return null;
  }

  static Future<String?> _saveCoverArtCache(
    String filePath,
    Uint8List artBytes,
    String coverCacheDirPath,
  ) async {
    try {
      if (coverCacheDirPath.isEmpty) return null;
      final coverDir = Directory(p.join(coverCacheDirPath, 'covers'));
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(filePath)).toString();
      final coverFile = File(p.join(coverDir.path, 'cover_$hash.jpg'));
      if (await coverFile.exists() &&
          (await coverFile.length()) == artBytes.length) {
        return coverFile.uri.toString();
      }
      await coverFile.writeAsBytes(artBytes);
      return coverFile.uri.toString(); // file:///...
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 6. Watermark Filter & Fallback Normalization
  // ==========================================
  static bool _isWatermark(String str) {
    final lower = str.trim().toLowerCase();
    const watermarks = [
      'kuwo',
      'kw',
      '酷我',
      '酷我音乐',
      'kugou',
      'kg',
      '酷狗',
      '酷狗音乐',
      'netease',
      'cloudmusic',
      '网易云',
      '网易云音乐',
      'qqmusic',
      'qq音乐',
      'yqq',
      'unknown',
      '未知歌手',
      '未知专辑',
      '未知曲目',
      '本地歌曲',
      '本地音乐',
    ];
    return watermarks.contains(lower) ||
        lower.startsWith('kuwo_') ||
        lower.startsWith('kw_') ||
        lower.startsWith('kg_');
  }

  static final RegExp _leadingTrackRegex = RegExp(r'^\s*\d+[\.\s\-_]+');
  static final RegExp _squareQualityRegex = RegExp(
    r'\[.*?(flac|320k|128k|24bit|96k|hq|sq|lossless|cd|hires|hi-res|kuwo|kugou|qqmusic|网易云|酷我|酷狗).*?\]',
    caseSensitive: false,
  );
  static final RegExp _roundQualityRegex = RegExp(
    r'\(.*?(flac|320k|128k|24bit|96k|hq|sq|lossless|cd|hires|hi-res|kuwo|kugou|qqmusic|网易云|酷我|酷狗).*?\)',
    caseSensitive: false,
  );
  static final RegExp _chineseQualityRegex = RegExp(
    r'【.*?(高音质|无损|官方|原版|独家|首发|超清|重制).*?】',
    caseSensitive: false,
  );
  static final RegExp _prefixNoiseRegex = RegExp(
    r'^\s*(kw|kuwo|kg)[\s\-_]+',
    caseSensitive: false,
  );

  static String cleanTrackName(String raw) {
    // 剥掉文件名里的前置曲目号：'01. '、'01 - '。只用于文件名回退，
    // 内嵌标题走 [_stripQualityNoise]，否则会误伤 "7 Years"、"99 Luftballons"
    // 这类以数字开头的真实歌名。
    return _stripQualityNoise(raw.replaceAll(_leadingTrackRegex, ''));
  }

  /// 去掉音质标注与下载站噪声，但不动前置曲目号。
  static String _stripQualityNoise(String raw) {
    return raw
        .replaceAll(_squareQualityRegex, '')
        .replaceAll(_roundQualityRegex, '')
        .replaceAll(_chineseQualityRegex, '')
        .replaceAll(_prefixNoiseRegex, '')
        .trim();
  }

  static AudioMetadataResult _sanitizeResult(
    AudioMetadataResult res,
    String filePath,
  ) {
    final fallback = _fallbackFromFilename(filePath);

    // 内嵌标题是权威数据：只清音质噪声，不剥前置曲目号。
    String title = _stripQualityNoise(res.title);
    String artist = res.artist.trim();
    String album = res.album.trim();

    if (title.isEmpty || _isWatermark(title)) {
      title = fallback.title;
    }

    if (artist.isEmpty || _isWatermark(artist)) {
      artist = fallback.artist;
    }

    if (album.isEmpty || _isWatermark(album)) {
      album = fallback.album;
    }

    final hasCachedUri =
        res.albumArtUri != null && res.albumArtUri!.isNotEmpty;
    return AudioMetadataResult(
      title: title,
      artist: artist,
      album: album,
      durationMs: res.durationMs > 0 ? res.durationMs : fallback.durationMs,
      albumArtUri: res.albumArtUri,
      // Drop raw embedded art bytes once cached to disk to prevent OOM across
      // isolate transfers and library state retention.
      albumArtBytes: hasCachedUri ? null : res.albumArtBytes,
      year: res.year,
      lyrics: res.lyrics,
    );
  }

  static AudioMetadataResult _fallbackFromFilename(String filePath) {
    String rawName = p.basenameWithoutExtension(filePath);
    rawName = cleanTrackName(rawName);

    if (rawName.contains(' - ')) {
      final parts = rawName.split(' - ');
      final p0 = parts[0].trim();
      final p1 = parts.sublist(1).join(' - ').trim();

      final artist = !_isWatermark(p0) ? p0 : '未知歌手';
      final title = !_isWatermark(p1) ? p1 : p0;

      return AudioMetadataResult(
        title: title.isNotEmpty ? title : rawName,
        artist: artist,
        album: '本地音乐',
      );
    }

    return AudioMetadataResult(
      title: rawName.isNotEmpty ? rawName : '本地歌曲',
      artist: '未知歌手',
      album: '本地音乐',
    );
  }
}
