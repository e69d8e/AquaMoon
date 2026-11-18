import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/qq_music_cookie_status.dart';
import '../../models/qq_music_discovery.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/playback_preferences_provider.dart';
import '../../providers/qq_music_discovery_provider.dart';
import '../../providers/qq_music_download_provider.dart';
import '../../providers/qq_music_provider.dart';
import '../../providers/qq_music_session_provider.dart';
import '../../services/qq_music_discovery_service.dart';
import '../widgets/qq_music_auth_dialog.dart';
import '../widgets/qq_music_quality_picker.dart';
import '../widgets/song_artwork.dart';

/// QQ 音乐在线发现页。
///
/// 协议实现参考 go-music-dl / music-lib（见 docs/qq_music_protocol.md）：
/// 单曲搜索、歌单 / 专辑 / 榜单发现、分享链接解析、七档音质在线取流。
/// 搜索结果直接转成带 `qqSongMid` 的 [Song]，由既有音频引擎解析流地址播放。
class QQMusicDiscoveryPage extends ConsumerStatefulWidget {
  const QQMusicDiscoveryPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<QQMusicDiscoveryPage> createState() =>
      _QQMusicDiscoveryPageState();
}

class _QQMusicDiscoveryPageState extends ConsumerState<QQMusicDiscoveryPage> {
  static const List<String> _quickTags = <String>[
    '周杰伦',
    '陈奕迅',
    '林俊杰',
    '王菲',
    '毛不易',
    '国风',
    '纯音乐',
  ];

  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(qqMusicSessionProvider.notifier).check();
      final query = widget.initialQuery?.trim() ?? '';
      if (query.isNotEmpty) {
        _submit(query);
      } else {
        ref.read(qqMusicDiscoveryProvider.notifier).setTab(
              QQMusicDiscoveryTab.playlists,
            );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 240) {
      return;
    }
    ref.read(qqMusicDiscoveryProvider.notifier).loadMore();
  }

  bool get _hasCookie {
    try {
      return ref.read(storageServiceProvider).getQQMusicConfig().hasCookie;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    final notifier = ref.read(qqMusicDiscoveryProvider.notifier);

    // 单曲分享链接：解析 mid 拿到元数据后立即播放。
    if (QQMusicDiscoveryService.parseSongMid(query) != null) {
      final song = await notifier.resolveSongLink(query);
      if (!mounted) return;
      if (song == null) {
        AppToast.show(context, '无法解析这首歌曲，请检查分享链接');
        return;
      }
      await _play(song, <Song>[song]);
      return;
    }

    // 歌单 / 专辑 / 单曲分享链接由状态机解析，歌单与专辑会展开曲目详情。
    await notifier.search(query);
  }

  Future<void> _play(Song song, List<Song> queue) async {
    // 开启「本地优先」且曲库里有同一首歌时，播放会走本地文件，
    // 此时不必再用 VIP 提示打断用户。
    final playsLocalCopy = _safeHasLocalCopy(song);
    if (song.isVip && !_hasCookie && !playsLocalCopy) {
      AppToast.show(
        context,
        '《${song.title}》为 VIP 曲目，绑定 QQ 音乐 Cookie 后可尝试播放',
        duration: const Duration(milliseconds: 2800),
      );
    }
    await ref.read(audioControllerProvider).playSong(song, queue: queue);
  }

  /// 纯渲染 / 精简 ProviderScope 下缺依赖时不要让播放流程崩掉。
  bool _safeHasLocalCopy(Song song) {
    try {
      return ref.read(hasLocalCopyProvider(song));
    } catch (_) {
      return false;
    }
  }

  /// 行内下载进度：下载中的歌曲在列表里直接显示进度环。
  QQMusicDownloadTask? _downloadTaskFor(Song song) {
    try {
      return ref.watch(qqMusicDownloadProvider).taskFor(song);
    } catch (_) {
      return null;
    }
  }

  /// 选择音质 → 入队下载 → 等待结果并提示保存位置。
  Future<void> _download(Song song) async {
    final hasCookie = _hasCookie;
    final settings = ref.read(qqMusicDownloadSettingsProvider);
    final quality = await showQQMusicQualityPicker(
      context,
      title: '选择下载音质',
      subtitle: '《${song.title}》· 保存到 ${settings.directoryLabel}',
      selected: settings.quality,
      hasCookie: hasCookie,
    );
    if (quality == null || !mounted) return;

    final notifier = ref.read(qqMusicDownloadProvider.notifier);
    AppToast.show(context, '已加入下载队列：${quality.label}');
    final task = await notifier.enqueue(song, quality: quality);
    if (!mounted) return;
    if (task.isCompleted) {
      final note = task.downgradeNote;
      AppToast.show(
        context,
        '《${song.title}》已保存到 ${task.directory ?? settings.directoryLabel}'
        '${note == null ? '' : '（$note）'}',
        icon: Icons.download_done_rounded,
        duration: const Duration(milliseconds: 2800),
      );
    } else if (task.isFailed) {
      AppToast.show(
        context,
        task.message.isEmpty ? '下载失败，请稍后重试' : task.message,
        icon: Icons.error_outline_rounded,
        duration: const Duration(milliseconds: 3000),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(qqMusicDiscoveryProvider);
    final notifier = ref.read(qqMusicDiscoveryProvider.notifier);
    final session = ref.watch(qqMusicSessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QQ 音乐 · 在线发现'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新当前结果',
            onPressed: () => notifier.refresh(),
          ),
          _buildQualityMenu(theme, state.quality, notifier),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: '绑定 QQ 音乐 Cookie（解锁无损音质）',
            onPressed: () => QQMusicAuthDialog.show(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (session.shouldPrompt) _buildCookieBanner(theme, session),
          _buildSearchBar(theme),
          _buildTabBar(theme, state, notifier),
          if (state.tab == QQMusicDiscoveryTab.playlists &&
              state.categories.isNotEmpty)
            _buildCategoryChips(theme, state, notifier),
          const Divider(height: 1, thickness: 0.5),
          Expanded(child: _buildContent(theme, state, notifier)),
        ],
      ),
    );
  }

  /// Cookie 过期 / 即将过期时的顶部提示条。
  Widget _buildCookieBanner(ThemeData theme, QQMusicSessionState session) {
    final expired = session.health == QQMusicCookieHealth.expired;
    final background = expired
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final foreground = expired
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            expired
                ? Icons.error_outline_rounded
                : Icons.schedule_rounded,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              expired
                  ? '${session.summary}，VIP 与无损曲目将无法播放'
                  : '${session.summary}，到期后 VIP 与无损曲目将无法播放',
              style: TextStyle(fontSize: 12.5, color: foreground),
            ),
          ),
          TextButton(
            onPressed: () => QQMusicAuthDialog.show(context),
            style: TextButton.styleFrom(foregroundColor: foreground),
            child: const Text('重新绑定'),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: foreground),
            tooltip: '本次不再提示',
            onPressed: () =>
                ref.read(qqMusicSessionProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: '搜索歌曲 / 歌手 / 歌单 / 专辑，或粘贴分享链接',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  tooltip: '清空',
                  onPressed: _searchController.clear,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 12,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _submit,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _submit(_searchController.text),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: QQMusicDiscoveryTab.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = QQMusicDiscoveryTab.values[index];
          final selected = state.tab == tab;
          return FilterChip(
            label: Text(tab.label),
            selected: selected,
            showCheckmark: false,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            selectedColor: theme.colorScheme.primaryContainer.withValues(
              alpha: 0.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            onSelected: (_) => notifier.setTab(tab),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChips(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        itemCount: state.categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = state.categories[index];
          final selected = (state.selectedCategoryId ?? '') == category.id;
          return ActionChip(
            label: Text(category.name, style: const TextStyle(fontSize: 12)),
            backgroundColor: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            onPressed: () => notifier.selectCategory(
              category.id.isEmpty ? null : category.id,
            ),
          );
        },
      ),
    );
  }

  Widget _buildQualityMenu(
    ThemeData theme,
    QQMusicStreamQuality current,
    QQMusicDiscoveryNotifier notifier,
  ) {
    return PopupMenuButton<QQMusicStreamQuality>(
      icon: const Icon(Icons.high_quality_rounded),
      tooltip: '在线播放音质',
      initialValue: current,
      onSelected: (quality) async {
        await notifier.setQuality(quality);
        if (!mounted) return;
        final hint = quality.requiresCookie && !_hasCookie
            ? ' · 无损档需绑定 QQ 音乐 Cookie'
            : '';
        AppToast.show(context, '已切换为 ${quality.label}$hint');
      },
      itemBuilder: (context) => QQMusicStreamQuality.values.map((quality) {
        return PopupMenuItem<QQMusicStreamQuality>(
          value: quality,
          child: Row(
            children: [
              Icon(
                quality == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: quality == current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(quality.label, style: const TextStyle(fontSize: 13))),
              if (quality.requiresCookie) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    if (state.openedCollection != null) {
      return _buildDetail(theme, state, notifier);
    }
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接 QQ 音乐…'),
          ],
        ),
      );
    }
    if (state.error != null) {
      return _buildMessage(
        theme,
        icon: Icons.cloud_off_rounded,
        title: state.error!,
        actionLabel: '重试',
        onAction: () => notifier.refresh(),
      );
    }
    if (state.tab.isSongs) {
      if (state.songs.isEmpty) {
        return _buildInitialGuide(theme, notifier, state);
      }
      return _buildSongList(theme, state, notifier);
    }
    if (state.collections.isEmpty) {
      return _buildInitialGuide(theme, notifier, state);
    }
    return _buildCollectionGrid(theme, state, notifier);
  }

  Widget _buildMessage(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInitialGuide(
    ThemeData theme,
    QQMusicDiscoveryNotifier notifier,
    QQMusicDiscoveryState state,
  ) {
    final isSongs = state.tab.isSongs;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Icon(
          state.tab == QQMusicDiscoveryTab.charts
              ? Icons.leaderboard_rounded
              : Icons.graphic_eq_rounded,
          size: 46,
          color: theme.colorScheme.primary.withValues(alpha: 0.75),
        ),
        const SizedBox(height: 16),
        Text(
          isSongs ? '搜一首想听的歌' : '发现 QQ 音乐好歌',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          '支持单曲搜索、歌单 / 专辑 / 榜单浏览与分享链接解析；'
          '点击结果即点即播，VIP 与无损音质需绑定 QQ 音乐 Cookie。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: _quickTags.map((tag) {
            return ActionChip(
              label: Text(tag, style: const TextStyle(fontSize: 12.5)),
              onPressed: () {
                _searchController.text = tag;
                notifier.setTab(QQMusicDiscoveryTab.songs).then(
                      (_) => notifier.search(tag),
                    );
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link_rounded,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      '粘贴分享链接',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '把 QQ 音乐的歌单、专辑或单曲链接粘进搜索框：'
                  '歌单 / 专辑会展开曲目列表，单曲会直接开始播放。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSongList(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text(
                '搜索结果 · ${state.songs.length} 首',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _play(state.songs.first, state.songs),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('播放全部'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
            itemCount: state.songs.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 2),
            itemBuilder: (context, index) {
              if (index == state.songs.length) {
                return _buildLoadMore(theme, state, notifier);
              }
              return _buildSongRow(
                theme,
                state.songs[index],
                state.songs,
                index,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMore(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            '没有更多结果了',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: TextButton(
          onPressed: () => notifier.loadMore(),
          child: const Text('加载更多'),
        ),
      ),
    );
  }

  Widget _buildSongRow(
    ThemeData theme,
    Song song,
    List<Song> queue,
    int index,
  ) {
    final downloadTask = _downloadTaskFor(song);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _play(song, queue),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SongArtwork(song: song, size: 44, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist.isEmpty
                          ? song.album
                          : (song.album.isEmpty
                              ? song.artist
                              : '${song.artist} · ${song.album}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (song.isVip) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'VIP',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
              if (downloadTask != null && downloadTask.isActive) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: downloadTask.progress,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  downloadTask.progress == null
                      ? '下载中'
                      : '${(downloadTask.progress! * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ] else ...[
                const SizedBox(width: 8),
                Text(
                  Formatters.formatDuration(song.duration),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
              ],
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                tooltip: '更多操作',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: () => _showSongActions(song, queue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSongActions(Song song, List<Song> queue) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('立即播放'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _play(song, queue);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('下一首播放'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref.read(audioControllerProvider).playNext(song);
                if (!mounted) return;
                AppToast.show(context, '已加入下一首播放：《${song.title}》');
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded),
              title: const Text('收藏到「我喜欢」'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _favorite(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载到本地'),
              subtitle: const Text('自选音质，保存到下载文件夹'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _download(song);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _favorite(Song song) async {
    final favorites = ref.read(qqMusicFavoritesProvider.notifier);
    final isBound = ref.read(qqMusicFavoritesProvider).config.isBound;
    if (!isBound) {
      AppToast.show(
        context,
        '请先在设置中绑定 QQ 音乐账号，再收藏在线歌曲',
        duration: const Duration(milliseconds: 2800),
      );
      return;
    }
    final result = await favorites.toggleFavorite(song);
    if (!mounted || result.toastMessage == null) return;
    AppToast.show(
      context,
      result.toastMessage!,
      icon: result.isFavorite
          ? Icons.favorite_rounded
          : Icons.favorite_border_rounded,
    );
  }

  Widget _buildCollectionGrid(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.76,
      ),
      itemCount: state.collections.length,
      itemBuilder: (context, index) {
        return _buildCollectionCard(
          theme,
          state.collections[index],
          notifier,
        );
      },
    );
  }

  Widget _buildCollectionCard(
    ThemeData theme,
    QQMusicCollection collection,
    QQMusicDiscoveryNotifier notifier,
  ) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () => notifier.openCollection(collection),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(theme, collection),
                  if (collection.badge != null &&
                      collection.badge!.isNotEmpty)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.86,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          collection.badge!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    collection.subtitle.isEmpty
                        ? _kindLabel(collection.kind)
                        : collection.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(ThemeData theme, QQMusicCollection collection) {
    final url = collection.coverUrl;
    if (url == null || url.isEmpty) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          _kindIcon(collection.kind),
          size: 38,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 320,
      memCacheHeight: 320,
      placeholder: (context, url) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (context, url, error) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          _kindIcon(collection.kind),
          size: 38,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  String _kindLabel(QQMusicCollectionKind kind) {
    switch (kind) {
      case QQMusicCollectionKind.playlist:
        return '歌单';
      case QQMusicCollectionKind.album:
        return '专辑';
      case QQMusicCollectionKind.chart:
        return '排行榜';
    }
  }

  IconData _kindIcon(QQMusicCollectionKind kind) {
    switch (kind) {
      case QQMusicCollectionKind.playlist:
        return Icons.queue_music_rounded;
      case QQMusicCollectionKind.album:
        return Icons.album_rounded;
      case QQMusicCollectionKind.chart:
        return Icons.leaderboard_rounded;
    }
  }

  Widget _buildDetail(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
  ) {
    final collection = state.openedCollection!;
    final detail = state.detail;
    final songs = detail?.songs ?? const <Song>[];
    final detailSubtitle = detail?.collection.subtitle ?? '';
    final subtitle = detailSubtitle.isNotEmpty
        ? detailSubtitle
        : (collection.subtitle.isNotEmpty
            ? collection.subtitle
            : _kindLabel(collection.kind));
    final description = detail?.collection.description ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _buildCover(theme, detail?.collection ?? collection),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail?.collection.title ?? collection.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (songs.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '共 ${songs.length} 首 · 点击即点即播',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: '返回',
                onPressed: () => notifier.closeDetail(),
              ),
            ],
          ),
        ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (songs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: FilledButton.tonalIcon(
              onPressed: () => _play(songs.first, songs),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('播放全部'),
            ),
          ),
        const Divider(height: 1, thickness: 0.5),
        Expanded(
          child: _buildDetailBody(theme, state, notifier, songs),
        ),
      ],
    );
  }

  Widget _buildDetailBody(
    ThemeData theme,
    QQMusicDiscoveryState state,
    QQMusicDiscoveryNotifier notifier,
    List<Song> songs,
  ) {
    if (state.isDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.detailError != null) {
      return _buildMessage(
        theme,
        icon: Icons.error_outline_rounded,
        title: state.detailError!,
        actionLabel: '重试',
        onAction: () => notifier.refresh(),
      );
    }
    if (songs.isEmpty) {
      return _buildMessage(
        theme,
        icon: Icons.music_off_rounded,
        title: '暂无曲目',
        actionLabel: '刷新',
        onAction: () => notifier.refresh(),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 40),
      itemCount: songs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, index) =>
          _buildSongRow(theme, songs[index], songs, index),
    );
  }
}
