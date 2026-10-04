/// A new version discovered from GitHub Releases. Not persisted —
/// fetched fresh on every update check.
class AppUpdateInfo {
  /// Normalized latest version, e.g. `1.1.0`.
  final String latestVersion;

  /// Normalized version the app is currently running.
  final String currentVersion;

  /// Release title from GitHub, may be empty.
  final String releaseTitle;

  /// Release notes body (GitHub auto-generated markdown), shown as plain text.
  final String releaseNotes;

  /// HTML URL of the release page, opened in the browser by 「前往下载」.
  final String releaseUrl;

  /// Direct download URL of the release `.apk` asset, when the release ships
  /// one — enables the in-app download & install path on Android.
  final String? apkUrl;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    this.releaseTitle = '',
    this.releaseNotes = '',
    required this.releaseUrl,
    this.apkUrl,
  });
}
