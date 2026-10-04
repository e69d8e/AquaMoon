import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils/version_utils.dart';
import '../models/update_info.dart';

/// Checks GitHub Releases for a newer app version.
///
/// Returns `null` from [checkForUpdate] when the app is already up to date;
/// network / parsing failures throw so callers can tell "no update" apart
/// from "check failed" (manual check shows an error toast, auto check stays
/// silent).
class UpdateService {
  UpdateService({http.Client? client, String? apiUrl})
      : _client = client ?? http.Client(),
        _apiUrl = apiUrl ?? defaultApiUrl;

  static const String defaultApiUrl =
      'https://api.github.com/repos/e69d8e/AquaMoon/releases/latest';

  final http.Client _client;
  final String _apiUrl;

  /// Returns update info when [currentVersion] is behind the latest GitHub
  /// release, `null` when it is up to date. Throws on network or parse
  /// failure (including GitHub rate-limit 403 responses).
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersion,
  }) async {
    final response = await _client
        .get(
          Uri.parse(_apiUrl),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'AquaMoon-Update-Check',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('GitHub Releases 查询失败 (HTTP ${response.statusCode})');
    }

    final data = json.decode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('GitHub Releases 响应格式异常');
    }

    final tagName = data['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) {
      throw const FormatException('GitHub Release 缺少 tag_name');
    }

    // The `latest` endpoint only returns full releases; treat pre-release
    // tags defensively the same as their plain release number.
    if (VersionUtils.compareVersions(tagName, currentVersion) <= 0) {
      return null;
    }

    return AppUpdateInfo(
      latestVersion: VersionUtils.normalize(tagName),
      currentVersion: VersionUtils.normalize(currentVersion),
      releaseTitle: data['name'] as String? ?? '',
      releaseNotes: data['body'] as String? ?? '',
      releaseUrl: data['html_url'] as String? ??
          'https://github.com/e69d8e/AquaMoon/releases',
      apkUrl: _findApkAssetUrl(data['assets']),
    );
  }

  /// Picks the `.apk` release asset so Android users can download and install
  /// the update in-app instead of leaving for the browser.
  ///
  /// Releases ship several per-ABI APKs plus a Universal one, and GitHub
  /// returns assets in arbitrary order — blindly taking the first `.apk`
  /// would hand e.g. an armeabi-v7a device an arm64-only package the
  /// installer rejects. Prefer the Universal APK; fall back to the first
  /// `.apk` only when no Universal asset exists.
  static String? _findApkAssetUrl(Object? assets) {
    if (assets is! List) return null;
    String? firstApk;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String?;
      if (name.toLowerCase().endsWith('.apk') &&
          url != null &&
          url.isNotEmpty) {
        if (name.toLowerCase().contains('universal')) {
          return url;
        }
        firstApk ??= url;
      }
    }
    return firstApk;
  }

  /// Streams the release APK into the app cache directory, reporting progress
  /// through [onProgress] (received bytes, total bytes or null when the
  /// server omits Content-Length). Returns the written file path.
  Future<String> downloadApk({
    required String url,
    required String version,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('APK 下载失败 (HTTP ${response.statusCode})');
    }

    final total = response.contentLength;
    final tempDir = await getTemporaryDirectory();
    final file = File(
      p.join(tempDir.path, 'aquamoon_v${VersionUtils.normalize(version)}.apk'),
    );
    final sink = file.openWrite();

    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      try {
        await file.delete();
      } catch (_) {}
      rethrow;
    }

    if (total != null && received < total) {
      try {
        await file.delete();
      } catch (_) {}
      throw Exception('APK 下载不完整');
    }
    return file.path;
  }

  void dispose() {
    _client.close();
  }
}
