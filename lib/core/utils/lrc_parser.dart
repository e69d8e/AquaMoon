import '../../models/lyric_line.dart';

class LrcParser {
  // Regex for standard [00:12.34] or [00:12.345] or [00:12] tags.
  // Minutes allow 3 digits: audiobooks / DJ mixes exceed 99 minutes and
  // [100:00.00] used to be dropped from the lyrics entirely.
  static final RegExp _squareTimeRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  // Regex for enhanced word-by-word <00:12.345> or <00:12.34> tags (QQ Music / KRC / YRC format)
  static final RegExp _angleTimeRegex = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
  // Regex for metadata tags like [ti:Title], [ar:Artist], [al:Album], [by:...]
  static final RegExp _metaRegex = RegExp(r'\[([a-zA-Z]+):([^\]]*)\]');
  // Global sync-shift directive: [offset:+500] / [offset:-300]. A positive
  // value is added to every timestamp (lyrics display later), matching the
  // convention of the common Chinese LRC editors this app's users export from.
  static final RegExp _offsetRegex = RegExp(
    r'\[\s*offset\s*:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );
  // Matches any angle-bracket tag (used for stripping and splitting).
  static final RegExp _angleTagAnyRegex = RegExp(r'<[^>]+>');

  /// Parses raw LRC (standard, multi-timestamp, or word-by-word <mm:ss.xxx>) string into a sorted list of [LyricLine]
  static List<LyricLine> parse(String? rawLrc) {
    if (rawLrc == null || rawLrc.trim().isEmpty) {
      return [];
    }

    // The [offset:±ms] directive applies to the whole file — extract it up
    // front so the generic metadata skip below doesn't silently discard it.
    var offsetMs = 0;
    final offsetMatch = _offsetRegex.firstMatch(rawLrc);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
    }

    final List<LyricLine> lines = [];
    final rawLines = rawLrc.split(RegExp(r'\r?\n'));

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 1. Skip metadata header tags like [ti:青花瓷], [ar:周杰伦]
      // ([offset:…] was already extracted above and must not be dropped).
      if (_metaRegex.hasMatch(line) && !_squareTimeRegex.hasMatch(line)) {
        continue;
      }

      // 2. Check for [mm:ss.xx] line timestamps first
      var squareMatches = _squareTimeRegex.allMatches(line).toList();

      if (squareMatches.isNotEmpty) {
        // Line has [mm:ss.xx] timestamp(s)
        final cleanText = _stripAllTags(line);
        if (cleanText.isEmpty) continue;

        final words = _extractWords(line, cleanText);

        for (final match in squareMatches) {
          final duration = _parseMatchToDuration(match);
          lines.add(
            LyricLine(time: duration, text: cleanText, words: words),
          );
        }
      } else {
        // 3. Line does NOT have [mm:ss.xx], check for leading <mm:ss.xxx> syllable timestamp (e.g. <00:35.183>宣<00:35.408>纸...)
        final angleMatches = _angleTimeRegex.allMatches(line).toList();
        if (angleMatches.isNotEmpty) {
          // Use the first timestamp as the line start time
          final firstMatch = angleMatches.first;
          final duration = _parseMatchToDuration(firstMatch);

          final cleanText = _stripAllTags(line);
          if (cleanText.isNotEmpty) {
            lines.add(
              LyricLine(
                time: duration,
                text: cleanText,
                words: _extractWords(line, cleanText),
              ),
            );
          }
        }
      }
    }

    // Apply the file-wide [offset:±ms] shift to every absolute timestamp
    // (line starts and word timings alike), clamping at zero.
    if (offsetMs != 0) {
      final shift = Duration(milliseconds: offsetMs);
      Duration shiftTime(Duration t) {
        final shifted = t + shift;
        return shifted < Duration.zero ? Duration.zero : shifted;
      }

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        lines[i] = LyricLine(
          time: shiftTime(line.time),
          text: line.text,
          translation: line.translation,
          words: line.words.isEmpty
              ? line.words
              : [
                  for (final w in line.words)
                    LyricWord(
                      start: shiftTime(w.start),
                      end: shiftTime(w.end),
                      text: w.text,
                    ),
                ],
        );
      }
    }

    // Sort chronologically
    lines.sort((a, b) => a.time.compareTo(b.time));
    _closeWordTimings(lines);
    return lines;
  }

  /// Strips all [..] and <..> tags, returning pure lyric text.
  static String _stripAllTags(String line) {
    return line
        .replaceAll(_angleTagAnyRegex, '')
        .replaceAll(RegExp(r'\[[^\]]+\]'), '')
        .trim();
  }

  /// Builds word segments from a raw enhanced-LRC line: the text run between
  /// angle tag N and tag N+1 belongs to word N. Returns an empty list for
  /// plain (line-timestamp-only) lines, and also when the timed runs don't
  /// reconstruct the full line text (untimed leading text etc.) so those fall
  /// back to line-level highlighting.
  static List<LyricWord> _extractWords(String rawLine, String cleanText) {
    final matches = _angleTimeRegex.allMatches(rawLine).toList();
    if (matches.isEmpty) return const [];

    final words = <LyricWord>[];
    for (var i = 0; i < matches.length; i++) {
      final runStart = matches[i].end;
      final runEnd = i + 1 < matches.length
          ? matches[i + 1].start
          : rawLine.length;
      final text = rawLine
          .substring(runStart, runEnd)
          .replaceAll(RegExp(r'\[[^\]]+\]'), '');
      if (text.isEmpty) continue;
      words.add(
        LyricWord(
          start: _parseMatchToDuration(matches[i]),
          end: Duration.zero, // filled in by [_closeWordTimings]
          text: text,
        ),
      );
    }

    if (words.isEmpty ||
        words.map((w) => w.text).join('').length != cleanText.length) {
      return const [];
    }
    return words;
  }

  /// Assigns every word an end time: the next word's start, the next line's
  /// time, or start + 3s for the final line's tail. Lines that are missing
  /// word timings entirely keep `words` empty.
  static void _closeWordTimings(List<LyricLine> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.words.isEmpty) continue;
      final nextLineTime = i + 1 < lines.length
          ? lines[i + 1].time
          : line.time + const Duration(seconds: 3);
      final closed = <LyricWord>[];
      for (var w = 0; w < line.words.length; w++) {
        final word = line.words[w];
        final end = w + 1 < line.words.length
            ? line.words[w + 1].start
            : nextLineTime;
        closed.add(
          LyricWord(
            start: word.start,
            end: end <= word.start ? word.start : end,
            text: word.text,
          ),
        );
      }
      lines[i] = LyricLine(
        time: line.time,
        text: line.text,
        translation: line.translation,
        words: closed,
      );
    }
  }

  /// Fraction (0.0–1.0) of [line]'s text that should be lit at [position],
  /// or `null` when the line carries no word timings (line-level highlight
  /// only). Character-based so CJK and Latin text both wipe smoothly.
  static double? litFraction(LyricLine line, Duration position) {
    if (line.words.isEmpty) return null;
    if (position <= line.words.first.start) return 0.0;

    var litChars = 0;
    for (final word in line.words) {
      if (position >= word.end) {
        litChars += word.text.length;
        continue;
      }
      if (position <= word.start) break;
      final spanMs = (word.end - word.start).inMilliseconds;
      final fraction = spanMs <= 0
          ? 1.0
          : (position - word.start).inMilliseconds / spanMs;
      litChars += (word.text.length * fraction).floor();
      break;
    }

    final total = line.text.length;
    if (total == 0) return null;
    return (litChars / total).clamp(0.0, 1.0);
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
