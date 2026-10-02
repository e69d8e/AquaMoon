/// Pure-Dart helpers for comparing app version strings against release tags.
///
/// Handles the shapes this app actually sees: pubspec versions like
/// `1.0.2+3` and GitHub tags like `v1.0.2` or `v1.1.0-beta.1`. A
/// pre-release (`-beta`) never outranks the plain release of the same
/// number, and build metadata (`+3`) is ignored entirely.
class VersionUtils {
  VersionUtils._();

  /// Compares two version strings and returns a negative number, zero, or a
  /// positive number when [a] is older than, equal to, or newer than [b].
  ///
  /// Numeric segments are compared position by position; missing segments
  /// count as zero, so `1.0` equals `1.0.0`. Non-numeric segments fall back
  /// to zero instead of throwing.
  static int compareVersions(String a, String b) {
    final segmentsA = _numericSegments(a);
    final segmentsB = _numericSegments(b);
    final length = segmentsA.length > segmentsB.length
        ? segmentsA.length
        : segmentsB.length;

    for (var i = 0; i < length; i++) {
      final segA = i < segmentsA.length ? segmentsA[i] : 0;
      final segB = i < segmentsB.length ? segmentsB[i] : 0;
      if (segA != segB) return segA.compareTo(segB);
    }
    return 0;
  }

  /// Strips the `v` prefix, pre-release suffix, and build metadata from a
  /// version or tag, keeping the dotted numeric core (`v1.0.2+3` → `1.0.2`).
  static String normalize(String version) {
    var s = version.trim().toLowerCase();
    if (s.startsWith('v')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    return s.trim();
  }

  static List<int> _numericSegments(String version) {
    final core = normalize(version);
    return core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}
