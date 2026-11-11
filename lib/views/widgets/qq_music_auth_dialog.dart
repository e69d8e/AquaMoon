import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../models/qq_music_config.dart';
import '../../providers/qq_music_provider.dart';
import '../../services/qq_music_service.dart';

class QQMusicAuthDialog extends ConsumerStatefulWidget {
  const QQMusicAuthDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const QQMusicAuthDialog(),
    );
  }

  @override
  ConsumerState<QQMusicAuthDialog> createState() => _QQMusicAuthDialogState();
}

class _QQMusicAuthDialogState extends ConsumerState<QQMusicAuthDialog> {
  late final TextEditingController _accountController;
  late final TextEditingController _cookieController;
  bool _showCookieSection = false;
  bool _isSubmitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    final config = ref.read(qqMusicFavoritesProvider).config;
    final initialAccountInput = config.uin.trim().isNotEmpty
        ? config.uin.trim()
        : config.dissid.trim();
    _accountController = TextEditingController(text: initialAccountInput);
    _cookieController = TextEditingController(text: config.cookie);
    _showCookieSection = config.cookie.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _accountController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveAndSync() async {
    final rawAccount = _accountController.text.trim();
    final rawCookie = _cookieController.text.trim();

    final parsedInput = QQMusicConfig.parseAccountOrPlaylistInput(rawAccount);
    final cookieUin = QQMusicConfig.extractUinFromCookie(rawCookie);

    var uin = parsedInput.uin.isNotEmpty ? parsedInput.uin : cookieUin;
    var dissid = parsedInput.dissid;

    // 若用户输入了非空内容但既非标准链接也未被识别为 QQ 号，尝试保留数字作为 dissid
    if (uin.isEmpty && dissid.isEmpty && rawAccount.isNotEmpty) {
      final digits = RegExp(r'\d{5,20}').firstMatch(rawAccount)?.group(0) ?? '';
      if (digits.isNotEmpty) {
        uin = digits;
      }
    }

    if (uin.isEmpty && dissid.isEmpty) {
      setState(() {
        _inlineError = '请输入 QQ 号、「我喜欢」歌单分享链接，或粘贴包含 uin 的 Cookie';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    final currentConfig = ref.read(qqMusicFavoritesProvider).config;
    // 如果切换了 QQ 号且未显式指定新 dissid，清空旧 dissid 以便重新解析
    final resolvedDissid = dissid.isNotEmpty
        ? dissid
        : (uin == currentConfig.uin ? currentConfig.dissid : '');

    final newConfig = QQMusicConfig(
      uin: uin,
      dissid: resolvedDissid,
      cookie: rawCookie,
      nickname: uin == currentConfig.uin ? currentConfig.nickname : '',
    );

    try {
      final summary = await ref
          .read(qqMusicFavoritesProvider.notifier)
          .saveConfigAndSync(newConfig);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show(
        context,
        summary,
        icon: Icons.check_circle_outline_rounded,
      );
    } on QQMusicApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _inlineError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _inlineError = '同步失败，请检查网络连接或账号配置后重试';
      });
    }
  }

  Future<void> _handleUnbind() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开 QQ 音乐绑定？'),
        content: const Text(
          '断开后将清空已同步的 QQ 音乐在线收藏列表，「收藏」页将恢复仅显示本地曲库中标记红心的歌曲。',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('断开绑定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(qqMusicFavoritesProvider.notifier).unbind();
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(
      context,
      '已断开 QQ 音乐绑定',
      icon: Icons.link_off_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qqState = ref.watch(qqMusicFavoritesProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.favorite_rounded,
            color: theme.colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '接入 QQ 音乐「我喜欢」',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (qqState.isBound) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前已连接：${qqState.config.displayLabel} · '
                          '共 ${qqState.mergedSongs.length} 首'
                          '${qqState.config.hasCookie ? ' (已启用 Cookie)' : ' (公开免登模式)'}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              const Text(
                'QQ 号 或「我喜欢」歌单分享链接 / ID',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _accountController,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  hintText: '例如：12345678 或粘贴「我喜欢」分享链接',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.65,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) {
                  if (!_isSubmitting) _handleSaveAndSync();
                },
              ),
              const SizedBox(height: 8),
              Text(
                '提示：免登模式下，请确保在 QQ 音乐 App 中将「我喜欢」歌单设为公开，或直接在「我喜欢」歌单右上角点击「分享 → 复制链接」粘贴到上方。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 12),

              // Collapsible Cookie Credentials Section
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _showCookieSection = !_showCookieSection;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showCookieSection
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '配置 Cookie 凭证（可选 · 解锁私密歌单 / VIP音质 / 云端红心同步）',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showCookieSection) ...[
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _cookieController,
                  builder: (context, value, _) {
                    final detectedUin = QQMusicConfig.extractUinFromCookie(
                      value.text,
                    );
                    final detectedKey = QQMusicConfig.extractAuthKeyFromCookie(
                      value.text,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _cookieController,
                          enabled: !_isSubmitting,
                          maxLines: 3,
                          minLines: 2,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            hintText:
                                '粘贴网页版 y.qq.com 的 Cookie（包含 uin=...; qqmusic_key=... 或 qm_keyst=...）',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (value.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                detectedKey.isNotEmpty
                                    ? Icons.check_circle_rounded
                                    : Icons.info_outline_rounded,
                                size: 15,
                                color: detectedKey.isNotEmpty
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  detectedKey.isNotEmpty
                                      ? '已识别登录凭证${detectedUin.isNotEmpty ? ' (QQ: $detectedUin)' : ''}'
                                      : '未检测到 qqmusic_key 或 qm_keyst 字段，请检查 Cookie 是否完整',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: detectedKey.isNotEmpty
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],

              if (_inlineError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _inlineError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (qqState.isBound)
          TextButton(
            onPressed: _isSubmitting ? null : _handleUnbind,
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('断开绑定'),
          ),
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleSaveAndSync,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sync_rounded, size: 18),
          label: Text(_isSubmitting ? '正在同步...' : '保存并同步'),
        ),
      ],
    );
  }
}
