import 'dart:math';

import 'package:flutter/material.dart';

class AppToast {
  /// Displays a floating, adaptive-width toast with theme green semi-transparent styling.
  ///
  /// [duration] defaults by message length: short messages stay 1.4s, longer
  /// ones (error details, paths) get 2.8s so they remain readable.
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

    // Theme green semi-transparent background (~90% opacity)
    final bg =
        backgroundColor ??
        (isLight
            ? const Color(0xEE1DB954) // Vibrant Theme Green with 93% opacity
            : const Color(0xEE15803D)); // Deep Theme Green with 93% opacity

    // Measure exact text width to adapt container width
    final textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: MediaQuery.of(context).size.width - 60);

    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = textPainter.width + (icon != null ? 24 : 0) + 40;
    final double finalWidth = contentWidth
        .clamp(100.0, max(100.0, screenWidth - 36))
        .toDouble();

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: finalWidth,
        elevation: 3,
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.28),
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
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                message,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: maxLines > 1 ? TextAlign.left : TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
