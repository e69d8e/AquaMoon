import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'empty_state_view.dart';

/// 带防抖与安全清空逻辑的歌曲搜索框。
///
/// 清空时先释放焦点再清空控制器，避免中文输入法在合成态收尾时
/// 把已输入字符重新提交回输入框。
class DebouncedSearchField extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onQueryChanged;
  final String hintText;
  final Duration debounceDuration;

  const DebouncedSearchField({
    super.key,
    this.initialQuery = '',
    required this.onQueryChanged,
    this.hintText = '搜索音乐、歌手、专辑...',
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  @override
  State<DebouncedSearchField> createState() => DebouncedSearchFieldState();
}

class DebouncedSearchFieldState extends State<DebouncedSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // 上层查询状态在跨标签页或桌面布局切换时可能存活，重建 State 时回填文本。
    _controller.text = widget.initialQuery;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 立即取消搜索：同时终止防抖定时器、断开输入法连接并通知上层重置筛选。
  void clear() {
    _debounce?.cancel();
    _focusNode.unfocus();
    _controller.clear();
    widget.onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final isLight = theme.brightness == Brightness.light;

    // 仅监听 controller 的本地变化来切换清除按钮可见性，
    // 保证按键当下即可点击清除，不必等待 300ms 防抖结束。
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: TextStyle(
            fontSize: 13.5,
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
            // 默认 prefixIcon 受 48dp 最小交互尺寸约束，会让整个输入框
            // 无法低于 48dp；这里收紧到 38dp，使搜索框更紧凑利落。
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 15),
                    onPressed: clear,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    visualDensity: VisualDensity.compact,
                    splashRadius: 16,
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 7,
              horizontal: 10,
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isLight ? 0.62 : 0.55,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: appColors.glassBorder, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
                width: 1.1,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (val) {
            _debounce?.cancel();
            _debounce = Timer(widget.debounceDuration, () {
              if (mounted) {
                widget.onQueryChanged(val);
              }
            });
          },
          // 点输入框外任意操作时立即结束输入态，避免菜单或页面返回后复唤输入法。
          onTapOutside: (_) => _focusNode.unfocus(),
        );
      },
    );
  }
}

/// 搜索无匹配结果时的通用空状态视图，支持一键清空搜索与可选扩展操作。
class SongSearchEmptyState extends StatelessWidget {
  final String message;
  final VoidCallback onClearSearch;
  final VoidCallback? onSecondaryAction;
  final String? secondaryLabel;
  final IconData? secondaryIcon;

  const SongSearchEmptyState({
    super.key,
    required this.message,
    required this.onClearSearch,
    this.onSecondaryAction,
    this.secondaryLabel,
    this.secondaryIcon,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.search_off_rounded,
      title: message,
      actions: [
        OutlinedButton.icon(
          onPressed: onClearSearch,
          icon: const Icon(Icons.clear_rounded, size: 17),
          label: const Text('清空搜索'),
        ),
        if (onSecondaryAction != null && secondaryLabel != null)
          FilledButton.icon(
            onPressed: onSecondaryAction,
            icon: Icon(
              secondaryIcon ?? Icons.cloud_download_rounded,
              size: 18,
            ),
            label: Text(secondaryLabel!),
          ),
      ],
    );
  }
}
