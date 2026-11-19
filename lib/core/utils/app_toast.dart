import 'dart:math';

import 'package:flutter/material.dart';

class AppToast {
  /// 显示跟随当前主题配色的悬浮胶囊提示（默认使用当前调色板的 `snackBarBackground`）。
  ///
  /// [duration] 按文案长度自动调整：短提示 1.4s，较长提示（错误细节、路径）2.8s。
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration? duration,
    Color? backgroundColor,
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final effectiveDuration =
        duration ??
        (message.length > 24
            ? const Duration(milliseconds: 2800)
            : const Duration(milliseconds: 1400));

    // 优先使用当前配色方案的 snackBarBackground（如水墨丹青的朱砂印色），
    // 脱离主题的孤立测试容器下优雅回退到主色深调。
    final bg =
        backgroundColor ??
        theme.snackBarTheme.backgroundColor ??
        theme.colorScheme.primary.withValues(alpha: isLight ? 0.93 : 0.88);
    final fg =
        theme.snackBarTheme.contentTextStyle?.color ?? Colors.white;

    // 测量文本宽度以实现紧凑自适应胶囊宽度。
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: max(0.0, screenWidth - 64));

    final contentWidth = textPainter.width + (icon != null ? 24 : 0) + 42;
    textPainter.dispose();
    final double finalWidth = contentWidth
        .clamp(108.0, max(108.0, screenWidth - 36))
        .toDouble();

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: finalWidth,
        elevation: 4,
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        duration: effectiveDuration,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: maxLines > 1
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                message,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: maxLines > 1 ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
