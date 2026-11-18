import 'dart:async';

import 'package:flutter/material.dart';

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
    // 仅监听 controller 的本地变化来切换清除按钮可见性，
    // 保证按键当下即可点击清除，不必等待 300ms 防抖结束。
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            // 默认 prefixIcon 受 48dp 最小交互尺寸约束，会让整个输入框
            // 无法低于 48dp；这里收紧到 40dp，使搜索框更紧凑。
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
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
              vertical: 5,
              horizontal: 10,
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
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

/// 搜索无匹配结果时的通用空状态卡片，支持一键清空搜索与可选扩展操作。
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
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
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
            ),
          ],
        ),
      ),
    );
  }
}
