import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../providers/theme_provider.dart';

/// 主题配色选择:每套方案带浅色/深色双预览,点选即时生效并持久化。
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themePaletteProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('主题配色')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              '配色方案',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
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
              '点选即可生效,与「主题模式」的浅色 / 深色 / 系统设置互不影响。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ref.read(themePaletteProvider.notifier).setPalette(palette),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _PalettePreview(colors: palette.light)),
                  const SizedBox(width: 10),
                  Expanded(child: _PalettePreview(colors: palette.dark)),
                ],
              ),
              const SizedBox(height: 12),
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
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
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
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
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
      ),
    );
  }
}

/// 用方案自身的 token 画一个迷你播放器示意图(文本条 + 主色圆点 + 进度线)。
class _PalettePreview extends StatelessWidget {
  final PaletteColors colors;

  const _PalettePreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors.playerGradient,
        ),
        border: Border.all(color: colors.cardBorder, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          Widget bar(Color color, double widthFactor) => Container(
            width: w * widthFactor,
            height: 5,
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
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: bar(
                      colors.textPrimary.withValues(alpha: 0.75),
                      0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              bar(colors.textSecondary, 0.5),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(1.5),
                child: SizedBox(
                  height: 3,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ColoredBox(color: colors.textPrimary),
                      ),
                      Expanded(
                        flex: 3,
                        child: ColoredBox(
                          color: colors.textPrimary.withValues(alpha: 0.15),
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
    );
  }
}
