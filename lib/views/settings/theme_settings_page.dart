import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../player/mini_player.dart';
import '../widgets/ui_helpers.dart';

/// 主题配色选择：每套方案呈现色标与浅色/深色双预览，点选即时生效并持久化。
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themePaletteProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('主题配色')),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  MediaQuery.paddingOf(context).bottom + 104,
                ),
                children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                child: Text(
                  '配色方案',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final palette in AppPalette.all) ...[
                _PaletteCard(
                  palette: palette,
                  selected: palette.id == current.id,
                ),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  '点选即可生效，与「主题模式」的浅色 / 深色 / 系统设置互不影响。',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }
}

class _PaletteCard extends ConsumerWidget {
  final AppPalette palette;
  final bool selected;

  const _PaletteCard({required this.palette, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name}，${palette.tagline}',
      child: AnimatedContainer(
        duration: motionDuration(context, const Duration(milliseconds: 220)),
        curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? theme.colorScheme.primary : appColors.glassBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              ref.read(themePaletteProvider.notifier).setPalette(palette),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PalettePreview(
                        colors: palette.light,
                        modeLabel: '浅',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PalettePreview(
                        colors: palette.dark,
                        modeLabel: '深',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    // 颜料三色小圆点：底纸 + 墨色 + 印泥强调色
                    _PigmentSwatches(palette: palette),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                palette.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if (palette.id == AppPalette.defaultId) ...[
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '默认',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: theme
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            palette.tagline,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      duration: motionDuration(
                        context,
                        const Duration(milliseconds: 180),
                      ),
                      opacity: selected ? 1 : 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _PigmentSwatches extends StatelessWidget {
  final AppPalette palette;

  const _PigmentSwatches({required this.palette});

  @override
  Widget build(BuildContext context) {
    final swatches = [
      (color: palette.light.background, ring: palette.light.textPrimary),
      (color: palette.dark.background, ring: palette.dark.textPrimary),
      (color: palette.light.primary, ring: palette.light.primary),
    ];
    return SizedBox(
      width: 42,
      height: 20,
      child: Stack(
        children: [
          for (var i = 0; i < swatches.length; i++)
            Positioned(
              left: i * 11.0,
              top: 1,
              child: Container(
                width: 18,
                height: 18,
                padding: const EdgeInsets.all(1.3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: swatches[i].color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: swatches[i].ring.withValues(alpha: 0.22),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 用方案自身的 token 绘出迷你播放器示意（渐变底幕 + 主色圆钮 + 进度线）。
class _PalettePreview extends StatelessWidget {
  final PaletteColors colors;
  final String modeLabel;

  const _PalettePreview({required this.colors, required this.modeLabel});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 70),
      child: Container(
        padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors.playerGradient,
        ),
        border: Border.all(
          color: colors.textPrimary.withValues(alpha: 0.09),
          width: 0.9,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          Widget bar(Color color, double widthFactor) => Container(
            width: w * widthFactor,
            height: 4.5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2.5),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 10,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(colors.textPrimary.withValues(alpha: 0.78), 0.72),
                        const SizedBox(height: 4),
                        bar(colors.textSecondary.withValues(alpha: 0.65), 0.44),
                      ],
                    ),
                  ),
                  Text(
                    modeLabel,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 2,
                        child: ColoredBox(color: colors.primary),
                      ),
                      Expanded(
                        flex: 3,
                        child: ColoredBox(
                          color: colors.textPrimary.withValues(alpha: 0.22),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}
