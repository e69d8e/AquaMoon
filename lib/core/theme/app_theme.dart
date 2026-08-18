import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Accent Colors
  static const primaryColor = Color(0xFF1DB954); // Vibrant Green Accent
  static const primaryDark = Color(0xFF191A23);
  static const accentIndigo = Color(0xFF6366F1);

  // Light Palette Tokens
  static const lightBackground = Color(0xFFF9FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSecondary = Color(0xFFF1F3F7);
  static const lightTextPrimary = Color(0xFF1C1D24);
  static const lightTextSecondary = Color(0xFF757885);
  static const lightTextTertiary = Color(0xFFA0A3AF);

  // Dark Palette Tokens
  static const darkBackground = Color(0xFF0F1117);
  static const darkSurface = Color(0xFF1A1D27);
  static const darkSurfaceLight = Color(0xFF242838);
  static const darkCard = Color(0xFF1E2230);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        secondary: primaryColor,
        secondaryContainer: primaryColor.withValues(alpha: 0.12),
        onSecondaryContainer: const Color(0xFF0D692E),
        surface: lightSurface,
        surfaceContainerHighest: lightSurfaceSecondary,
        onPrimary: Colors.white,
        onSurface: lightTextPrimary,
        onSurfaceVariant: lightTextSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        iconTheme: IconThemeData(color: lightTextPrimary),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: lightTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x0F000000), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xEE1DB954),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x40FFFFFF), width: 0.8),
        ),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: lightTextPrimary,
        inactiveTrackColor: Color(0x1A000000),
        thumbColor: lightTextPrimary,
        overlayColor: Color(0x14000000),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
        trackHeight: 3.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        elevation: 1,
        indicatorColor: primaryColor.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor);
          }
          return const TextStyle(fontSize: 12, color: lightTextSecondary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor);
          }
          return const IconThemeData(color: lightTextSecondary);
        }),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryColor,
        secondaryContainer: primaryColor.withValues(alpha: 0.2),
        onSecondaryContainer: const Color(0xFF86EFAC),
        surface: darkSurface,
        surfaceContainerHighest: darkSurfaceLight,
        onPrimary: Colors.white,
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFF9E9E9E),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xEE15803D),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x40FFFFFF), width: 0.8),
        ),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Colors.white,
        inactiveTrackColor: Color(0x33FFFFFF),
        thumbColor: Colors.white,
        overlayColor: Color(0x291DB954),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
        trackHeight: 3.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor);
          }
          return const TextStyle(fontSize: 12, color: Colors.grey);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor);
          }
          return const IconThemeData(color: Colors.grey);
        }),
      ),
    );
  }
}
