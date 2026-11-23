import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class AppToast {
  static OverlayEntry? _activeOverlayEntry;
  static Timer? _overlayTimer;

  static void _dismissOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _activeOverlayEntry?.remove();
    _activeOverlayEntry = null;
  }

  /// 显示跟随当前主题配色的悬浮胶囊提示（默认使用当前调色板的 `snackBarBackground`）。
  ///
  /// - 普通页面走 `ScaffoldMessenger` 浮动 `SnackBar`；
  /// - 处于模态弹窗 / 底部弹层之上时自动升至根 `Overlay`，避免提示压在遮罩背后；
  /// - 默认至少保留 2.4 秒、最多允许 2 行自动换行，提供关闭按钮与读屏 `liveRegion`。
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration? duration,
    Color? backgroundColor,
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final effectiveDuration =
        duration ??
        (message.length > 24
            ? const Duration(milliseconds: 3600)
            : const Duration(milliseconds: 2400));

    // 优先使用当前配色方案的 snackBarBackground（如水墨丹青的朱砂印色），
    // 脱离主题的孤立测试容器下优雅回退到主色深调。
    final bg =
        backgroundColor ??
        theme.snackBarTheme.backgroundColor ??
        theme.colorScheme.primary.withValues(alpha: isLight ? 0.93 : 0.88);
    final fg = theme.snackBarTheme.contentTextStyle?.color ?? Colors.white;

    // 测量文本宽度以实现紧凑自适应胶囊宽度，保留图标与关闭按钮余量。
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScaler = MediaQuery.textScalerOf(context);
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
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: max(0.0, screenWidth - 112));

    final contentWidth = textPainter.width + (icon != null ? 24 : 0) + 68;
    textPainter.dispose();
    final double finalWidth = contentWidth
        .clamp(124.0, max(124.0, screenWidth - 32))
        .toDouble();

    final isInModalRoute = ModalRoute.of(context) is PopupRoute;
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);

    if (isInModalRoute && rootOverlay != null) {
      _dismissOverlay();
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) => _OverlayToastWidget(
          message: message,
          icon: icon,
          backgroundColor: bg,
          foregroundColor: fg,
          maxWidth: finalWidth,
          maxLines: maxLines,
          duration: effectiveDuration,
          onDismiss: () {
            if (_activeOverlayEntry == entry) {
              _dismissOverlay();
            }
          },
        ),
      );
      _activeOverlayEntry = entry;
      rootOverlay.insert(entry);
      _overlayTimer = Timer(effectiveDuration, () {
        if (_activeOverlayEntry == entry) {
          _dismissOverlay();
        }
      });
      return;
    }

    final scaffold = ScaffoldMessenger.maybeOf(context);
    if (scaffold == null) return;
    _dismissOverlay();
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: finalWidth,
        elevation: 4,
        backgroundColor: bg,
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        duration: effectiveDuration,
        content: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 15, color: fg),
                tooltip: '关闭提示',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                visualDensity: VisualDensity.compact,
                onPressed: () => scaffold.hideCurrentSnackBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final double maxWidth;
  final int maxLines;
  final Duration duration;
  final VoidCallback onDismiss;

  const _OverlayToastWidget({
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.maxWidth,
    required this.maxLines,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_OverlayToastWidget> createState() => _OverlayToastWidgetState();
}

class _OverlayToastWidgetState extends State<_OverlayToastWidget> {
  void _pauseTimer() {
    AppToast._overlayTimer?.cancel();
  }

  void _resumeTimer() {
    AppToast._overlayTimer?.cancel();
    AppToast._overlayTimer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom + 24;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomPadding,
      child: Center(
        child: MouseRegion(
          onEnter: (_) => _pauseTimer(),
          onExit: (_) => _resumeTimer(),
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 16, color: widget.foregroundColor),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: widget.maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.foregroundColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: widget.foregroundColor,
                      ),
                      tooltip: '关闭提示',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onDismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
