class LyricLine {
  final Duration time;
  final String text;
  final String? translation;

  /// Word-level (or character-level) timings from enhanced LRC `<mm:ss.xxx>`
  /// tags. Empty when the line only carries a line-level timestamp.
  final List<LyricWord> words;

  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.words = const [],
  });

  bool get hasWordTimings => words.isNotEmpty;

  @override
  String toString() => '[${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}] $text';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          time == other.time &&
          text == other.text;

  @override
  int get hashCode => time.hashCode ^ text.hashCode;
}

/// One timed segment of an enhanced-LRC line.
class LyricWord {
  final Duration start;
  final Duration end;
  final String text;

  const LyricWord({required this.start, required this.end, required this.text});
}
