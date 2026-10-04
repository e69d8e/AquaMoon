import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/core/utils/lrc_parser.dart';
import 'package:aquamoon/models/lyric_line.dart';

void main() {
  group('增强型 LRC 逐字解析', () {
    test('解析 <mm:ss.xxx> 词级时间标签并生成词段', () {
      final lines = LrcParser.parse(
        '[00:10.00]<00:10.00>宣<00:10.50>纸<00:11.00>走<00:11.50>笔\n'
        '[00:20.00]普通行\n',
      );

      expect(lines, hasLength(2));
      expect(lines[0].text, '宣纸走笔');
      expect(lines[0].hasWordTimings, isTrue);
      expect(lines[0].words, hasLength(4));
      expect(lines[0].words[0].start, const Duration(seconds: 10));
      expect(lines[0].words[1].start, const Duration(milliseconds: 10500));
      // 词尾由 _closeWordTimings 补齐：下一个词的开始时间。
      expect(lines[0].words[0].end, const Duration(milliseconds: 10500));
      expect(lines[0].words[3].end, const Duration(seconds: 20));
      expect(lines[0].words.map((w) => w.text).join(), '宣纸走笔');

      expect(lines[1].hasWordTimings, isFalse);
    });

    test('尖括号时间戳独立成行（无方括号行标签）也能解析', () {
      final lines = LrcParser.parse('<00:35.183>宣<00:35.408>纸');
      expect(lines, hasLength(1));
      expect(lines[0].time, const Duration(seconds: 35, milliseconds: 183));
      expect(lines[0].text, '宣纸');
      expect(lines[0].words.map((w) => w.text).join(), '宣纸');
    });

    test('普通 LRC 不产生词段（保持行级高亮）', () {
      final lines = LrcParser.parse('[00:12.34]青花瓷\n[00:20.00]天青色等烟雨');
      expect(lines, hasLength(2));
      for (final line in lines) {
        expect(line.hasWordTimings, isFalse);
      }
    });

    test('未覆盖整行的词段时间戳回退为行级高亮', () {
      // "宣"位于第一个尖括号标签之前，无时间戳 → 词段无法重建整行文本。
      final lines = LrcParser.parse('[00:10.00]宣<00:10.50>纸走笔');
      expect(lines, hasLength(1));
      expect(lines[0].text, '宣纸走笔');
      expect(lines[0].hasWordTimings, isFalse);
    });

    test('litFraction 随播放位置单调推进', () {
      final line = LrcParser.parse(
        '[00:10.00]<00:10.00>青花<00:12.00>瓷',
      ).first;

      expect(LrcParser.litFraction(line, const Duration(seconds: 9)), 0.0);
      // 第一词"青花"内推进一半 → 点亮 1/3 字符。
      final half = LrcParser.litFraction(line, const Duration(seconds: 11));
      expect(half, closeTo(1 / 3, 0.01));
      // 第一词结束：两字全亮，第二词未开始 → 2/3。
      final afterFirst = LrcParser.litFraction(
        line,
        const Duration(seconds: 12, milliseconds: 1),
      );
      expect(afterFirst, closeTo(2 / 3, 0.01));
      // 全部完成。
      expect(
        LrcParser.litFraction(line, const Duration(seconds: 30)),
        1.0,
      );
    });

    test('litFraction 对无词段行返回 null', () {
      final line = LrcParser.parse('[00:10.00]普通行').first;
      expect(LrcParser.litFraction(line, const Duration(seconds: 11)), isNull);
    });
  });

  group('LyricWord & LyricLine 模型', () {
    test('LyricLine.hasWordTimings 反映词段存在性', () {
      const empty = LyricLine(time: Duration.zero, text: 'A');
      const withWords = LyricLine(
        time: Duration.zero,
        text: 'AB',
        words: [
          LyricWord(start: Duration.zero, end: Duration(seconds: 1), text: 'A'),
          LyricWord(
            start: Duration(seconds: 1),
            end: Duration(seconds: 2),
            text: 'B',
          ),
        ],
      );
      expect(empty.hasWordTimings, isFalse);
      expect(withWords.hasWordTimings, isTrue);
    });
  });
}
