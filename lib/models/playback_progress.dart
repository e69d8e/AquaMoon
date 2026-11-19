class PlaybackProgress {
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;

  const PlaybackProgress({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
  });

  double get progressRatio {
    if (duration.inMilliseconds == 0) return 0.0;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    return ratio.clamp(0.0, 1.0);
  }

  double get bufferedRatio {
    if (duration.inMilliseconds == 0) return 0.0;
    final ratio = bufferedPosition.inMilliseconds / duration.inMilliseconds;
    return ratio.clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackProgress &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          duration == other.duration &&
          bufferedPosition == other.bufferedPosition;

  @override
  int get hashCode => Object.hash(position, duration, bufferedPosition);
}
