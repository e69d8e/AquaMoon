import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/file_export_service.dart';
import '../../services/online_metadata_service.dart';

class OnlineSearchPage extends ConsumerStatefulWidget {
  final String? initialQuery;

  const OnlineSearchPage({super.key, this.initialQuery});

  @override
  ConsumerState<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends ConsumerState<OnlineSearchPage> {
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();

  String _selectedPlatform = '全部';
  final List<String> _platforms = [
    '全部',
    'QQ音乐',
    '网易云音乐',
    'Apple Music',
    'LRCLIB',
  ];

  bool _isLoading = false;
  List<OnlineSearchResult> _results = [];
  String? _errorMessage;
  bool _hasSearched = false;

  final List<String> _quickTags = [
    '周杰伦',
    '陈奕迅',
    '林俊杰',
    '王菲',
    'Taylor Swift',
    '纯音乐',
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      AppToast.show(context, '请输入搜索关键词', icon: Icons.info_outline_rounded);
      return;
    }

    _focusNode.unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final service = ref.read(onlineMetadataServiceProvider);
      final list = await service.searchOnlineSongs(
        query: query,
        platformFilter: _selectedPlatform,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _results = list;
          if (list.isEmpty) {
            _errorMessage = '未找到相关在线歌曲与歌词，建议更换关键词或切换检索平台重试';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '检索失败，请检查网络连接后重试';
        });
      }
    }
  }

  Color _getSourceColor(String source) {
    switch (source) {
      case 'QQ音乐':
        return const Color(0xFF07C160);
      case '网易云音乐':
        return const Color(0xFFE60026);
      case 'Apple Music':
        return const Color(0xFF007AFF);
      case 'LRCLIB':
        return const Color(0xFF8A2BE2);
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _downloadCover(OnlineSearchResult item) async {
    if (item.coverUrl == null || item.coverUrl!.isEmpty) {
      AppToast.show(
        context,
        '该歌曲暂无在线封面图片',
        icon: Icons.image_not_supported_rounded,
      );
      return;
    }

    AppToast.show(context, '正在下载高清封面...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveCoverImage(
      coverUrlOrPath: item.coverUrl!,
      title: item.title,
      artist: item.artist,
    );

    if (mounted) {
      AppToast.show(
        context,
        res.success ? '封面已下载保存到 AquaMoon 文件夹！' : res.message,
        icon: res.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _downloadLyrics(OnlineSearchResult item) async {
    final service = ref.read(onlineMetadataServiceProvider);
    OnlineSearchResult target = item;

    if (!target.hasLyrics && target.extraId != null) {
      AppToast.show(context, '正在解析完整歌词...', icon: Icons.sync_rounded);
      try {
        target = await service.ensureLyricsLoaded(item);
      } catch (_) {
        if (mounted) {
          AppToast.show(
            context,
            '歌词获取失败，请检查网络后重试',
            icon: Icons.error_outline_rounded,
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final lyricContent = target.syncedLyrics ?? target.plainLyrics;
    if (lyricContent == null || lyricContent.trim().isEmpty) {
      AppToast.show(context, '该歌曲未收录有效歌词', icon: Icons.lyrics_outlined);
      return;
    }

    AppToast.show(context, '正在导出 LRC 歌词文件...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveLyricFile(
      lyricContent: lyricContent,
      title: target.title,
      artist: target.artist,
    );

    if (mounted) {
      AppToast.show(
        context,
        res.success ? 'LRC 歌词文件已保存到 AquaMoon 文件夹！' : res.message,
        icon: res.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _copyLyrics(OnlineSearchResult item) async {
    final service = ref.read(onlineMetadataServiceProvider);
    OnlineSearchResult target = item;

    if (!target.hasLyrics && target.extraId != null) {
      AppToast.show(context, '正在获取完整歌词...', icon: Icons.sync_rounded);
      try {
        target = await service.ensureLyricsLoaded(item);
      } catch (_) {
        if (mounted) {
          AppToast.show(
            context,
            '歌词获取失败，请检查网络后重试',
            icon: Icons.error_outline_rounded,
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final lyricContent = target.syncedLyrics ?? target.plainLyrics;
    if (lyricContent == null || lyricContent.trim().isEmpty) {
      if (mounted) {
        AppToast.show(context, '暂无歌词可复制', icon: Icons.info_outline_rounded);
      }
      return;
    }

    await FileExportService.copyToClipboard(lyricContent);
    if (mounted) {
      AppToast.show(context, '歌词已复制到剪贴板！', icon: Icons.copy_rounded);
    }
  }

  void _showResourceDetails(OnlineSearchResult item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ResourceDetailSheet(
        initialItem: item,
        onDownloadCover: () => _downloadCover(item),
        onDownloadLyrics: () => _downloadLyrics(item),
        onCopyLyrics: () => _copyLyrics(item),
        onApplyToLocalSong: (song, enriched) =>
            _applyMetadataToLocalSong(song, enriched),
      ),
    );
  }

  Future<void> _applyMetadataToLocalSong(
    Song localSong,
    OnlineSearchResult onlineData,
  ) async {
    // Hoist provider access above the awaits: the page can be popped while
    // the cover downloads, and riverpod throws on ref use after dispose.
    final library = ref.read(libraryNotifierProvider.notifier);
    final onlineService = ref.read(onlineMetadataServiceProvider);
    String? newArtUri = localSong.albumArtUri;
    if (onlineData.coverUrl != null && onlineData.coverUrl!.isNotEmpty) {
      newArtUri = await onlineService.cacheOnlineImage(onlineData.coverUrl!);
    }
    final newLrc = onlineData.syncedLyrics ?? onlineData.plainLyrics;

    final applied = await library.updateSongMerged(localSong.id, (current) {
      return current.copyWith(
        title: onlineData.title,
        artist: onlineData.artist,
        album: onlineData.album.isNotEmpty ? onlineData.album : current.album,
        albumArtUri: newArtUri,
        lrcContent: newLrc,
      );
    });
    if (applied == null) return;
    final updated = applied;

    final currentSong = ref.read(currentSongProvider).valueOrNull;
    if (currentSong != null && currentSong.id == updated.id) {
      ref
          .read(audioHandlerProvider)
          .updateCurrentSongMetadata(
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtUri: updated.albumArtUri,
            lrcContent: updated.lrcContent,
          );
      ref.read(lyricsNotifierProvider.notifier).loadLyricsForSong(updated);
    }

    if (mounted) {
      AppToast.show(
        context,
        '已将来自 ${onlineData.source} 的《${onlineData.title}》封面与歌词关联至本地曲库！',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(title: const Text('全网在线歌曲与歌词检索'), elevation: 0),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                Expanded(
                  // Listen to the controller locally so keystrokes only rebuild
                  // the field (suffix icon visibility), not the whole page.
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      return TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        style: const TextStyle(fontSize: 14.5),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索在线歌曲、歌手、专辑...',
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                          prefixIcon: const Icon(
                            Icons.saved_search_rounded,
                            size: 22,
                          ),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                            horizontal: 12,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _performSearch,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search_rounded, size: 18),
                  label: const Text('检索'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Platform Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: _platforms.map((p) {
                final isSelected = _selectedPlatform == p;
                final sourceColor = _getSourceColor(p);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(p),
                    selected: isSelected,
                    showCheckmark: false,
                    avatar: p != '全部'
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: sourceColor,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? (isLight ? theme.colorScheme.primary : Colors.white)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    selectedColor: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                      ),
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedPlatform = p;
                        });
                        if (_searchController.text.trim().isNotEmpty) {
                          _performSearch();
                        }
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 0.5),

          // Search Content Area
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在连接各大音乐平台检索歌曲、高清封面与 LRC 歌词...'),
                      ],
                    ),
                  )
                : _results.isNotEmpty
                ? _buildResultsList()
                : _hasSearched
                ? _buildEmptyOrErrorState()
                : _buildInitialGuideState(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text(
                '检索结果 · ${_results.length} 项',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '点击卡片可查看大图与歌词，或直接点击右侧下载',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
            itemCount: _results.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _results[index];
              final sourceColor = _getSourceColor(item.source);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                color: theme.colorScheme.surface,
                child: InkWell(
                  onTap: () => _showResourceDetails(item),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        // Cover Art Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child:
                              item.coverUrl != null && item.coverUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: item.coverUrl!,
                                  width: 54,
                                  height: 54,
                                  memCacheWidth: 160,
                                  memCacheHeight: 160,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, error, stackTrace) =>
                                      Container(
                                        width: 54,
                                        height: 54,
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        child: const Icon(
                                          Icons.album_rounded,
                                          size: 28,
                                        ),
                                      ),
                                )
                              : Container(
                                  width: 54,
                                  height: 54,
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    size: 28,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Source Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sourceColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: sourceColor.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      item.source,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: sourceColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.artist}${item.album.isNotEmpty ? " · ${item.album}" : ""}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (item.durationMs > 0) ...[
                                    Text(
                                      Formatters.formatDuration(item.duration),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (item.hasLyrics)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        '含歌词',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: Colors.purple,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (item.coverUrl != null) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        '高清封面',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Action Buttons (Download Cover & Download Lyrics)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.image_outlined, size: 20),
                              tooltip: '下载封面图片',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _downloadCover(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.lyrics_outlined, size: 20),
                              tooltip: '下载歌词文件 (.lrc)',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _downloadLyrics(item),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                size: 20,
                              ),
                              tooltip: '更多详情与操作',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _showResourceDetails(item),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyOrErrorState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 60,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? '未找到匹配的在线结果',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('切换为全部平台'),
                  onPressed: () {
                    setState(() {
                      _selectedPlatform = '全部';
                    });
                    _performSearch();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialGuideState() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_download_rounded,
                  color: theme.colorScheme.primary,
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '多源音乐与歌词下载中心',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '检索 QQ 音乐、网易云、Apple Music 与 LRCLIB，一键下载保存高清封面图片与标准 LRC 歌词文件，或关联至本地歌曲。',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '快捷热门检索',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickTags.map((tag) {
              return ActionChip(
                label: Text(tag),
                avatar: const Icon(Icons.trending_up_rounded, size: 14),
                onPressed: () {
                  _searchController.text = tag;
                  _performSearch();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ResourceDetailSheet extends ConsumerStatefulWidget {
  final OnlineSearchResult initialItem;
  final VoidCallback onDownloadCover;
  final VoidCallback onDownloadLyrics;
  final VoidCallback onCopyLyrics;
  final Function(Song localSong, OnlineSearchResult onlineData)
  onApplyToLocalSong;

  const _ResourceDetailSheet({
    required this.initialItem,
    required this.onDownloadCover,
    required this.onDownloadLyrics,
    required this.onCopyLyrics,
    required this.onApplyToLocalSong,
  });

  @override
  ConsumerState<_ResourceDetailSheet> createState() =>
      _ResourceDetailSheetState();
}

class _ResourceDetailSheetState extends ConsumerState<_ResourceDetailSheet> {
  late OnlineSearchResult _item;
  bool _isLoadingLyrics = false;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    _fetchLyricsIfNeeded();
  }

  Future<void> _fetchLyricsIfNeeded() async {
    if (!_item.hasLyrics && _item.extraId != null) {
      setState(() {
        _isLoadingLyrics = true;
      });
      final service = ref.read(onlineMetadataServiceProvider);
      try {
        final enriched = await service.ensureLyricsLoaded(_item);
        if (mounted) {
          setState(() {
            _item = enriched;
          });
        }
      } catch (_) {
        if (mounted) {
          AppToast.show(
            context,
            '歌词获取失败，请检查网络后重试',
            icon: Icons.error_outline_rounded,
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingLyrics = false;
          });
        }
      }
    }
  }

  void _showLocalSongPicker() {
    final songs = ref.read(libraryNotifierProvider).songs;
    if (songs.isEmpty) {
      AppToast.show(context, '本地曲库为空，暂无法关联', icon: Icons.info_outline_rounded);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = songs.where((s) {
              if (filter.isEmpty) return true;
              return s.title.toLowerCase().contains(filter.toLowerCase()) ||
                  s.artist.toLowerCase().contains(filter.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text(
                '选择要关联的本地歌曲',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 480,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: '搜索本地歌曲...',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          filter = val.trim();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('无匹配本地歌曲'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, idx) {
                                final s = filtered[idx];
                                return ListTile(
                                  title: Text(
                                    s.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    s.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.link_rounded),
                                  onTap: () {
                                    Navigator.of(dialogCtx).pop();
                                    Navigator.of(context).pop(); // close sheet
                                    widget.onApplyToLocalSong(s, _item);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final lyricText = _item.syncedLyrics ?? _item.plainLyrics;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _item.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_item.artist} · ${_item.album.isNotEmpty ? _item.album : "未知专辑"} (${_item.source})',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Action Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _item.coverUrl != null
                      ? widget.onDownloadCover
                      : null,
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('下载封面图片'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: lyricText != null ? widget.onDownloadLyrics : null,
                  icon: const Icon(Icons.lyrics_outlined, size: 16),
                  label: const Text('下载 LRC 歌词'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: lyricText != null ? widget.onCopyLyrics : null,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('复制歌词'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showLocalSongPicker,
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('关联至本地歌曲'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content Tabs (Cover & Lyrics Preview)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // High-Res Cover Preview
                  if (_item.coverUrl != null && _item.coverUrl!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: _item.coverUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          memCacheHeight: 600,
                        ),
                      ),
                    ),

                  // Lyrics Text Preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lyrics_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '歌词内容试看',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_isLoadingLyrics)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (lyricText != null &&
                            lyricText.trim().isNotEmpty)
                          SelectableText(
                            lyricText,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.8,
                              color: isLight ? Colors.black87 : Colors.white70,
                              fontFamily: 'monospace',
                            ),
                          )
                        else
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text('该平台此音轨暂未收录歌词'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
