/// User-tunable display options for the synced lyrics page.
///
/// Defaults mirror the original hard-coded values so existing installs
/// look unchanged until the user tweaks something.
class LyricsDisplaySettings {
  /// Font size of non-active lines (px).
  final double baseFontSize;

  /// Font size of the currently playing line (px).
  final double activeFontSize;

  /// Text height multiplier applied to every line.
  final double lineHeight;

  /// Viewport fraction (0..1) the active line is aligned to when the
  /// lyrics list auto-scrolls.
  final double scrollAlignment;

  static const double minBaseFontSize = 13;
  static const double maxBaseFontSize = 20;
  static const double minActiveFontSize = 16;
  static const double maxActiveFontSize = 26;
  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 2.0;
  static const double minScrollAlignment = 0.15;
  static const double maxScrollAlignment = 0.55;

  const LyricsDisplaySettings({
    this.baseFontSize = 16,
    this.activeFontSize = 19,
    this.lineHeight = 1.5,
    this.scrollAlignment = 0.34,
  });

  static const LyricsDisplaySettings defaults = LyricsDisplaySettings();

  LyricsDisplaySettings copyWith({
    double? baseFontSize,
    double? activeFontSize,
    double? lineHeight,
    double? scrollAlignment,
  }) {
    return LyricsDisplaySettings(
      baseFontSize: baseFontSize ?? this.baseFontSize,
      activeFontSize: activeFontSize ?? this.activeFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      scrollAlignment: scrollAlignment ?? this.scrollAlignment,
    );
  }

  Map<String, dynamic> toMap() => {
    'base_font_size': baseFontSize,
    'active_font_size': activeFontSize,
    'line_height': lineHeight,
    'scroll_alignment': scrollAlignment,
  };

  factory LyricsDisplaySettings.fromMap(dynamic raw) {
    if (raw is! Map) return defaults;
    final map = Map<String, dynamic>.from(raw);
    double readDouble(String key, double min, double max, double fallback) {
      final value = map[key];
      if (value is! num) return fallback;
      return LyricsDisplaySettings._clampStatic(
        value.toDouble(),
        min,
        max,
        fallback,
      );
    }

    return LyricsDisplaySettings(
      baseFontSize: readDouble(
        'base_font_size',
        minBaseFontSize,
        maxBaseFontSize,
        defaults.baseFontSize,
      ),
      activeFontSize: readDouble(
        'active_font_size',
        minActiveFontSize,
        maxActiveFontSize,
        defaults.activeFontSize,
      ),
      lineHeight: readDouble(
        'line_height',
        minLineHeight,
        maxLineHeight,
        defaults.lineHeight,
      ),
      scrollAlignment: readDouble(
        'scroll_alignment',
        minScrollAlignment,
        maxScrollAlignment,
        defaults.scrollAlignment,
      ),
    );
  }

  static double _clampStatic(double value, double min, double max, double fallback) {
    if (value.isNaN || value.isInfinite) return fallback;
    return value.clamp(min, max);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsDisplaySettings &&
          runtimeType == other.runtimeType &&
          baseFontSize == other.baseFontSize &&
          activeFontSize == other.activeFontSize &&
          lineHeight == other.lineHeight &&
          scrollAlignment == other.scrollAlignment;

  @override
  int get hashCode => Object.hash(
    baseFontSize,
    activeFontSize,
    lineHeight,
    scrollAlignment,
  );
}
