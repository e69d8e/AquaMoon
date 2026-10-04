import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

/// 承载没有对应 ColorScheme 槽位的主题 token(如全屏播放页背景渐变)。
///
/// 视图通过 `Theme.of(context).extension<AppColors>()` 读取。
class AppColors extends ThemeExtension<AppColors> {
  /// 全屏播放页三段式背景渐变(上 → 下)。
  final List<Color> playerGradient;

  const AppColors({required this.playerGradient});

  @override
  AppColors copyWith({List<Color>? playerGradient}) => AppColors(
        playerGradient: playerGradient ?? this.playerGradient,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null || other.playerGradient.length != playerGradient.length) {
      return this;
    }
    return AppColors(
      playerGradient: List.generate(
        playerGradient.length,
        (i) => Color.lerp(playerGradient[i], other.playerGradient[i], t)!,
      ),
    );
  }
}

class AppTheme {
  static ThemeData lightTheme(PaletteColors c) => _build(c, Brightness.light);

  static ThemeData darkTheme(PaletteColors c) => _build(c, Brightness.dark);

  static ThemeData _build(PaletteColors c, Brightness brightness) {
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: c.primary,
      scaffoldBackgroundColor: c.background,
      colorScheme: isLight
          ? ColorScheme.light(
              primary: c.primary,
              secondary: c.primary,
              secondaryContainer: c.primary.withValues(alpha: 0.12),
              onSecondaryContainer: c.onSecondaryContainer,
              surface: c.surface,
              surfaceContainerHighest: c.surfaceContainerHighest,
              onPrimary: c.onPrimary,
              onSurface: c.textPrimary,
              onSurfaceVariant: c.textSecondary,
              outline: c.textTertiary,
              outlineVariant: c.textTertiary.withValues(alpha: 0.45),
            )
          : ColorScheme.dark(
              primary: c.primary,
              secondary: c.primary,
              secondaryContainer: c.primary.withValues(alpha: 0.2),
              onSecondaryContainer: c.onSecondaryContainer,
              surface: c.surface,
              surfaceContainerHighest: c.surfaceContainerHighest,
              onPrimary: c.onPrimary,
              onSurface: c.textPrimary,
              onSurfaceVariant: c.textSecondary,
              outline: c.textTertiary,
              outlineVariant: c.textTertiary.withValues(alpha: 0.35),
            ),
      extensions: [
        AppColors(playerGradient: c.playerGradient),
      ],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isLight ? Brightness.dark : Brightness.light,
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: c.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.cardBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.snackBarBackground,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x40FFFFFF), width: 0.8),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.textPrimary,
        inactiveTrackColor: isLight
            ? Colors.black.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.2),
        thumbColor: c.textPrimary,
        overlayColor: isLight
            ? Colors.black.withValues(alpha: 0.08)
            : c.primary.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
        trackHeight: 3.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        elevation: 1,
        indicatorColor: c.primary.withValues(alpha: isLight ? 0.15 : 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.primary,
            );
          }
          return TextStyle(fontSize: 12, color: c.textSecondary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.primary);
          }
          return IconThemeData(color: c.textSecondary);
        }),
      ),
    );
  }
}
