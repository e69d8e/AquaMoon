import 'package:flutter/material.dart';

/// 悬浮在歌曲列表右下角的「定位当前播放」小按钮。
///
/// 只在当前播放歌曲确实位于列表中时由调用方插入；采用主题主色实心圆，
/// 保证在滚动内容与磨砂玻璃迷你播放器之上都有足够对比度。
class LocatePlayingButton extends StatelessWidget {
  const LocatePlayingButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '定位当前播放',
      child: Material(
        color: theme.colorScheme.primary,
        elevation: 3,
        shadowColor: theme.colorScheme.primary.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.my_location_rounded,
              size: 20,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
