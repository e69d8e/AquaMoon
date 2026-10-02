import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/update_info.dart';

/// Dialog shown when a newer release is found — both from the silent
/// startup check and the manual check in settings.
Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('发现新版本 v${info.latestVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前版本 v${info.currentVersion}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
          if (info.releaseTitle.trim().isNotEmpty &&
              info.releaseTitle.trim() != info.latestVersion &&
              info.releaseTitle.trim() != 'v${info.latestVersion}') ...[
            const SizedBox(height: 8),
            Text(
              info.releaseTitle.trim(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
          if (info.releaseNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes.trim(),
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('下次再说'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            launchUrl(
              Uri.parse(info.releaseUrl),
              mode: LaunchMode.externalApplication,
            );
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('前往下载'),
        ),
      ],
    ),
  );
}
