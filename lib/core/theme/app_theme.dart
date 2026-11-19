import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

/// 承载没有对应 ColorScheme 槽位的主题 token（渐变、玻璃边界、语义色等）。
///
/// 视图通过 `Theme.of(context).extension<AppColors>()` 读取；
/// 若运行在未注入主题的孤立测试 `MaterialApp` 中，使用 [AppColors.fallbackOf] 安全降级。
class AppColors extends ThemeExtension<AppColors> {
  /// 全屏播放页三段式背景渐变（上 → 下）。
  final List<Color> playerGradient;

  /// 磨砂玻璃表面的细描边。
  final Color glassBorder;

  /// 极淡分隔线。
  final Color subtleDivider;

  /// 收藏心形高亮色（朱红系，与水墨及各主题协调）。
  final Color favorite;

  /// 云端曲目标签色。
  final Color onlineBadge;

  /// VIP 徽章色。
  final Color vipBadge;

  const AppColors({
    required this.playerGradient,
    this.glassBorder = const Color(0x1826241F),
    this.subtleDivider = const Color(0x1426241F),
    this.favorite = const Color(0xFFD6453A),
    this.onlineBadge = const Color(0xFF2B7A72),
    this.vipBadge = const Color(0xFFB37B1C),
  });

  /// 当 widget 运行在默认 `MaterialApp()` 测试容器内时，提供合理的降级 token。
  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    if (ext != null) return ext;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final palette = isLight ? AppPalette.inkwash.light : AppPalette.inkwash.dark;
    return _fromPalette(palette, isLight: isLight);
  }

  static AppColors _fromPalette(PaletteColors c, {required bool isLight}) {
    return AppColors(
      playerGradient: c.playerGradient,
      glassBorder: isLight
          ? c.textPrimary.withValues(alpha: 0.08)
          : c.textPrimary.withValues(alpha: 0.10),
      subtleDivider: isLight
          ? c.textPrimary.withValues(alpha: 0.07)
          : c.textPrimary.withValues(alpha: 0.08),
      favorite: isLight ? const Color(0xFFD14338) : const Color(0xFFEF6C60),
      onlineBadge: isLight ? const Color(0xFF2B7A72) : const Color(0xFF69BBAE),
      vipBadge: isLight ? const Color(0xFFA66E12) : const Color(0xFFE3B14E),
    );
  }

  @override
  AppColors copyWith({
    List<Color>? playerGradient,
    Color? glassBorder,
    Color? subtleDivider,
    Color? favorite,
    Color? onlineBadge,
    Color? vipBadge,
  }) => AppColors(
    playerGradient: playerGradient ?? this.playerGradient,
    glassBorder: glassBorder ?? this.glassBorder,
    subtleDivider: subtleDivider ?? this.subtleDivider,
    favorite: favorite ?? this.favorite,
    onlineBadge: onlineBadge ?? this.onlineBadge,
    vipBadge: vipBadge ?? this.vipBadge,
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
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      subtleDivider: Color.lerp(subtleDivider, other.subtleDivider, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
      onlineBadge: Color.lerp(onlineBadge, other.onlineBadge, t)!,
      vipBadge: Color.lerp(vipBadge, other.vipBadge, t)!,
    );
  }
}

class AppTheme {
  static ThemeData lightTheme(PaletteColors c) => _build(c, Brightness.light);

  static ThemeData darkTheme(PaletteColors c) => _build(c, Brightness.dark);

  static ThemeData _build(PaletteColors c, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final appColors = AppColors._fromPalette(c, isLight: isLight);
    final errorColor = isLight
        ? const Color(0xFFC23B2E)
        : const Color(0xFFEB6B5E);

    final colorScheme = isLight
        ? ColorScheme.light(
            primary: c.primary,
            onPrimary: c.onPrimary,
            primaryContainer: c.primary.withValues(alpha: 0.11),
            onPrimaryContainer: c.onSecondaryContainer,
            secondary: c.primary,
            secondaryContainer: c.primary.withValues(alpha: 0.12),
            onSecondaryContainer: c.onSecondaryContainer,
            surface: c.surface,
            surfaceContainerHighest: c.surfaceContainerHighest,
            onSurface: c.textPrimary,
            onSurfaceVariant: c.textSecondary,
            outline: c.textTertiary,
            outlineVariant: c.textTertiary.withValues(alpha: 0.42),
            error: errorColor,
            onError: Colors.white,
          )
        : ColorScheme.dark(
            primary: c.primary,
            onPrimary: c.onPrimary,
            primaryContainer: c.primary.withValues(alpha: 0.18),
            onPrimaryContainer: c.onSecondaryContainer,
            secondary: c.primary,
            secondaryContainer: c.primary.withValues(alpha: 0.2),
            onSecondaryContainer: c.onSecondaryContainer,
            surface: c.surface,
            surfaceContainerHighest: c.surfaceContainerHighest,
            onSurface: c.textPrimary,
            onSurfaceVariant: c.textSecondary,
            outline: c.textTertiary,
            outlineVariant: c.textTertiary.withValues(alpha: 0.32),
            error: errorColor,
            onError: const Color(0xFF2B0B08),
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: c.primary,
      scaffoldBackgroundColor: c.background,
      colorScheme: colorScheme,
      extensions: [appColors],
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(
        color: appColors.subtleDivider,
        thickness: 0.8,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(
            color: c.textTertiary.withValues(alpha: isLight ? 0.35 : 0.28),
            width: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return c.primary.withValues(alpha: isLight ? 0.14 : 0.24);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return c.primary;
            }
            return c.textSecondary;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: c.textTertiary.withValues(alpha: isLight ? 0.32 : 0.25),
              width: 0.9,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceContainerHighest.withValues(alpha: 0.55),
        selectedColor: c.primary.withValues(alpha: isLight ? 0.14 : 0.22),
        side: BorderSide(color: c.cardBorder, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(fontSize: 12.5, color: c.textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isLight ? Brightness.dark : Brightness.light,
        ),
        iconTheme: IconThemeData(color: c.textPrimary, size: 22),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: c.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.cardBorder, width: 1),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isLight ? 6 : 10,
        shadowColor: Colors.black.withValues(alpha: isLight ? 0.10 : 0.38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: appColors.glassBorder, width: 1),
        ),
        textStyle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        subtitleTextStyle: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isLight ? 6 : 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: appColors.glassBorder, width: 1),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: -0.3,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: c.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: c.textTertiary.withValues(alpha: 0.45),
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isLight
              ? c.textPrimary.withValues(alpha: 0.92)
              : c.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: isLight
              ? null
              : Border.all(color: appColors.glassBorder, width: 0.8),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isLight ? c.surface : c.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.snackBarBackground,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x38FFFFFF), width: 0.8),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: isLight
            ? c.textPrimary.withValues(alpha: 0.10)
            : c.textPrimary.withValues(alpha: 0.16),
        thumbColor: c.primary,
        overlayColor: c.primary.withValues(alpha: 0.14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackHeight: 3.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.onPrimary;
          return c.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return c.textTertiary.withValues(alpha: 0.35);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.primary.withValues(alpha: 0.12),
        circularTrackColor: c.primary.withValues(alpha: 0.12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.primary.withValues(alpha: isLight ? 0.13 : 0.20),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: c.primary,
            );
          }
          return TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: c.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.primary, size: 22);
          }
          return IconThemeData(color: c.textSecondary, size: 22);
        }),
      ),
    );
  }
}
