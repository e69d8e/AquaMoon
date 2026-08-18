import '../../models/lyric_line.dart';

class LrcParser {
  // Regex for standard [00:12.34] or [00:12.345] or [00:12] tags
  static final RegExp _squareTimeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  // Regex for enhanced word-by-word <00:12.345> or <00:12.34> tags (QQ Music / KRC / YRC format)
  static final RegExp _angleTimeRegex = RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');
  // Regex for metadata tags like [ti:Title], [ar:Artist], [al:Album], [by:...]
  static final RegExp _metaRegex = RegExp(r'\[([a-zA-Z]+):([^\]]*)\]');

  /// Parses raw LRC (standard, multi-timestamp, or word-by-word <mm:ss.xxx>) string into a sorted list of [LyricLine]
  static List<LyricLine> parse(String? rawLrc) {
    if (rawLrc == null || rawLrc.trim().isEmpty) {
      return [];
    }

    final List<LyricLine> lines = [];
    final rawLines = rawLrc.split(RegExp(r'\r?\n'));

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 1. Skip metadata header tags like [ti:青花瓷], [ar:周杰伦], [offset:0]
      if (_metaRegex.hasMatch(line) && !_squareTimeRegex.hasMatch(line)) {
        continue;
      }

      // 2. Check for [mm:ss.xx] line timestamps first
      var squareMatches = _squareTimeRegex.allMatches(line).toList();

      if (squareMatches.isNotEmpty) {
        // Line has [mm:ss.xx] timestamp(s)
        // Clean text by stripping all [mm:ss.xx] tags AND all embedded <mm:ss.xxx> syllable tags
        final cleanText = line
            .replaceAll(_squareTimeRegex, '')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\[[^\]]+\]'), '')
            .trim();

        if (cleanText.isEmpty) continue;

        for (final match in squareMatches) {
          final duration = _parseMatchToDuration(match);
          lines.add(LyricLine(time: duration, text: cleanText));
        }
      } else {
        // 3. Line does NOT have [mm:ss.xx], check for leading <mm:ss.xxx> syllable timestamp (e.g. <00:35.183>宣<00:35.408>纸...)
        final angleMatches = _angleTimeRegex.allMatches(line).toList();
        if (angleMatches.isNotEmpty) {
          // Use the first timestamp as the line start time
          final firstMatch = angleMatches.first;
          final duration = _parseMatchToDuration(firstMatch);

          // Strip all <mm:ss.xxx> and [mm:ss.xx] tags to get pure clean text
          final cleanText = line
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll(RegExp(r'\[[^\]]+\]'), '')
              .trim();

          if (cleanText.isNotEmpty) {
            lines.add(LyricLine(time: duration, text: cleanText));
          }
        }
      }
    }

    // Sort chronologically
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  static Duration _parseMatchToDuration(Match match) {
    final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
    final msString = match.group(3) ?? '0';

    int milliseconds = 0;
    if (msString.length == 1) {
      milliseconds = (int.tryParse(msString) ?? 0) * 100;
    } else if (msString.length == 2) {
      milliseconds = (int.tryParse(msString) ?? 0) * 10;
    } else {
      milliseconds = int.tryParse(msString) ?? 0;
    }

    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Binary search to find current active lyric index for given [position]
  static int findCurrentIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    if (position < lines.first.time) return -1;
    if (position >= lines.last.time) return lines.length - 1;

    int low = 0;
    int high = lines.length - 1;
    int result = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }
}
