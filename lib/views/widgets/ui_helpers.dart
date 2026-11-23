import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 返回适配系统「减弱动态效果」设置的动画时长。
Duration motionDuration(BuildContext context, Duration normal) {
  final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return disable ? Duration.zero : normal;
}

/// 破坏性/高风险操作确认框：默认将焦点落在安全的「取消」按钮上，
/// 确认按钮统一采用主题 `error` / `onError` 语义色。
Future<bool> showDestructiveConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '取消',
  required String confirmLabel,
  IconData? icon,
}) async {
  final theme = Theme.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: icon == null
          ? Text(title)
          : Row(
              children: [
                Icon(icon, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
              ],
            ),
      content: Text(message, style: const TextStyle(height: 1.45)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 统一的轻量胶囊快捷操作钮（曲库 / 收藏共用），支持键盘聚焦与触控友好高度。
class ActionPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  const ActionPillButton({
    super.key,
    required this.icon,
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Material(
        color: filled
            ? theme.colorScheme.primary.withValues(alpha: isLight ? 0.12 : 0.20)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: filled
                      ? theme.colorScheme.primary.withValues(alpha: 0.26)
                      : appColors.subtleDivider,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: filled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                      color: filled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
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

/// 底部弹层标准化顶栏：统一拖动手柄、标题区与桌面端友好的显式关闭按钮。
class ModalSheetHeader extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> trailingActions;
  final bool showCloseButton;

  const ModalSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailingActions = const [],
    this.showCloseButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Center(
            child: ExcludeSemantics(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 10, 8),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              ...trailingActions,
              if (showCloseButton)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 宽屏居中限宽容器，避免超宽桌面窗口下拉长列表导致扫视距离过远。
class ResponsivePageContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsivePageContainer({
    super.key,
    required this.child,
    this.maxWidth = 900,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 随动画收起时同步阻断键盘焦点、指针命中与读屏树遍历的折叠容器，
/// 防止 `Tab` 键落入高度为 0 的隐藏控件。
class CollapsibleSection extends StatelessWidget {
  final Animation<double> animation;
  final bool collapsed;
  final Widget child;

  const CollapsibleSection({
    super.key,
    required this.animation,
    required this.collapsed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final body = ExcludeFocus(
      excluding: collapsed,
      child: ExcludeSemantics(
        excluding: collapsed,
        child: IgnorePointer(ignoring: collapsed, child: child),
      ),
    );
    if (reduceMotion) {
      return collapsed ? const SizedBox.shrink() : body;
    }
    return SizeTransition(
      sizeFactor: animation,
      alignment: Alignment.topCenter,
      child: body,
    );
  }
}
