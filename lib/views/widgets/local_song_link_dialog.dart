import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/song_matcher.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/qq_music_provider.dart';
import 'song_artwork.dart';

/// 手动把一首 QQ 音乐云端曲目关联到本地音频文件。
///
/// 自动匹配依赖标题/歌手/时长，本地标签缺失或写法差异过大时会匹配不上
/// （表现为收藏页出现无法播放的在线副本）。这里让用户自己挑对应文件，
/// 关联结果优先级高于自动匹配，且重新同步不会丢失。
class LocalSongLinkDialog extends ConsumerStatefulWidget {
  /// 待关联的云端曲目（来自收藏页的在线副本）。
  final Song remote;

  const LocalSongLinkDialog({super.key, required this.remote});

  static Future<String?> show(BuildContext context, Song remote) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => LocalSongLinkDialog(remote: remote),
    );
  }

  @override
  ConsumerState<LocalSongLinkDialog> createState() =>
      _LocalSongLinkDialogState();
}

class _LocalSongLinkDialogState extends ConsumerState<LocalSongLinkDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 本地候选按匹配可信度排序：能匹配的排前面，其余按标题相似度兜底。
  List<({Song song, ({int tier, int duration})? score})> _rankedCandidates(
    List<Song> localSongs,
  ) {
    final query = SongMatcher.compact(_query);

    final entries = <({Song song, ({int tier, int duration})? score})>[];
    for (final local in localSongs) {
      if (!local.hasLocalFile) continue;
      if (query.isNotEmpty) {
        final haystack =
            '${SongMatcher.compact(local.title)}${SongMatcher.compact(local.artist)}';
        if (!haystack.contains(query)) continue;
      }
      entries.add((song: local, score: SongMatcher.scorePair(widget.remote, local)));
    }

    entries.sort((a, b) {
      final sa = a.score;
      final sb = b.score;
      // 可匹配的（score != null）整体排在不可匹配之前
      if (sa != null && sb == null) return -1;
      if (sa == null && sb != null) return 1;
      if (sa != null && sb != null) {
        if (sa.tier != sb.tier) return sa.tier.compareTo(sb.tier);
        if (sa.duration != sb.duration) return sb.duration.compareTo(sa.duration);
      }
      return a.song.title.compareTo(b.song.title);
    });
    return entries;
  }

  Future<void> _confirm(Song local) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final message = await ref
          .read(qqMusicFavoritesProvider.notifier)
          .linkLocalSong(remote: widget.remote, local: local);
      if (!mounted) return;
      Navigator.of(context).pop(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.show(context, '关联失败，请重试', icon: Icons.error_outline_rounded);
    }
  }

  String _matchLabel(({int tier, int duration})? score) {
    if (score == null) return '未匹配';
    switch (score.tier) {
      case 0:
        return score.duration >= 3 ? '高度匹配' : '标题歌手匹配';
      case 1:
        return '标题匹配（本地缺歌手）';
      default:
        return '疑似同一首';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localSongs = ref.watch(
      libraryNotifierProvider.select((s) => s.songs),
    );
    final candidates = _rankedCandidates(localSongs);
    final matchedCount = candidates.where((c) => c.score != null).length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.link_rounded, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('关联本地音频', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 云端曲目信息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  SongArtwork(song: widget.remote, size: 40, borderRadius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.remote.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.remote.artist}'
                          '${widget.remote.durationMs > 0 ? ' · ${Formatters.formatDuration(Duration(milliseconds: widget.remote.durationMs))}' : ''}',
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
            const SizedBox(height: 10),
            Text(
              matchedCount > 0
                  ? '从本地曲库中选择与这首歌对应的音频文件（已按匹配度排序）'
                  : '没有自动匹配到本地音频，可搜索后手动选择对应文件',
              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              enabled: !_isSubmitting,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索本地曲库（标题或歌手）',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    localSongs.isEmpty ? '本地曲库为空，请先扫描或导入音频' : '没有符合条件的本地音频',
                    style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final entry = candidates[index];
                    final song = entry.song;
                    final label = _matchLabel(entry.score);
                    final isMatched = entry.score != null;
                    final isLinked = song.qqSongMid != null &&
                        song.qqSongMid!.isNotEmpty &&
                        song.qqSongMid == widget.remote.qqSongMid;

                    return ListTile(
                      dense: true,
                      enabled: !_isSubmitting,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: SongArtwork(song: song, size: 40, borderRadius: 8),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (isLinked) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle_rounded, size: 14, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${song.artist}'
                            '${song.durationMs > 0 ? ' · ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isMatched
                                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isMatched
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded, size: 20),
                      onTap: () => _confirm(song),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
