import 'package:flutter/material.dart';

/// 单个亮度下的原始颜色 token 集。
///
/// 每套配色方案([AppPalette])都提供 light / dark 两组 token,
/// 由 [AppTheme] 喂给 ThemeData。
class PaletteColors {
  /// 页面背景(scaffoldBackgroundColor)。
  final Color background;

  /// 卡片 / 弹窗 / 底部面板 / 导航栏等表面色。
  final Color surface;

  /// 次级表面(填充、输入框底色等)。
  final Color surfaceContainerHighest;

  /// 卡片底色(深色模式下通常比 [surface] 略亮)。
  final Color card;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 强调色:按钮、进度条、歌词高亮、选中态。
  final Color primary;
  final Color onPrimary;
  final Color onSecondaryContainer;
  final Color snackBarBackground;

  /// 卡片描边;浅色用极淡墨线,深色通常透明。
  final Color cardBorder;

  /// 全屏播放页的三段式背景渐变(上 → 下)。
  final List<Color> playerGradient;

  const PaletteColors({
    required this.background,
    required this.surface,
    required this.surfaceContainerHighest,
    required this.card,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.onPrimary,
    required this.onSecondaryContainer,
    required this.snackBarBackground,
    required this.cardBorder,
    required this.playerGradient,
  });
}

/// 一套命名的配色方案,包含浅色与深色两组 token。
class AppPalette {
  final String id;
  final String name;
  final String tagline;
  final PaletteColors light;
  final PaletteColors dark;

  const AppPalette({
    required this.id,
    required this.name,
    required this.tagline,
    required this.light,
    required this.dark,
  });

  static const String defaultId = 'inkwash';

  static const List<AppPalette> all = [
    inkwash,
    porcelain,
    bamboo,
    violet,
    amber,
    teal,
  ];

  /// 按 id 查找;未知或为空时回退到默认方案,防止脏数据导致崩溃。
  static AppPalette byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => inkwash);

  static const AppPalette inkwash = AppPalette(
    id: 'inkwash',
    name: '水墨丹青',
    tagline: '宣纸为底 · 朱砂点睛',
    light: PaletteColors(
      background: Color(0xFFF7F4ED),
      surface: Color(0xFFFDFCF8),
      surfaceContainerHighest: Color(0xFFEFEBE1),
      card: Color(0xFFFDFCF8),
      textPrimary: Color(0xFF26241F),
      textSecondary: Color(0xFF6E6A5F),
      textTertiary: Color(0xFFA8A294),
      primary: Color(0xFFB03E2D),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF7C2418),
      snackBarBackground: Color(0xEE9E3627),
      cardBorder: Color(0x1426241F),
      playerGradient: [Color(0xFFF0E9DB), Color(0xFFF7F4ED), Color(0xFFFCFAF5)],
    ),
    dark: PaletteColors(
      background: Color(0xFF141210),
      surface: Color(0xFF1D1A16),
      surfaceContainerHighest: Color(0xFF2A2620),
      card: Color(0xFF201D18),
      textPrimary: Color(0xFFECE7DC),
      textSecondary: Color(0xFFA39C8E),
      textTertiary: Color(0xFF6F695C),
      primary: Color(0xFFD4695A),
      onPrimary: Color(0xFF2E100A),
      onSecondaryContainer: Color(0xFFF2B4A6),
      snackBarBackground: Color(0xEE8C3B2E),
      cardBorder: Color(0x00FFFFFF),
      playerGradient: [Color(0xFF4A3F35), Color(0xFF2A241E), Color(0xFF141210)],
    ),
  );

  static const AppPalette porcelain = AppPalette(
    id: 'porcelain',
    name: '青花瓷',
    tagline: '素坯勾勒 · 青花一色',
    light: PaletteColors(
      background: Color(0xFFF4F7FA),
      surface: Color(0xFFFBFDFE),
      surfaceContainerHighest: Color(0xFFE7EEF4),
      card: Color(0xFFFBFDFE),
      textPrimary: Color(0xFF1D2733),
      textSecondary: Color(0xFF5E6D7C),
      textTertiary: Color(0xFF95A3B1),
      primary: Color(0xFF2B5C9E),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF1D4576),
      snackBarBackground: Color(0xEE2B5C9E),
      cardBorder: Color(0x141D2733),
      playerGradient: [Color(0xFFDCE7F2), Color(0xFFECF2F8), Color(0xFFFBFDFE)],
    ),
    dark: PaletteColors(
      background: Color(0xFF0E141C),
      surface: Color(0xFF16202B),
      surfaceContainerHighest: Color(0xFF223040),
      card: Color(0xFF1A2530),
      textPrimary: Color(0xFFE5ECF3),
      textSecondary: Color(0xFF9FAEC0),
      textTertiary: Color(0xFF64748A),
      primary: Color(0xFF7FA6D9),
      onPrimary: Color(0xFF0D2138),
      onSecondaryContainer: Color(0xFFB8D2F0),
      snackBarBackground: Color(0xEE33517E),
      cardBorder: Color(0x00FFFFFF),
      playerGradient: [Color(0xFF2A3A50), Color(0xFF182230), Color(0xFF0E141C)],
    ),
  );

  /// 完整保留改造前的绿色观感,供老用户无缝续用。
  static const AppPalette bamboo = AppPalette(
    id: 'bamboo',
    name: '青竹',
    tagline: '林间新绿 · 清音入耳',
    light: PaletteColors(
      background: Color(0xFFF9FAFC),
      surface: Color(0xFFFFFFFF),
      surfaceContainerHighest: Color(0xFFF1F3F7),
      card: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1C1D24),
      textSecondary: Color(0xFF757885),
      textTertiary: Color(0xFFA0A3AF),
      primary: Color(0xFF1DB954),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF0D692E),
      snackBarBackground: Color(0xEE1DB954),
      cardBorder: Color(0x0F000000),
      playerGradient: [Color(0xFFDFEDE4), Color(0xFFEFF6F1), Color(0xFFFCFEFC)],
    ),
    dark: PaletteColors(
      background: Color(0xFF0F1117),
      surface: Color(0xFF1A1D27),
      surfaceContainerHighest: Color(0xFF242838),
      card: Color(0xFF1E2230),
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFF9E9E9E),
      textTertiary: Color(0xFF777A85),
      primary: Color(0xFF1DB954),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF86EFAC),
      snackBarBackground: Color(0xEE15803D),
      cardBorder: Color(0x00FFFFFF),
      playerGradient: [Color(0xFF1F3A2C), Color(0xFF14231C), Color(0xFF0D1114)],
    ),
  );

  /// 浅色/深色渐变复刻改造前全屏播放页的藕荷紫外观。
  static const AppPalette violet = AppPalette(
    id: 'violet',
    name: '暮山紫',
    tagline: '暮色四合 · 紫烟渐染',
    light: PaletteColors(
      background: Color(0xFFF6F2F8),
      surface: Color(0xFFFFFFFF),
      surfaceContainerHighest: Color(0xFFEBE6F3),
      card: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF241E33),
      textSecondary: Color(0xFF6B6478),
      textTertiary: Color(0xFFA49CB4),
      primary: Color(0xFF5F4E8C),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF443768),
      snackBarBackground: Color(0xEE5F4E8C),
      cardBorder: Color(0x14241E33),
      playerGradient: [Color(0xFFEBE6F3), Color(0xFFF6F2F8), Color(0xFFFFFFFF)],
    ),
    dark: PaletteColors(
      background: Color(0xFF191326),
      surface: Color(0xFF241B33),
      surfaceContainerHighest: Color(0xFF322747),
      card: Color(0xFF201830),
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFFA99FC0),
      textTertiary: Color(0xFF736B8A),
      primary: Color(0xFFA78BC9),
      onPrimary: Color(0xFF241533),
      onSecondaryContainer: Color(0xFFD3C3EA),
      snackBarBackground: Color(0xEE5E4866),
      cardBorder: Color(0x00FFFFFF),
      playerGradient: [Color(0xFF5E4866), Color(0xFF382A4D), Color(0xFF191326)],
    ),
  );

  static const AppPalette amber = AppPalette(
    id: 'amber',
    name: '琥珀',
    tagline: '暖光入盏 · 岁月鎏金',
    light: PaletteColors(
      background: Color(0xFFF8F4EB),
      surface: Color(0xFFFDFBF5),
      surfaceContainerHighest: Color(0xFFEFE7D6),
      card: Color(0xFFFDFBF5),
      textPrimary: Color(0xFF292318),
      textSecondary: Color(0xFF6F6552),
      textTertiary: Color(0xFFA89D85),
      primary: Color(0xFF96660F),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF6B4906),
      snackBarBackground: Color(0xEE8F6214),
      cardBorder: Color(0x14292318),
      playerGradient: [Color(0xFFEFE3CC), Color(0xFFF7F1E3), Color(0xFFFDFBF5)],
    ),
    dark: PaletteColors(
      background: Color(0xFF161209),
      surface: Color(0xFF201A0F),
      surfaceContainerHighest: Color(0xFF2E2718),
      card: Color(0xFF241D11),
      textPrimary: Color(0xFFF0E9D8),
      textSecondary: Color(0xFFB0A58C),
      textTertiary: Color(0xFF776E58),
      primary: Color(0xFFDBA640),
      onPrimary: Color(0xFF2A1D05),
      onSecondaryContainer: Color(0xFFF2D28E),
      snackBarBackground: Color(0xEE8A661C),
      cardBorder: Color(0x00FFFFFF),
      playerGradient: [Color(0xFF4C3D1F), Color(0xFF2C2413), Color(0xFF161209)],
    ),
  );

  static const AppPalette teal = AppPalette(
    id: 'teal',
    name: '黛青',
    tagline: '远山如黛 · 静水深流',
    light: PaletteColors(
      background: Color(0xFFF2F6F5),
      surface: Color(0xFFFAFCFB),
      surfaceContainerHighest: Color(0xFFE1EBE8),
      card: Color(0xFFFAFCFB),
      textPrimary: Color(0xFF1A2422),
      textSecondary: Color(0xFF5A6B67),
      textTertiary: Color(0xFF93A5A0),
      primary: Color(0xFF2F6D66),
      onPrimary: Color(0xFFFFFFFF),
      onSecondaryContainer: Color(0xFF1F4B45),
      snackBarBackground: Color(0xEE2F6D66),
      cardBorder: Color(0x141A2422),
      playerGradient: [Color(0xFFDCE9E5), Color(0xFFEBF2F0), Color(0xFFFAFCFB)],
    ),
    dark: PaletteColors(
      background: Color(0xFF0D1413),
      surface: Color(0xFF151F1D),
      surfaceContainerHighest: Color(0xFF21302D),
      card: Color(0xFF192523),
      textPrimary: Color(0xFFE4ECEA),
      textSecondary: Color(0xFF9CAEAA),
      textTertiary: Color(0xFF62726E),
      primary: Color(0xFF74B8AE),
      onPrimary: Color(0xFF0A201C),
      onSecondaryContainer: Color(0xFFAEDAD2),
      snackBarBackground: Color(0xEE2E5D57),
      cardBorder: Color(0x00FFFFFF),
      playerGradient: [Color(0xFF26403C), Color(0xFF16211F), Color(0xFF0D1413)],
    ),
  );
}
