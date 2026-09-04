import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/app_toast.dart';
import '../../models/song.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/file_export_service.dart';
import '../../services/online_metadata_service.dart';

class OnlineCandidateSelectDialog extends ConsumerStatefulWidget {
  final Song song;
  final String? initialTitle;
  final String? initialArtist;

  const OnlineCandidateSelectDialog({
    super.key,
    required this.song,
    this.initialTitle,
    this.initialArtist,
  });

  /// Static helper to open dialog and return the selected result
  static Future<OnlineSearchResult?> show(
    BuildContext context,
    Song song, {
    String? initialTitle,
    String? initialArtist,
  }) {
    return showDialog<OnlineSearchResult?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => OnlineCandidateSelectDialog(
        song: song,
        initialTitle: initialTitle,
        initialArtist: initialArtist,
      ),
    );
  }

  @override
  ConsumerState<OnlineCandidateSelectDialog> createState() => _OnlineCandidateSelectDialogState();
}

class _OnlineCandidateSelectDialogState extends ConsumerState<OnlineCandidateSelectDialog> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;

  bool _isLoading = false;
  List<OnlineSearchResult> _candidates = [];
  String? _errorMessage;
  int? _expandedLyricIndex;
  bool _isLoadingLyrics = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? widget.song.title);
    _artistController = TextEditingController(
      text: widget.initialArtist ?? (widget.song.artist == '未知歌手' ? '' : widget.song.artist),
    );
    _performSearch();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _errorMessage = '请输入歌曲名称后重试';
        _candidates = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _expandedLyricIndex = null;
    });

    try {
      final service = ref.read(onlineMetadataServiceProvider);
      final results = await service.searchCandidates(
        title: title,
        artist: artist,
        album: widget.song.album,
        duration: widget.song.duration,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _candidates = results;
          if (results.isEmpty) {
            _errorMessage = '未找到匹配的在线数据，您可以微调歌名或歌手名后重试。';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '检索失败: $e';
        });
      }
    }
  }

  Future<void> _toggleLyricPreview(int index, OnlineSearchResult candidate) async {
    if (_expandedLyricIndex == index) {
      setState(() {
        _expandedLyricIndex = null;
      });
      return;
    }

    setState(() {
      _expandedLyricIndex = index;
    });

    if (!candidate.hasLyrics && candidate.extraId != null) {
      setState(() {
        _isLoadingLyrics = true;
      });
      final service = ref.read(onlineMetadataServiceProvider);
      final enriched = await service.ensureLyricsLoaded(candidate);
      if (mounted) {
        setState(() {
          _candidates[index] = enriched;
          _isLoadingLyrics = false;
        });
      }
    }
  }

  Future<void> _applyCandidate(OnlineSearchResult candidate) async {
    final service = ref.read(onlineMetadataServiceProvider);
    setState(() {
      _isLoading = true;
    });

    // Ensure complete lyrics and download cover
    final fullCandidate = await service.ensureLyricsLoaded(candidate);
    if (mounted) {
      Navigator.of(context).pop(fullCandidate);
    }
  }

  Future<void> _downloadCover(OnlineSearchResult candidate) async {
    if (candidate.coverUrl == null || candidate.coverUrl!.isEmpty) {
      AppToast.show(context, '该候选未包含封面地址', icon: Icons.image_not_supported_rounded);
      return;
    }
    AppToast.show(context, '正在保存封面...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveCoverImage(
      coverUrlOrPath: candidate.coverUrl!,
      title: candidate.title,
      artist: candidate.artist,
    );
    if (mounted) {
      AppToast.show(
        context,
        res.success ? '封面已成功保存至 SoundCraft 文件夹！' : res.message,
        icon: res.success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _downloadLyrics(OnlineSearchResult candidate) async {
    final service = ref.read(onlineMetadataServiceProvider);
    OnlineSearchResult target = candidate;
    if (!target.hasLyrics && target.extraId != null) {
      AppToast.show(context, '正在获取歌词...', icon: Icons.sync_rounded);
      target = await service.ensureLyricsLoaded(candidate);
    }

    if (!mounted) return;

    final lyricContent = target.syncedLyrics ?? target.plainLyrics;
    if (lyricContent == null || lyricContent.trim().isEmpty) {
      AppToast.show(context, '该候选未包含有效歌词', icon: Icons.lyrics_outlined);
      return;
    }

    AppToast.show(context, '正在导出歌词...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveLyricFile(
      lyricContent: lyricContent,
      title: target.title,
      artist: target.artist,
    );
    if (mounted) {
      AppToast.show(
        context,
        res.success ? 'LRC 歌词已成功保存至 SoundCraft 文件夹！' : res.message,
        icon: res.success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _copyLyrics(OnlineSearchResult candidate) async {
    final service = ref.read(onlineMetadataServiceProvider);
    OnlineSearchResult target = candidate;
    if (!target.hasLyrics && target.extraId != null) {
      target = await service.ensureLyricsLoaded(candidate);
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 620,
          maxHeight: 740,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.saved_search_rounded, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '在线多源数据检索与校准',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '优先呈现 QQ 音乐与网易云整套数据，支持试看歌词与精准切换',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
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

              const SizedBox(height: 14),

              // Local Reference Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.audiotrack_rounded, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '本地参考：${widget.song.title} · ${widget.song.artist} (时长: ${_formatDuration(widget.song.duration)})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Search Bar
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _titleController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '歌曲名称',
                        isDense: true,
                        prefixIcon: Icon(Icons.music_note_rounded, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _artistController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '歌手名',
                        isDense: true,
                        prefixIcon: Icon(Icons.person_rounded, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _performSearch,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search_rounded, size: 18),
                    label: const Text('检索'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Candidate List or Status
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('正在跨库检索（QQ音乐 / 网易云 / Apple Music）并校验时长...'),
                          ],
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(_errorMessage!, textAlign: TextAlign.center),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _candidates.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _candidates[index];
                              final isExpanded = _expandedLyricIndex == index;
                              final diffSec = item.durationDiffSeconds(widget.song.duration);
                              final sourceColor = _getSourceColor(item.source);

                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: index == 0
                                        ? theme.colorScheme.primary.withValues(alpha: 0.4)
                                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                                    width: index == 0 ? 1.5 : 1,
                                  ),
                                ),
                                color: index == 0
                                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
                                    : theme.colorScheme.surface,
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Cover Art Thumbnail
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: item.coverUrl != null
                                                ? CachedNetworkImage(
                                                    imageUrl: item.coverUrl!,
                                                    width: 52,
                                                    height: 52,
                                                    memCacheWidth: 160,
                                                    memCacheHeight: 160,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (context, error, stackTrace) => Container(
                                                      width: 52,
                                                      height: 52,
                                                      color: theme.colorScheme.surfaceContainerHighest,
                                                      child: const Icon(Icons.album_rounded, size: 26),
                                                    ),
                                                  )
                                                : Container(
                                                    width: 52,
                                                    height: 52,
                                                    color: theme.colorScheme.surfaceContainerHighest,
                                                    child: const Icon(Icons.music_note_rounded, size: 26),
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
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: sourceColor.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: sourceColor.withValues(alpha: 0.4)),
                                                      ),
                                                      child: Text(
                                                        item.source,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: sourceColor,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    if (index == 0) ...[
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          '推荐首选',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: theme.colorScheme.primary,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                    ],
                                                    Expanded(
                                                      child: Text(
                                                        item.title,
                                                        style: const TextStyle(
                                                          fontSize: 14,
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
                                                  '${item.artist}${item.album.isNotEmpty ? " · 《${item.album}》" : ""}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 6),

                                                // Duration comparison & lyric tag
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  children: [
                                                    if (item.durationMs > 0)
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            diffSec <= 3
                                                                ? Icons.check_circle_outline_rounded
                                                                : Icons.schedule_rounded,
                                                            size: 13,
                                                            color: diffSec <= 3 ? Colors.green : Colors.orange,
                                                          ),
                                                          const SizedBox(width: 3),
                                                          Text(
                                                            '${_formatDuration(item.duration)} (偏差 ${diffSec}s)',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w500,
                                                              color: diffSec <= 3 ? Colors.green : Colors.orange,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: item.syncedLyrics != null
                                                            ? Colors.green.withValues(alpha: 0.12)
                                                            : (item.plainLyrics != null
                                                                ? Colors.blue.withValues(alpha: 0.12)
                                                                : theme.colorScheme.surfaceContainerHighest),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: item.syncedLyrics != null
                                                              ? Colors.green.withValues(alpha: 0.4)
                                                              : (item.plainLyrics != null
                                                                  ? Colors.blue.withValues(alpha: 0.4)
                                                                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        item.syncedLyrics != null
                                                            ? 'LRC 滚动歌词'
                                                            : (item.plainLyrics != null ? '纯文本歌词' : '无歌词'),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w500,
                                                          color: item.syncedLyrics != null
                                                              ? Colors.green
                                                              : (item.plainLyrics != null ? Colors.blue : theme.colorScheme.onSurfaceVariant),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(height: 1),
                                      const SizedBox(height: 6),

                                      // Actions Row: Preview Lyrics & Downloads on Left, Apply on Right
                                      Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextButton.icon(
                                                onPressed: () => _toggleLyricPreview(index, item),
                                                icon: Icon(
                                                  isExpanded ? Icons.expand_less_rounded : Icons.lyrics_outlined,
                                                  size: 14,
                                                ),
                                                label: Text(
                                                  isExpanded ? '收起歌词' : '预览歌词',
                                                  style: const TextStyle(fontSize: 11.5),
                                                ),
                                                style: TextButton.styleFrom(
                                                  visualDensity: VisualDensity.compact,
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                              if (item.coverUrl != null)
                                                IconButton(
                                                  icon: const Icon(Icons.image_outlined, size: 16),
                                                  tooltip: '下载此封面',
                                                  visualDensity: VisualDensity.compact,
                                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                  onPressed: () => _downloadCover(item),
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.download_rounded, size: 16),
                                                tooltip: '下载此 LRC 歌词',
                                                visualDensity: VisualDensity.compact,
                                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                onPressed: () => _downloadLyrics(item),
                                              ),
                                            ],
                                          ),
                                          FilledButton.icon(
                                            onPressed: () => _applyCandidate(item),
                                            icon: const Icon(Icons.check_rounded, size: 13),
                                            label: const Text('采用此数据', style: TextStyle(fontSize: 11.5)),
                                            style: FilledButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Expanded Lyrics View
                                      if (isExpanded) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                alignment: WrapAlignment.spaceBetween,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                spacing: 4,
                                                runSpacing: 4,
                                                children: [
                                                  const Text(
                                                    '歌词预览',
                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      TextButton.icon(
                                                        onPressed: () => _copyLyrics(item),
                                                        icon: const Icon(Icons.copy_rounded, size: 12),
                                                        label: const Text('复制歌词', style: TextStyle(fontSize: 11)),
                                                        style: TextButton.styleFrom(
                                                          visualDensity: VisualDensity.compact,
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                        ),
                                                      ),
                                                      TextButton.icon(
                                                        onPressed: () => _downloadLyrics(item),
                                                        icon: const Icon(Icons.download_rounded, size: 12),
                                                        label: const Text('导出LRC', style: TextStyle(fontSize: 11)),
                                                        style: TextButton.styleFrom(
                                                          visualDensity: VisualDensity.compact,
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              _isLoadingLyrics
                                                  ? const Center(
                                                      child: Padding(
                                                        padding: EdgeInsets.all(8.0),
                                                        child: SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child: CircularProgressIndicator(strokeWidth: 2),
                                                        ),
                                                      ),
                                                    )
                                                  : ConstrainedBox(
                                                      constraints: const BoxConstraints(maxHeight: 120),
                                                      child: SingleChildScrollView(
                                                        child: Text(
                                                          item.syncedLyrics ?? item.plainLyrics ?? '（暂未拉取到歌词文本）',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            height: 1.5,
                                                            fontFamily: 'monospace',
                                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
