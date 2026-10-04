import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/core/theme/app_palette.dart';
import 'package:aquamoon/core/theme/app_theme.dart';

void main() {
  group('AppPalette', () {
    test('默认配色方案为水墨丹青', () {
      expect(AppPalette.defaultId, 'inkwash');
      expect(AppPalette.byId(null).id, 'inkwash');
    });

    test('未知 id 回退到默认方案,不抛异常', () {
      expect(AppPalette.byId('nonexistent').id, AppPalette.defaultId);
      expect(AppPalette.byId('').id, AppPalette.defaultId);
    });

    test('全部方案 id 唯一且非空', () {
      final ids = AppPalette.all.map((p) => p.id).toSet();
      expect(ids.length, AppPalette.all.length);
      expect(ids.any((id) => id.isEmpty), isFalse);
    });

    test('每套方案都有名称、标语与三段渐变', () {
      for (final palette in AppPalette.all) {
        expect(palette.name, isNotEmpty, reason: '${palette.id} 缺少名称');
        expect(palette.tagline, isNotEmpty, reason: '${palette.id} 缺少标语');
        expect(
          palette.light.playerGradient.length,
          3,
          reason: '${palette.id} 浅色渐变应为三段',
        );
        expect(
          palette.dark.playerGradient.length,
          3,
          reason: '${palette.id} 深色渐变应为三段',
        );
      }
    });

    test('至少包含计划中的 6 套方案', () {
      expect(
        AppPalette.all.map((p) => p.id),
        containsAll([
          'inkwash',
          'porcelain',
          'bamboo',
          'violet',
          'amber',
          'teal',
        ]),
      );
    });
  });

  group('AppTheme', () {
    test('每套方案的浅色与深色 ThemeData 均可无断言构建', () {
      for (final palette in AppPalette.all) {
        final light = AppTheme.lightTheme(palette.light);
        final dark = AppTheme.darkTheme(palette.dark);

        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.useMaterial3, isTrue);
        expect(dark.useMaterial3, isTrue);
        expect(light.colorScheme.primary, palette.light.primary);
        expect(dark.colorScheme.primary, palette.dark.primary);
        expect(light.scaffoldBackgroundColor, palette.light.background);
        expect(dark.scaffoldBackgroundColor, palette.dark.background);
      }
    });

    test('ThemeData 注册了 AppColors 扩展且渐变与方案一致', () {
      for (final palette in AppPalette.all) {
        final light = AppTheme.lightTheme(palette.light);
        final appColors = light.extension<AppColors>();
        expect(appColors, isNotNull);
        expect(appColors!.playerGradient, palette.light.playerGradient);
      }
    });

    test('AppColors.lerp 在两个方案间平滑插值', () {
      const a = AppColors(playerGradient: [
        Color(0xFF000000),
        Color(0xFF000000),
        Color(0xFF000000),
      ]);
      const b = AppColors(playerGradient: [
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
      ]);

      final mid = a.lerp(b, 0.5).playerGradient.first;
      // Color.lerp 可能产生浮点分量(127.5/255),按近似值断言。
      expect((mid.r - 0.5).abs(), lessThan(0.001));
      expect((mid.g - 0.5).abs(), lessThan(0.001));
      expect((mid.b - 0.5).abs(), lessThan(0.001));
    });
  });
}
