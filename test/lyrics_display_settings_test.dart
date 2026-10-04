import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/models/lyrics_display_settings.dart';

void main() {
  group('LyricsDisplaySettings', () {
    test('defaults match the original hard-coded lyrics look', () {
      const settings = LyricsDisplaySettings.defaults;
      expect(settings.baseFontSize, 16);
      expect(settings.activeFontSize, 19);
      expect(settings.lineHeight, 1.5);
      expect(settings.scrollAlignment, closeTo(0.34, 0.001));
    });

    test('toMap/fromMap round trip preserves values', () {
      const settings = LyricsDisplaySettings(
        baseFontSize: 18,
        activeFontSize: 24,
        lineHeight: 1.8,
        scrollAlignment: 0.5,
      );
      final restored = LyricsDisplaySettings.fromMap(settings.toMap());
      expect(restored, settings);
    });

    test('fromMap falls back to defaults for missing or invalid data', () {
      expect(LyricsDisplaySettings.fromMap(null), LyricsDisplaySettings.defaults);
      expect(
        LyricsDisplaySettings.fromMap('garbage'),
        LyricsDisplaySettings.defaults,
      );
      expect(
        LyricsDisplaySettings.fromMap({}),
        LyricsDisplaySettings.defaults,
      );
    });

    test('fromMap clamps out-of-range and corrupt values', () {
      final restored = LyricsDisplaySettings.fromMap({
        'base_font_size': 99,
        'active_font_size': double.nan,
        'line_height': -3,
        'scroll_alignment': 5.0,
      });
      expect(
        restored.baseFontSize,
        LyricsDisplaySettings.maxBaseFontSize,
      );
      expect(restored.activeFontSize, LyricsDisplaySettings.defaults.activeFontSize);
      expect(restored.lineHeight, LyricsDisplaySettings.minLineHeight);
      expect(
        restored.scrollAlignment,
        LyricsDisplaySettings.maxScrollAlignment,
      );
    });

    test('copyWith only overrides given fields', () {
      const settings = LyricsDisplaySettings.defaults;
      final updated = settings.copyWith(baseFontSize: 14);
      expect(updated.baseFontSize, 14);
      expect(updated.activeFontSize, settings.activeFontSize);
      expect(updated.lineHeight, settings.lineHeight);
    });
  });
}
