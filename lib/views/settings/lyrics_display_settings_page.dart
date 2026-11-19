import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../models/lyrics_display_settings.dart';
import '../../providers/lyrics_settings_provider.dart';

/// 歌词显示设置：字号、行距、当前行高亮与自动滚动位置。
class LyricsDisplaySettingsPage extends ConsumerWidget {
  const LyricsDisplaySettingsPage({super.key});

  static const _alignmentOptions = [
    (0.22, '偏上'),
    (0.34, '适中'),
    (0.5, '居中'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(lyricsDisplaySettingsProvider);
    final notifier = ref.read(lyricsDisplaySettingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌词显示'),
        actions: [
          TextButton(
            onPressed: () {
              notifier.resetToDefaults();
              AppToast.show(
                context,
                '已恢复默认歌词显示',
                icon: Icons.restart_alt_rounded,
              );
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              _LyricsPreviewCard(settings: settings),
              const SizedBox(height: 22),
              _sectionHeader(theme, '字号与行距'),
              Card(
                child: Column(
                  children: [
                    _SliderRow(
                      icon: Icons.format_size_rounded,
                      title: '歌词字号',
                      subtitle: '普通歌词行的大小',
                      value: settings.baseFontSize,
                      min: LyricsDisplaySettings.minBaseFontSize,
                      max: LyricsDisplaySettings.maxBaseFontSize,
                      divisions:
                          (LyricsDisplaySettings.maxBaseFontSize -
                                  LyricsDisplaySettings.minBaseFontSize)
                              .round(),
                      valueLabel: '${settings.baseFontSize.round()} px',
                      // 拖动中只更新内存状态，松手才落盘，避免每帧写 Hive。
                      onChanged: (value) {
                        // Keep the active line at least as large as base lines.
                        final active = settings.activeFontSize < value
                            ? value
                            : settings.activeFontSize;
                        notifier.updateLive(
                          settings.copyWith(
                            baseFontSize: value,
                            activeFontSize: active,
                          ),
                        );
                      },
                      onChangeEnd: (_) => notifier.persist(),
                    ),
                    const Divider(height: 1, indent: 56),
                    _SliderRow(
                      icon: Icons.campaign_rounded,
                      title: '当前行字号',
                      subtitle: '正在播放歌词行的大小',
                      value: settings.activeFontSize,
                      min: LyricsDisplaySettings.minActiveFontSize,
                      max: LyricsDisplaySettings.maxActiveFontSize,
                      divisions:
                          (LyricsDisplaySettings.maxActiveFontSize -
                                  LyricsDisplaySettings.minActiveFontSize)
                              .round(),
                      valueLabel: '${settings.activeFontSize.round()} px',
                      onChanged: (value) {
                        final base = settings.baseFontSize > value
                            ? value
                            : settings.baseFontSize;
                        notifier.updateLive(
                          settings.copyWith(
                            activeFontSize: value,
                            baseFontSize: base,
                          ),
                        );
                      },
                      onChangeEnd: (_) => notifier.persist(),
                    ),
                    const Divider(height: 1, indent: 56),
                    _SliderRow(
                      icon: Icons.format_line_spacing_rounded,
                      title: '行间距',
                      subtitle: '歌词行与行之间的距离',
                      value: settings.lineHeight,
                      min: LyricsDisplaySettings.minLineHeight,
                      max: LyricsDisplaySettings.maxLineHeight,
                      divisions:
                          ((LyricsDisplaySettings.maxLineHeight -
                                      LyricsDisplaySettings.minLineHeight) *
                                  10)
                              .round(),
                      valueLabel: '${settings.lineHeight.toStringAsFixed(1)} 倍',
                      onChanged: (value) => notifier.updateLive(
                        settings.copyWith(lineHeight: value),
                      ),
                      onChangeEnd: (_) => notifier.persist(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _sectionHeader(theme, '自动滚动'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.vertical_align_center_rounded,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          '当前行停留位置',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SegmentedButton<double>(
                        segments: _alignmentOptions
                            .map(
                              (option) => ButtonSegment(
                                value: option.$1,
                                label: Text(option.$2),
                              ),
                            )
                            .toList(),
                        selected: {_nearestAlignment(settings.scrollAlignment)},
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStatePropertyAll(
                            TextStyle(fontSize: 12),
                          ),
                        ),
                        onSelectionChanged: (selection) {
                          notifier.update(
                            settings.copyWith(scrollAlignment: selection.first),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static double _nearestAlignment(double value) {
    return _alignmentOptions
        .map((option) => option.$1)
        .reduce(
          (best, current) =>
              (current - value).abs() < (best - value).abs() ? current : best,
        );
  }
}

/// 按当前设置与当前主题渐变底幕渲染实时歌词预览（带上下柔雾渐隐）。
class _LyricsPreviewCard extends StatelessWidget {
  final LyricsDisplaySettings settings;

  const _LyricsPreviewCard({required this.settings});

  static const _sampleLines = [
    '前奏渐起',
    '夜色漫过窗台',
    '你的名字在耳边',
    '像一首未完的歌',
    '轻轻落进心底',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;
    const activeIndex = 2;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: appColors.playerGradient,
        ),
        border: Border.all(color: appColors.glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Column(
                children: [
                  for (var i = 0; i < _sampleLines.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 12,
                      ),
                      child: Text(
                        _sampleLines[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: i == activeIndex
                              ? settings.activeFontSize
                              : settings.baseFontSize,
                          fontWeight: i == activeIndex
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: i == activeIndex
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: (i - activeIndex).abs() <= 1
                                      ? (isLight ? 0.48 : 0.54)
                                      : (isLight ? 0.30 : 0.36),
                                ),
                          height: settings.lineHeight,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 36,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        appColors.playerGradient.first,
                        appColors.playerGradient.first.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 36,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        appColors.playerGradient.last.withValues(alpha: 0),
                        appColors.playerGradient.last,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _SliderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      valueLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: valueLabel,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
