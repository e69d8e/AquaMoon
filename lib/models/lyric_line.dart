class LyricLine {
  final Duration time;
  final String text;
  final String? translation;

  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
  });

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
