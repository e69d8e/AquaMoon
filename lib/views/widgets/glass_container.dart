import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 磨砂玻璃容器：对背后已绘制的内容做高斯模糊，叠加随亮暗模式变化的
/// 半透明底色与极细描边，呈现宣纸薄雾般的通透质感。
///
/// [BackdropFilter] 只能模糊同一层树中先于它绘制的内容，因此玻璃面板必须
/// 悬浮在滚动内容之上（Stack 覆盖层、底部导航栏、模态弹层）才有真实磨砂效果。
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.blurSigma = 20,
    this.enableBlur = true,
    this.tint,
    this.border,
    this.showBorder = true,
    this.shadow,
    this.padding,
    this.child,
  });

  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  /// 高斯模糊强度；越大越"雾"。20–24 在可读性与通透感之间比较平衡。
  final double blurSigma;

  /// 是否启用实时 [BackdropFilter] 高斯模糊；长列表卡片或大型可滚动弹层应设为 false
  /// 以避免整屏反复离屏重绘，改以高不透明度宣纸底色保真。
  final bool enableBlur;

  /// 覆盖在模糊之上的底色；缺省时按亮暗模式取主题 surface 加透明度。
  final Color? tint;

  /// 自定义描边；为 null 且 [showBorder] 为 true 时自动绘制极细玻璃边缘线。
  final BoxBorder? border;

  /// 是否绘制默认极细边缘线，让悬浮玻璃在浅底和深底上都轮廓清晰。
  final bool showBorder;

  /// 画在玻璃边缘外的柔和投影（仅圆角面板需要，贴边导航栏不用）。
  final List<BoxShadow>? shadow;

  final EdgeInsetsGeometry? padding;
  final Widget? child;

  /// 浅色模式底色不透明度略高于深色，保证浅底上的文字对比度。
  static Color defaultTint(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return theme.colorScheme.surface.withValues(alpha: isLight ? 0.76 : 0.68);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final effectiveBorder =
        border ??
        (showBorder
            ? Border.all(color: appColors.glassBorder, width: 0.9)
            : null);

    final effectiveTint = tint ??
        (enableBlur
            ? defaultTint(context)
            : Theme.of(context).colorScheme.surface.withValues(
                alpha: isLight ? 0.96 : 0.93,
              ));

    final surfaceBody = DecoratedBox(
      decoration: BoxDecoration(
        color: effectiveTint,
        borderRadius: borderRadius,
        border: effectiveBorder,
      ),
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child),
    );

    if (!enableBlur) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
        child: ClipRRect(borderRadius: borderRadius, child: surfaceBody),
      );
    }

    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: surfaceBody,
          ),
        ),
      ),
    );
  }
}
