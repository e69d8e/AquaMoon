import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
    );
  }

  void dispose() {
    _client.close();
  }
}
