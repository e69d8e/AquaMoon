import 'dart:convert';
import 'dart:io';
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

  const AudioMetadataResult({
    required this.title,
    required this.artist,
    required this.album,
    this.durationMs = 0,
    this.albumArtUri,
    this.albumArtBytes,
    this.year,
  });
}

class MetadataExtractor {
  /// Extracts metadata and embedded artwork from a local audio file (.mp3, .flac, .m4a, .ogg, .wav, etc.)
  static Future<AudioMetadataResult> extractFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return _fallbackFromFilename(filePath);
    }

    try {
      final ext = p.extension(filePath).toLowerCase();

      // Read up to first 2MB for header analysis (large enough for high-res cover art in metadata)
      final length = await file.length();
      final readLen = length > (2 * 1024 * 1024) ? (2 * 1024 * 1024) : length;
      final headerBytes = await file.openRead(0, readLen).fold<List<int>>([], (prev, elem) => prev..addAll(elem));
      final uint8 = Uint8List.fromList(headerBytes);

      AudioMetadataResult? result;

      // 1. FLAC format (Magic 'fLaC' = 0x66, 0x4C, 0x61, 0x43)
      if (ext == '.flac' || (uint8.length >= 4 && uint8[0] == 0x66 && uint8[1] == 0x4C && uint8[2] == 0x61 && uint8[3] == 0x43)) {
        result = await _parseFlac(file, uint8, filePath);
      }
      // 2. MP4 / M4A / AAC container (contains 'ftyp' or 'moov' or ext .m4a/.aac)
      else if (ext == '.m4a' || ext == '.aac' || ext == '.mp4' || (uint8.length >= 8 && (uint8[4] == 0x66 && uint8[5] == 0x74 && uint8[6] == 0x79 && uint8[7] == 0x70))) {
        result = await _parseM4a(file, uint8, filePath);
      }
      // 3. ID3v2 (MP3, WAV with ID3 chunk, or FLAC with ID3 wrapper)
      else if (uint8.length >= 10 && uint8[0] == 0x49 && uint8[1] == 0x44 && uint8[2] == 0x33) {
        result = await _parseId3v2(file, uint8, filePath);
      }
      // 4. OGG / Opus container
      else if (ext == '.ogg' || ext == '.opus' || (uint8.length >= 4 && uint8[0] == 0x4F && uint8[1] == 0x67 && uint8[2] == 0x67 && uint8[3] == 0x53)) {
        result = await _parseOgg(file, uint8, filePath);
      }

      // 5. Fallback to ID3v1 for MP3
      if (result == null || result.title == '未知曲目' || _isWatermark(result.title)) {
        final id3v1 = await _parseId3v1(file, filePath);
        if (id3v1 != null) {
          result = id3v1;
        }
      }

      // 6. If no embedded cover art found, search local directory for folder.jpg / cover.jpg / album.jpg
      if (result == null || result.albumArtUri == null) {
        final folderCoverUri = await _findLocalDirectoryCover(filePath);
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
  static Future<AudioMetadataResult?> _parseFlac(File file, Uint8List data, String filePath) async {
    try {
      if (data.length < 4 || data[0] != 0x66 || data[1] != 0x4C || data[2] != 0x61 || data[3] != 0x43) {
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

      while (!isLast && offset + 4 <= data.length) {
        final headerByte = data[offset];
        isLast = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;
        final blockLength = (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
        offset += 4;

        if (offset + blockLength > data.length) {
          final fullBlock = await file.openRead(offset, offset + blockLength).fold<List<int>>([], (p, e) => p..addAll(e));
          final blockData = Uint8List.fromList(fullBlock);
          offset += blockLength;

          if (blockType == 0) {
            durationMs = _parseFlacStreamInfo(blockData);
          } else if (blockType == 4) {
            final comments = _parseVorbisComments(blockData);
            title ??= comments['TITLE'] ?? comments['title'];
            artist ??= comments['ARTIST'] ?? comments['artist'];
            album ??= comments['ALBUM'] ?? comments['album'];
            final yearStr = comments['DATE'] ?? comments['date'] ?? comments['YEAR'] ?? comments['year'];
            if (yearStr != null && yearStr.length >= 4) {
              year ??= int.tryParse(yearStr.substring(0, 4));
            }
            if (comments.containsKey('METADATA_BLOCK_PICTURE')) {
              try {
                final picBase64 = comments['METADATA_BLOCK_PICTURE']!;
                artBytes ??= _parseFlacPictureBlock(base64.decode(picBase64));
              } catch (_) {}
            }
          } else if (blockType == 6) {
            artBytes ??= _parseFlacPictureBlock(blockData);
          }
        } else {
          final blockData = data.sublist(offset, offset + blockLength);
          offset += blockLength;

          if (blockType == 0) {
            durationMs = _parseFlacStreamInfo(blockData);
          } else if (blockType == 4) {
            final comments = _parseVorbisComments(blockData);
            title ??= comments['TITLE'] ?? comments['title'];
            artist ??= comments['ARTIST'] ?? comments['artist'];
            album ??= comments['ALBUM'] ?? comments['album'];
            final yearStr = comments['DATE'] ?? comments['date'] ?? comments['YEAR'] ?? comments['year'];
            if (yearStr != null && yearStr.length >= 4) {
              year ??= int.tryParse(yearStr.substring(0, 4));
            }
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
      }

      String? artUri;
      if (artBytes != null && artBytes.isNotEmpty) {
        artUri = await _saveCoverArtCache(filePath, artBytes);
      }

      final fallback = _fallbackFromFilename(filePath);
      return AudioMetadataResult(
        title: (title != null && title.trim().isNotEmpty) ? title.trim() : fallback.title,
        artist: (artist != null && artist.trim().isNotEmpty) ? artist.trim() : fallback.artist,
        album: (album != null && album.trim().isNotEmpty) ? album.trim() : fallback.album,
        durationMs: durationMs > 0 ? durationMs : fallback.durationMs,
        albumArtUri: artUri,
        albumArtBytes: artBytes,
        year: year,
      );
    } catch (_) {
      return null;
    }
  }

  static int _parseFlacStreamInfo(Uint8List block) {
    if (block.length < 18) return 0;
    final sampleRate = (block[10] << 12) | (block[11] << 4) | (block[12] >> 4);
    final totalSamples = ((block[13] & 0x0F) * 4294967296) +
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
    final vendorLen = block[offset] | (block[offset + 1] << 8) | (block[offset + 2] << 16) | (block[offset + 3] << 24);
    offset += 4 + vendorLen;

    if (offset + 4 > block.length) return result;
    final commentCount = block[offset] | (block[offset + 1] << 8) | (block[offset + 2] << 16) | (block[offset + 3] << 24);
    offset += 4;

    for (int i = 0; i < commentCount && offset + 4 <= block.length; i++) {
      final len = block[offset] | (block[offset + 1] << 8) | (block[offset + 2] << 16) | (block[offset + 3] << 24);
      offset += 4;
      if (offset + len > block.length) break;

      final commentStr = utf8.decode(block.sublist(offset, offset + len), allowMalformed: true);
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
      final mimeLen = (block[offset] << 24) | (block[offset + 1] << 16) | (block[offset + 2] << 8) | block[offset + 3];
      if (mimeLen < 0 || offset + 4 + mimeLen > block.length) return null;
      offset += 4 + mimeLen;

      if (offset + 4 > block.length) return null;
      final descLen = (block[offset] << 24) | (block[offset + 1] << 16) | (block[offset + 2] << 8) | block[offset + 3];
      if (descLen < 0 || offset + 4 + descLen > block.length) return null;
      offset += 4 + descLen;

      // Skip width (4), height (4), depth (4), colors (4) = 16 bytes
      if (offset + 16 + 4 > block.length) return null;
      offset += 16;

      final dataLen = (block[offset] << 24) | (block[offset + 1] << 16) | (block[offset + 2] << 8) | block[offset + 3];
      offset += 4;

      if (dataLen > 0 && offset + dataLen <= block.length) {
        return Uint8List.fromList(block.sublist(offset, offset + dataLen));
      }
    } catch (_) {}
    return null;
  }

  // ==========================================
  // 2. M4A / AAC (MP4 Metadata ilst & covr & mvhd duration)
  // ==========================================
  static Future<AudioMetadataResult?> _parseM4a(File file, Uint8List data, String filePath) async {
    try {
      String? title;
      String? artist;
      String? album;
      Uint8List? artBytes;
      int? year;
      int durationMs = 0;

      int i = 0;
      while (i + 8 < data.length) {
        final boxSize = (data[i] << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | data[i + 3];
        if (boxSize <= 0 || i + boxSize > data.length) {
          i++;
          continue;
        }

        final boxType = String.fromCharCodes(data.sublist(i + 4, i + 8));

        if (boxType == 'mvhd' && i + 24 <= data.length) {
          final version = data[i + 8];
          if (version == 0 && i + 28 <= data.length) {
            final timescale = (data[i + 20] << 24) | (data[i + 21] << 16) | (data[i + 22] << 8) | data[i + 23];
            final duration = (data[i + 24] << 24) | (data[i + 25] << 16) | (data[i + 26] << 8) | data[i + 27];
            if (timescale > 0) {
              durationMs = ((duration * 1000) / timescale).toInt();
            }
          } else if (version == 1 && i + 36 <= data.length) {
            final timescale = (data[i + 28] << 24) | (data[i + 29] << 16) | (data[i + 30] << 8) | data[i + 31];
            final duration = ((data[i + 32] & 0x7F) << 56) |
                (data[i + 33] << 48) |
                (data[i + 34] << 40) |
                (data[i + 35] << 32) |
                (data[i + 36] << 24) |
                (data[i + 37] << 16) |
                (data[i + 38] << 8) |
                data[i + 39];
            if (timescale > 0) {
              durationMs = ((duration * 1000) / timescale).toInt();
            }
          }
        } else if (boxType == 'mdhd' && durationMs == 0 && i + 24 <= data.length) {
          final version = data[i + 8];
          if (version == 0 && i + 28 <= data.length) {
            final timescale = (data[i + 20] << 24) | (data[i + 21] << 16) | (data[i + 22] << 8) | data[i + 23];
            final duration = (data[i + 24] << 24) | (data[i + 25] << 16) | (data[i + 26] << 8) | data[i + 27];
            if (timescale > 0) {
              durationMs = ((duration * 1000) / timescale).toInt();
            }
          }
        } else if (boxType == '©nam' || (data[i + 4] == 0xA9 && data[i + 5] == 0x6E && data[i + 6] == 0x61 && data[i + 7] == 0x6D)) {
          title = _extractM4aString(data.sublist(i, i + boxSize));
        } else if (boxType == '©ART' || (data[i + 4] == 0xA9 && data[i + 5] == 0x41 && data[i + 6] == 0x52 && data[i + 7] == 0x54)) {
          artist = _extractM4aString(data.sublist(i, i + boxSize));
        } else if (boxType == '©alb' || (data[i + 4] == 0xA9 && data[i + 5] == 0x61 && data[i + 6] == 0x6C && data[i + 7] == 0x62)) {
          album = _extractM4aString(data.sublist(i, i + boxSize));
        } else if (boxType == '©day' || (data[i + 4] == 0xA9 && data[i + 5] == 0x64 && data[i + 6] == 0x61 && data[i + 7] == 0x79)) {
          final yearStr = _extractM4aString(data.sublist(i, i + boxSize));
          if (yearStr != null && yearStr.length >= 4) {
            year = int.tryParse(yearStr.substring(0, 4));
          }
        } else if (boxType == 'covr') {
          artBytes = _extractM4aCover(data.sublist(i, i + boxSize));
        }

        i += 4;
      }

      String? artUri;
      if (artBytes != null && artBytes.isNotEmpty) {
        artUri = await _saveCoverArtCache(filePath, artBytes);
      }

      final fallback = _fallbackFromFilename(filePath);
      return AudioMetadataResult(
        title: (title != null && title.trim().isNotEmpty) ? title.trim() : fallback.title,
        artist: (artist != null && artist.trim().isNotEmpty) ? artist.trim() : fallback.artist,
        album: (album != null && album.trim().isNotEmpty) ? album.trim() : fallback.album,
        durationMs: durationMs > 0 ? durationMs : fallback.durationMs,
        albumArtUri: artUri,
        albumArtBytes: artBytes,
        year: year,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractM4aString(Uint8List atom) {
    for (int i = 0; i + 16 <= atom.length; i++) {
      if (atom[i + 4] == 0x64 && atom[i + 5] == 0x61 && atom[i + 6] == 0x74 && atom[i + 7] == 0x61) {
        final dataLen = (atom[i] << 24) | (atom[i + 1] << 16) | (atom[i + 2] << 8) | atom[i + 3];
        if (i + dataLen <= atom.length && dataLen > 16) {
          final strBytes = atom.sublist(i + 16, i + dataLen);
          return utf8.decode(strBytes, allowMalformed: true).trim();
        }
      }
    }
    return null;
  }

  static Uint8List? _extractM4aCover(Uint8List atom) {
    for (int i = 0; i + 16 <= atom.length; i++) {
      if (atom[i + 4] == 0x64 && atom[i + 5] == 0x61 && atom[i + 6] == 0x74 && atom[i + 7] == 0x61) {
        final dataLen = (atom[i] << 24) | (atom[i + 1] << 16) | (atom[i + 2] << 8) | atom[i + 3];
        if (i + dataLen <= atom.length && dataLen > 16) {
          return Uint8List.fromList(atom.sublist(i + 16, i + dataLen));
        }
      }
    }
    return null;
  }

  // ==========================================
  // 3. OGG / Opus Parser
  // ==========================================
  static Future<AudioMetadataResult?> _parseOgg(File file, Uint8List data, String filePath) async {
    try {
      final comments = _parseVorbisComments(data);
      final title = comments['TITLE'] ?? comments['title'];
      final artist = comments['ARTIST'] ?? comments['artist'];
      final album = comments['ALBUM'] ?? comments['album'];

      Uint8List? artBytes;
      if (comments.containsKey('METADATA_BLOCK_PICTURE')) {
        try {
          artBytes = _parseFlacPictureBlock(base64.decode(comments['METADATA_BLOCK_PICTURE']!));
        } catch (_) {}
      }

      String? artUri;
      if (artBytes != null && artBytes.isNotEmpty) {
        artUri = await _saveCoverArtCache(filePath, artBytes);
      }

      final fallback = _fallbackFromFilename(filePath);
      return AudioMetadataResult(
        title: title ?? fallback.title,
        artist: artist ?? fallback.artist,
        album: album ?? fallback.album,
        albumArtUri: artUri,
        albumArtBytes: artBytes,
      );
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 4. ID3v2 Parser (MP3, WAV, FLAC wrappers)
  // ==========================================
  static Future<AudioMetadataResult?> _parseId3v2(File file, Uint8List headerBytes, String filePath) async {
    final version = headerBytes[3];
    final tagSize = _readSynchsafeInt(headerBytes, 6);
    if (tagSize <= 0) return null;

    final fullTagBytes = await file.openRead(10, 10 + tagSize).fold<List<int>>([], (prev, elem) => prev..addAll(elem));
    final data = Uint8List.fromList(fullTagBytes);

    String? title;
    String? artist;
    String? album;
    int durationMs = 0;
    Uint8List? artBytes;
    int? year;

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
        frameSize = (data[offset + 3] << 16) | (data[offset + 4] << 8) | data[offset + 5];
        offset += 6;
      } else {
        if (offset + 10 > data.length) break;
        frameId = String.fromCharCodes(data.sublist(offset, offset + 4));
        if (version == 4) {
          frameSize = _readSynchsafeInt(data, offset + 4);
        } else {
          frameSize = (data[offset + 4] << 24) |
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
      } else if (frameId == 'APIC' || frameId == 'PIC') {
        artBytes = _extractApicArtwork(frameData, isV22: version == 2);
      }
    }

    if (durationMs <= 0) {
      durationMs = await _calculateMp3Duration(file, 10 + tagSize);
    }

    String? artUri;
    if (artBytes != null && artBytes.isNotEmpty) {
      artUri = await _saveCoverArtCache(filePath, artBytes);
    }

    final fallback = _fallbackFromFilename(filePath);
    return AudioMetadataResult(
      title: (title != null && title.trim().isNotEmpty) ? title.trim() : fallback.title,
      artist: (artist != null && artist.trim().isNotEmpty) ? artist.trim() : fallback.artist,
      album: (album != null && album.trim().isNotEmpty) ? album.trim() : fallback.album,
      durationMs: durationMs > 0 ? durationMs : fallback.durationMs,
      albumArtUri: artUri,
      albumArtBytes: artBytes,
      year: year,
    );
  }

  static Future<int> _calculateMp3Duration(File file, int tagSize) async {
    try {
      final fileLength = await file.length();
      if (fileLength <= tagSize) return 0;

      final readLen = (fileLength - tagSize) > 65536 ? 65536 : (fileLength - tagSize);
      final audioBytes = await file.openRead(tagSize, tagSize + readLen).fold<List<int>>([], (p, e) => p..addAll(e));
      final bytes = Uint8List.fromList(audioBytes);

      const bitratesV1L3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0];
      const sampleRatesV1 = [44100, 48000, 32000, 0];
      const bitratesV2L3 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0];
      const sampleRatesV2 = [22050, 24000, 16000, 0];

      for (int i = 0; i + 4 < bytes.length; i++) {
        if (bytes[i] == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) {
          final mpegVersion = (bytes[i + 1] >> 3) & 0x03;
          final layer = (bytes[i + 1] >> 1) & 0x03;
          if (layer != 1) continue;

          final bitrateIdx = (bytes[i + 2] >> 4) & 0x0F;
          final sampleRateIdx = (bytes[i + 2] >> 2) & 0x03;
          final isMono = ((bytes[i + 3] >> 6) & 0x03) == 3;

          final bitrate = (mpegVersion == 3) ? bitratesV1L3[bitrateIdx] : bitratesV2L3[bitrateIdx];
          final sampleRate = (mpegVersion == 3) ? sampleRatesV1[sampleRateIdx] : sampleRatesV2[sampleRateIdx];

          if (bitrate == 0 || sampleRate == 0) continue;

          // Check Xing / Info Header
          final xingOffset = (mpegVersion == 3) ? (isMono ? i + 21 : i + 36) : (isMono ? i + 13 : i + 21);
          if (xingOffset + 12 <= bytes.length) {
            final headerTag = String.fromCharCodes(bytes.sublist(xingOffset, xingOffset + 4));
            if (headerTag == 'Xing' || headerTag == 'Info') {
              final flags = (bytes[xingOffset + 4] << 24) |
                  (bytes[xingOffset + 5] << 16) |
                  (bytes[xingOffset + 6] << 8) |
                  bytes[xingOffset + 7];
              if ((flags & 0x0001) != 0 && xingOffset + 12 <= bytes.length) {
                final frames = (bytes[xingOffset + 8] << 24) |
                    (bytes[xingOffset + 9] << 16) |
                    (bytes[xingOffset + 10] << 8) |
                    bytes[xingOffset + 11];
                final samplesPerFrame = (mpegVersion == 3) ? 1152 : 576;
                if (frames > 0 && sampleRate > 0) {
                  return ((frames * samplesPerFrame * 1000) / sampleRate).toInt();
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
            final frames = (bytes[vbriOffset + 14] << 24) |
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

  static Future<int> _calculateWavDuration(File file, Uint8List header) async {
    try {
      if (header.length < 44) return 0;
      if (String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
        return 0;
      }
      final byteRate = (header[28]) | (header[29] << 8) | (header[30] << 16) | (header[31] << 24);
      final fileSize = await file.length();
      if (byteRate > 0 && fileSize > 44) {
        return (((fileSize - 44) * 1000) ~/ byteRate);
      }
    } catch (_) {}
    return 0;
  }

  static Future<AudioMetadataResult?> _parseId3v1(File file, String filePath) async {
    try {
      final len = await file.length();
      if (len < 128) return null;

      final id3v1Bytes = await file.openRead(len - 128, len).fold<List<int>>([], (prev, elem) => prev..addAll(elem));
      if (id3v1Bytes.length == 128 &&
          id3v1Bytes[0] == 0x54 && // 'T'
          id3v1Bytes[1] == 0x41 && // 'A'
          id3v1Bytes[2] == 0x47) {  // 'G'
        final title = latin1.decode(id3v1Bytes.sublist(3, 33)).replaceAll('\u0000', '').trim();
        final artist = latin1.decode(id3v1Bytes.sublist(33, 63)).replaceAll('\u0000', '').trim();
        final album = latin1.decode(id3v1Bytes.sublist(63, 93)).replaceAll('\u0000', '').trim();
        final yearStr = latin1.decode(id3v1Bytes.sublist(93, 97)).replaceAll('\u0000', '').trim();

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

  static Uint8List? _extractApicArtwork(Uint8List frameData, {bool isV22 = false}) {
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

  static int _skipNullTerminatedString(Uint8List data, int offset, int encoding) {
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
    final content = frameData.sublist(1);

    try {
      if (encoding == 0) {
        return latin1.decode(content).replaceAll('\u0000', '');
      } else if (encoding == 1) {
        if (content.length >= 2) {
          final isLE = content[0] == 0xFF && content[1] == 0xFE;
          final uint16List = <int>[];
          for (int i = 2; i + 1 < content.length; i += 2) {
            final val = isLE ? (content[i] | (content[i + 1] << 8)) : ((content[i] << 8) | content[i + 1]);
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
        return utf8.decode(content, allowMalformed: true).replaceAll('\u0000', '');
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
  static Future<String?> _findLocalDirectoryCover(String audioFilePath) async {
    try {
      final dir = Directory(p.dirname(audioFilePath));
      if (!await dir.exists()) return null;

      final songBaseName = p.basenameWithoutExtension(audioFilePath).toLowerCase();
      final commonCoverNames = [
        'cover.jpg', 'cover.png', 'cover.jpeg', 'cover.webp',
        'folder.jpg', 'folder.png', 'folder.jpeg',
        'album.jpg', 'album.png', 'album.jpeg',
        'front.jpg', 'front.png', 'front.jpeg',
        '$songBaseName.jpg', '$songBaseName.png', '$songBaseName.jpeg',
      ];

      for (final name in commonCoverNames) {
        final coverFile = File(p.join(dir.path, name));
        if (await coverFile.exists()) {
          return coverFile.uri.toString();
        }
      }

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
            return entity.uri.toString();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _saveCoverArtCache(String filePath, Uint8List artBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final coverDir = Directory(p.join(tempDir.path, 'covers'));
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(filePath)).toString();
      final coverFile = File(p.join(coverDir.path, 'cover_$hash.jpg'));
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
      'kuwo', 'kw', '酷我', '酷我音乐',
      'kugou', 'kg', '酷狗', '酷狗音乐',
      'netease', 'cloudmusic', '网易云', '网易云音乐',
      'qqmusic', 'qq音乐', 'yqq',
      'unknown', '未知歌手', '未知专辑', '未知曲目', '本地歌曲', '本地音乐',
    ];
    return watermarks.contains(lower) || lower.startsWith('kuwo_') || lower.startsWith('kw_') || lower.startsWith('kg_');
  }

  static String cleanTrackName(String raw) {
    return raw
        .replaceAll(RegExp(r'^\s*\d+[\.\s\-_]+'), '') // Leading track numbers: '01. ', '01 - '
        .replaceAll(RegExp(r'\[.*?(flac|320k|128k|24bit|96k|hq|sq|lossless|cd|hires|hi-res|kuwo|kugou|qqmusic|网易云|酷我|酷狗).*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?(flac|320k|128k|24bit|96k|hq|sq|lossless|cd|hires|hi-res|kuwo|kugou|qqmusic|网易云|酷我|酷狗).*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'【.*?(高音质|无损|官方|原版|独家|首发|超清|重制).*?】', caseSensitive: false), '')
        .replaceAll(RegExp(r'^\s*(kw|kuwo|kg)[\s\-_]+', caseSensitive: false), '')
        .trim();
  }

  static AudioMetadataResult _sanitizeResult(AudioMetadataResult res, String filePath) {
    final fallback = _fallbackFromFilename(filePath);

    String title = cleanTrackName(res.title);
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

    return AudioMetadataResult(
      title: title,
      artist: artist,
      album: album,
      durationMs: res.durationMs > 0 ? res.durationMs : fallback.durationMs,
      albumArtUri: res.albumArtUri,
      albumArtBytes: res.albumArtBytes,
      year: res.year,
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
