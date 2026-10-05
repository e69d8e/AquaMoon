import 'dart:ui';

import 'package:flutter/material.dart';

/// 磨砂玻璃容器:对背后已绘制的内容做高斯模糊,再叠加一层随亮暗模式变化的
/// 半透明底色,形成 iOS 风格的毛玻璃面板。
///
/// [BackdropFilter] 只能模糊同一层树中先于它绘制的内容,因此玻璃面板必须
/// 悬浮在滚动内容之上(Stack 覆盖层、底部导航栏、模态弹层)才有真实磨砂效果。
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.blurSigma = 20,
    this.tint,
    this.shadow,
    this.padding,
    this.child,
  });

  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  /// 高斯模糊强度;越大越"雾"。20 左右在可读性与通透感之间比较平衡。
  final double blurSigma;

  /// 覆盖在模糊之上的底色;缺省时按亮暗模式取主题 surface 加透明度。
  final Color? tint;

  /// 画在玻璃边缘外的柔和投影(仅圆角面板需要,贴边导航栏不用)。
  final List<BoxShadow>? shadow;

  final EdgeInsetsGeometry? padding;
  final Widget? child;

  /// 浅色模式底色不透明度略高于深色,保证浅底上的文字对比度。
  static Color defaultTint(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return theme.colorScheme.surface.withValues(alpha: isLight ? 0.70 : 0.58);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: ColoredBox(
            color: tint ?? defaultTint(context),
            child: padding == null
                ? child
                : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
  }
}
