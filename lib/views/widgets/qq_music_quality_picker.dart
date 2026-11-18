import 'package:flutter/material.dart';

import '../../models/qq_music_discovery.dart';

/// 弹出音质选择面板。
///
/// 既用于「在线播放音质」，也用于单曲下载时的音质选择与设置页的默认下载
/// 音质，三处共用同一份 [QQMusicStreamQuality] 定义与同一套文案，避免出现
/// 「设置里选无损、下载时却悄悄降级」的困惑。
Future<QQMusicStreamQuality?> showQQMusicQualityPicker(
  BuildContext context, {
  required String title,
  required QQMusicStreamQuality selected,
  bool hasCookie = false,
  String? subtitle,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<QQMusicStreamQuality>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (final quality in QQMusicStreamQuality.values)
                _QualityOption(
                  quality: quality,
                  selected: quality == selected,
                  hasCookie: hasCookie,
                  onTap: () => Navigator.of(sheetContext).pop(quality),
                ),
              if (!hasCookie)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '无损及以上音质需要先在设置中绑定 QQ 音乐 Cookie，否则会自动回退到可用音质。',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.quality,
    required this.selected,
    required this.hasCookie,
    required this.onTap,
  });

  final QQMusicStreamQuality quality;
  final bool selected;
  final bool hasCookie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = quality.requiresCookie && !hasCookie;
    final foreground = locked
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              quality.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
          if (quality.extension == 'flac') ...[
            const SizedBox(width: 6),
            _Tag(
              text: 'FLAC',
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              foreground: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${quality.filenamePrefix} · ${quality.extension.toUpperCase()}'
        '${quality.requiresCookie ? ' · 需 Cookie' : ''}',
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary)
          : null,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.foreground});

  final String text;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: foreground,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}