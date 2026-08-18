import 'dart:math';
import 'package:flutter/material.dart';

class AppToast {
  /// Displays a floating, adaptive-width toast with theme green semi-transparent styling
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(milliseconds: 1400),
    Color? backgroundColor,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    // Theme green semi-transparent background (~90% opacity)
    final bg = backgroundColor ??
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
      maxLines: 1,
    )..layout();

    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = textPainter.width + (icon != null ? 24 : 0) + 40;
    final double finalWidth = contentWidth.clamp(100.0, max(100.0, screenWidth - 36)).toDouble();

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
        duration: duration,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
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
