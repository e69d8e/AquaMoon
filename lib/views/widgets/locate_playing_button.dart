import 'package:flutter/material.dart';

import 'glass_container.dart';

/// 悬浮在歌曲列表右下角的「定位当前播放」轻巧胶囊按钮。
///
/// 只在当前播放歌曲确实位于列表中时由调用方插入；采用磨砂纸质感底托
/// 与主题主色图标，在滚动曲目之上既醒目又不突兀。
class LocatePlayingButton extends StatelessWidget {
  const LocatePlayingButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Tooltip(
      message: '定位当前播放',
      child: GlassContainer(
        width: 42,
        height: 42,
        borderRadius: BorderRadius.circular(21),
        blurSigma: 20,
        tint: theme.colorScheme.surface.withValues(alpha: isLight ? 0.88 : 0.82),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.28),
          width: 1,
        ),
        shadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(
              child: Icon(
                Icons.my_location_rounded,
                size: 19,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
