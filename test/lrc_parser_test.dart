import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/core/utils/lrc_parser.dart';

void main() {
  group('LrcParser Tests', () {
    test('parses standard LRC lyrics with [mm:ss.xx]', () {
      const lrc = '''
[ti:Sample Track]
[ar:Sample Artist]
[al:Sample Album]
[00:02.50]Hello world
[00:05.80]This is line two
[00:10.00]This is line three
''';

      final lines = LrcParser.parse(lrc);
      expect(lines.length, equals(3));
      expect(lines[0].text, equals('Hello world'));
      expect(lines[0].time, equals(const Duration(seconds: 2, milliseconds: 500)));
      expect(lines[1].text, equals('This is line two'));
      expect(lines[1].time, equals(const Duration(seconds: 5, milliseconds: 800)));
      expect(lines[2].text, equals('This is line three'));
      expect(lines[2].time, equals(const Duration(seconds: 10)));
    });

    test('parses and cleans QQ Music word-by-word syllable tags correctly', () {
      const rawLrc = '''
<00:30.703>冉<00:30.935>冉<00:31.216>檀<00:31.527>香<00:31.920><00:32.071>透<00:32.311>过<00:32.642>窗
<00:35.183>宣<00:35.408>纸<00:35.647>上<00:35.865><00:35.976>走<00:36.231>笔<00:36.503>至<00:36.774>此<00:37.098>搁<00:37.456><00:37.619>一<00:37.888>半<00:39.159>
''';

      final lines = LrcParser.parse(rawLrc);
      expect(lines.length, equals(2));
      expect(lines[0].text, equals('冉冉檀香透过窗'));
      expect(lines[0].time, equals(const Duration(seconds: 30, milliseconds: 703)));
      expect(lines[1].text, equals('宣纸上走笔至此搁一半'));
      expect(lines[1].time, equals(const Duration(seconds: 35, milliseconds: 183)));
    });

    test('parses multi-timestamp lines and sorts chronologically', () {
      const lrc = '''
[00:08.00][00:02.00]Chorus line
[00:05.00]Verse line
''';

      final lines = LrcParser.parse(lrc);
      expect(lines.length, equals(3));
      expect(lines[0].time, equals(const Duration(seconds: 2)));
      expect(lines[0].text, equals('Chorus line'));
      expect(lines[1].time, equals(const Duration(seconds: 5)));
      expect(lines[1].text, equals('Verse line'));
      expect(lines[2].time, equals(const Duration(seconds: 8)));
      expect(lines[2].text, equals('Chorus line'));
    });

    test('binary search finds accurate active lyric index', () {
      const lrc = '''
[00:05.00]First line
[00:10.00]Second line
[00:15.00]Third line
''';

      final lines = LrcParser.parse(lrc);

      // Before first line
      expect(LrcParser.findCurrentIndex(lines, const Duration(seconds: 2)), equals(-1));
      // Exactly at first line
      expect(LrcParser.findCurrentIndex(lines, const Duration(seconds: 5)), equals(0));
      // Between first and second line
      expect(LrcParser.findCurrentIndex(lines, const Duration(seconds: 7)), equals(0));
      // At second line
      expect(LrcParser.findCurrentIndex(lines, const Duration(seconds: 10)), equals(1));
      // Past last line
      expect(LrcParser.findCurrentIndex(lines, const Duration(seconds: 30)), equals(2));
    });

    test('handles empty or null LRC gracefully', () {
      expect(LrcParser.parse(null), isEmpty);
      expect(LrcParser.parse('   '), isEmpty);
      expect(LrcParser.parse('Invalid text with no timestamps'), isEmpty);
    });
  });
}
