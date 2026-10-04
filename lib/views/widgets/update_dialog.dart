import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/apk_installer.dart';
import '../../core/utils/app_toast.dart';
import '../../models/update_info.dart';
import '../../services/update_service.dart';

/// Dialog shown when a newer release is found — both from the silent
/// startup check and the manual check in settings.
///
/// On Android, when the release ships an `.apk` asset, the primary action
/// downloads it in-app with a progress bar and then launches the system
/// package installer.
Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final ValueNotifier<_DownloadState> _download = ValueNotifier(
    const _DownloadState(),
  );
  late final UpdateService _updateService;
  bool _disposed = false;

  bool get _supportsInAppInstall =>
      !kIsWeb && Platform.isAndroid && widget.info.apkUrl != null;

  @override
  void initState() {
    super.initState();
    _updateService = UpdateService();
  }

  @override
  void dispose() {
    _disposed = true;
    _download.dispose();
    _updateService.dispose();
    super.dispose();
  }

  Future<void> _startInAppDownload() async {
    if (_download.value.phase != _DownloadPhase.idle) return;
    _download.value = const _DownloadState(phase: _DownloadPhase.downloading);
    try {
      final path = await _updateService.downloadApk(
        url: widget.info.apkUrl!,
        version: widget.info.latestVersion,
        onProgress: (received, total) {
          if (_disposed) return;
          _download.value = _DownloadState(
            phase: _DownloadPhase.downloading,
            receivedBytes: received,
            totalBytes: total,
          );
        },
      );
      if (_disposed) return;
      _download.value = const _DownloadState(phase: _DownloadPhase.installing);
      final launched = await ApkInstaller.installApk(path);
      if (_disposed) return;
      if (launched) {
        _download.value = const _DownloadState(phase: _DownloadPhase.idle);
        if (mounted) Navigator.of(context).pop();
      } else {
        // 跳转了「未知来源授权」页，授权后重新触发即可。
        _download.value = const _DownloadState(phase: _DownloadPhase.idle);
        if (mounted) {
          AppToast.show(
            context,
            '请先允许安装未知来源应用，再重试更新',
            icon: Icons.shield_outlined,
          );
        }
      }
    } catch (_) {
      if (_disposed) return;
      _download.value = const _DownloadState(phase: _DownloadPhase.idle);
      if (mounted) {
        AppToast.show(
          context,
          '下载安装失败，请检查网络后重试或前往发布页下载',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('发现新版本 v${widget.info.latestVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前版本 v${widget.info.currentVersion}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.info.releaseTitle.trim().isNotEmpty &&
              widget.info.releaseTitle.trim() != widget.info.latestVersion &&
              widget.info.releaseTitle.trim() !=
                  'v${widget.info.latestVersion}') ...[
            const SizedBox(height: 8),
            Text(
              widget.info.releaseTitle.trim(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
          if (widget.info.releaseNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.releaseNotes.trim(),
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('下次再说'),
        ),
        ValueListenableBuilder<_DownloadState>(
          valueListenable: _download,
          builder: (context, state, _) {
            final busy =
                state.phase == _DownloadPhase.downloading ||
                state.phase == _DownloadPhase.installing;

            if (_supportsInAppInstall) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                launchUrl(
                                  Uri.parse(widget.info.releaseUrl),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                        child: const Text('前往发布页'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: busy ? null : _startInAppDownload,
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          state.phase == _DownloadPhase.installing
                              ? '准备安装'
                              : '应用内更新',
                        ),
                      ),
                    ],
                  ),
                  if (state.phase == _DownloadPhase.downloading) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 240,
                      child: LinearProgressIndicator(
                        value: state.totalBytes != null
                            ? (state.receivedBytes / state.totalBytes!)
                                  .clamp(0.0, 1.0)
                            : null,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.totalBytes != null
                          ? '${(state.receivedBytes / 1024 / 1024).toStringAsFixed(1)} / ${(state.totalBytes! / 1024 / 1024).toStringAsFixed(1)} MB'
                          : '已下载 ${(state.receivedBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              );
            }

            return FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse(widget.info.releaseUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('前往下载'),
            );
          },
        ),
      ],
    );
  }
}

enum _DownloadPhase { idle, downloading, installing }

class _DownloadState {
  final _DownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  const _DownloadState({
    this.phase = _DownloadPhase.idle,
    this.receivedBytes = 0,
    this.totalBytes,
  });
}
