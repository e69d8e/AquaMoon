import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../providers/qq_music_provider.dart';
import '../../services/qq_music_service.dart';
import 'qq_music_auth_dialog.dart';

/// 触发一次 QQ 音乐收藏同步；未绑定时先弹出账号配置框，同步结果以 Toast 反馈。
Future<void> triggerQQMusicSync(BuildContext context, WidgetRef ref) async {
  final qqState = ref.read(qqMusicFavoritesProvider);
  if (!qqState.isBound) {
    await QQMusicAuthDialog.show(context);
    return;
  }
  try {
    final summary = await ref
        .read(qqMusicFavoritesProvider.notifier)
        .syncFavorites(silent: false);
    if (context.mounted && summary.isNotEmpty) {
      AppToast.show(
        context,
        summary,
        icon: Icons.check_circle_outline_rounded,
      );
    }
  } on QQMusicApiException catch (e) {
    if (context.mounted) {
      AppToast.show(
        context,
        e.message,
        icon: Icons.error_outline_rounded,
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        '同步失败，请检查网络连接后重试',
        icon: Icons.error_outline_rounded,
      );
    }
  }
}

/// QQ 音乐同步失败时的内联提示条，提供直接进入账号配置的入口。
class QQMusicSyncErrorBanner extends StatelessWidget {
  final String message;

  const QQMusicSyncErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: errorColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: errorColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: errorColor,
                ),
              ),
            ),
            TextButton(
              onPressed: () => QQMusicAuthDialog.show(context),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('配置', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
