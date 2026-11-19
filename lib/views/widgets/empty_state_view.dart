import 'package:flutter/material.dart';

/// 统一的留白空状态视图：以淡墨涟漪光环托起图标，给出清晰、可行动的引导。
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Color? iconColor;
  final double maxWidth;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.iconColor,
    this.maxWidth = 340,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = iconColor ?? theme.colorScheme.primary;
    final isLight = theme.brightness == Brightness.light;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 双重极淡墨韵涟漪环
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: isLight ? 0.06 : 0.09),
                  border: Border.all(
                    color: accent.withValues(alpha: isLight ? 0.12 : 0.16),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: isLight ? 0.10 : 0.15),
                    ),
                    child: Icon(
                      icon,
                      size: 28,
                      color: accent.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
