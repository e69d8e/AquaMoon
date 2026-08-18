import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/app_toast.dart';
import '../../models/song.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/file_export_service.dart';
import 'online_candidate_dialog.dart';
import 'song_artwork.dart';

class EditSongDialog extends ConsumerStatefulWidget {
  final Song song;

  const EditSongDialog({super.key, required this.song});

  static Future<void> show(BuildContext context, Song song) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditSongDialog(song: song),
    );
  }

  @override
  ConsumerState<EditSongDialog> createState() => _EditSongDialogState();
}

class _EditSongDialogState extends ConsumerState<EditSongDialog> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _yearController;
  late TextEditingController _lrcController;

  String? _customAlbumArtUri;
  bool _isEditingLyrics = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist);
    _albumController = TextEditingController(text: widget.song.album);
    _yearController = TextEditingController(text: widget.song.year?.toString() ?? '');
    _lrcController = TextEditingController(text: widget.song.lrcContent ?? '');
    _customAlbumArtUri = widget.song.albumArtUri;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _lrcController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalCoverImage() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(type: FileType.image);
      if (pickedFiles.isNotEmpty) {
        final path = pickedFiles.first.path;
        if (path != null) {
          setState(() {
            _customAlbumArtUri = File(path).uri.toString();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _searchOnlineCandidates() async {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();

    final selected = await OnlineCandidateSelectDialog.show(
      context,
      widget.song,
      initialTitle: title.isNotEmpty ? title : null,
      initialArtist: artist.isNotEmpty ? artist : null,
    );

    if (selected != null && mounted) {
      final onlineService = ref.read(onlineMetadataServiceProvider);
      String? cachedCoverUri = _customAlbumArtUri;
      if (selected.coverUrl != null && selected.coverUrl!.isNotEmpty) {
        cachedCoverUri = await onlineService.cacheOnlineImage(selected.coverUrl!);
      }

      setState(() {
        _titleController.text = selected.title;
        _artistController.text = selected.artist;
        if (selected.album.isNotEmpty) {
          _albumController.text = selected.album;
        }
        if (selected.syncedLyrics != null || selected.plainLyrics != null) {
          _lrcController.text = selected.syncedLyrics ?? selected.plainLyrics!;
          _isEditingLyrics = true;
        }
        _customAlbumArtUri = cachedCoverUri;
      });

      if (mounted) {
        AppToast.show(
          context,
          '已应用来自 ${selected.source} 的《${selected.title}》元数据与歌词！',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    }
  }

  Future<void> _saveCover() async {
    final uri = _customAlbumArtUri ?? widget.song.albumArtUri;
    if (uri == null || uri.isEmpty) {
      AppToast.show(context, '暂无可保存的封面', icon: Icons.image_not_supported_rounded);
      return;
    }
    AppToast.show(context, '正在保存封面...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveCoverImage(
      coverUrlOrPath: uri,
      title: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : widget.song.title,
      artist: _artistController.text.trim(),
    );
    if (mounted) {
      AppToast.show(
        context,
        res.success ? '封面已成功保存至 SoundCraft 文件夹！' : res.message,
        icon: res.success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _exportLyrics() async {
    final content = _lrcController.text.trim();
    if (content.isEmpty) {
      AppToast.show(context, '暂无歌词内容可导出', icon: Icons.lyrics_outlined);
      return;
    }
    AppToast.show(context, '正在导出 LRC 歌词文件...', icon: Icons.downloading_rounded);
    final res = await FileExportService.saveLyricFile(
      lyricContent: content,
      title: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : widget.song.title,
      artist: _artistController.text.trim(),
    );
    if (mounted) {
      AppToast.show(
        context,
        res.success ? '歌词文件已保存至 SoundCraft 文件夹！' : res.message,
        icon: res.success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _copyLyrics() async {
    final content = _lrcController.text.trim();
    if (content.isEmpty) {
      AppToast.show(context, '暂无歌词可复制', icon: Icons.info_outline_rounded);
      return;
    }
    await FileExportService.copyToClipboard(content);
    if (mounted) {
      AppToast.show(context, '歌词已复制到剪贴板！', icon: Icons.copy_rounded);
    }
  }

  void _saveChanges() {
    final updatedSong = widget.song.copyWith(
      title: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : widget.song.title,
      artist: _artistController.text.trim().isNotEmpty ? _artistController.text.trim() : '未知歌手',
      album: _albumController.text.trim().isNotEmpty ? _albumController.text.trim() : '未知专辑',
      year: int.tryParse(_yearController.text.trim()),
      albumArtUri: _customAlbumArtUri,
      lrcContent: _lrcController.text.trim().isNotEmpty ? _lrcController.text.trim() : null,
    );

    // Save to Hive
    ref.read(libraryNotifierProvider.notifier).updateSong(updatedSong);

    // If currently playing, sync with AudioHandler & LyricsProvider
    final currentSong = ref.read(currentSongProvider).valueOrNull;
    if (currentSong != null && currentSong.id == updatedSong.id) {
      ref.read(audioHandlerProvider).updateCurrentSongMetadata(
            title: updatedSong.title,
            artist: updatedSong.artist,
            album: updatedSong.album,
            albumArtUri: updatedSong.albumArtUri,
            lrcContent: updatedSong.lrcContent,
          );
      ref.read(lyricsNotifierProvider.notifier).loadLyricsForSong(updatedSong);
    }

    Navigator.of(context).pop();
    AppToast.show(
      context,
      '歌曲信息修改成功！',
      icon: Icons.check_circle_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final previewSong = widget.song.copyWith(
      albumArtUri: _customAlbumArtUri,
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('编辑歌曲信息与歌词', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Artwork & Action Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SongArtwork(song: previewSong, size: 76, borderRadius: 10),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickLocalCoverImage,
                          icon: const Icon(Icons.image_outlined, size: 15),
                          label: const Text('选择本地封面', style: TextStyle(fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _searchOnlineCandidates,
                          icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                          label: const Text('联网检索元数据', style: TextStyle(fontSize: 11.5)),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (_customAlbumArtUri != null || widget.song.albumArtUri != null)
                          OutlinedButton.icon(
                            onPressed: _saveCover,
                            icon: const Icon(Icons.download_rounded, size: 15),
                            label: const Text('保存此封面', style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Title input
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '歌曲名称 (Title)',
                  prefixIcon: Icon(Icons.music_note_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Artist input
              TextField(
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: '歌手 / 艺术家 (Artist)',
                  prefixIcon: Icon(Icons.person_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Album input
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _albumController,
                      decoration: const InputDecoration(
                        labelText: '专辑 (Album)',
                        prefixIcon: Icon(Icons.album_rounded, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '年份 (Year)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Lyrics Management Expander
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isEditingLyrics = !_isEditingLyrics;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Icon(
                            _isEditingLyrics ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '歌词编辑与管理 (${_lrcController.text.trim().isNotEmpty ? "已有歌词" : "暂无歌词"})',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_lrcController.text.trim().isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: '复制歌词',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copyLyrics,
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      tooltip: '导出 LRC 歌词文件',
                      visualDensity: VisualDensity.compact,
                      onPressed: _exportLyrics,
                    ),
                  ],
                ],
              ),

              if (_isEditingLyrics) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _lrcController,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: '可在此粘贴或编辑 LRC 时间轴歌词 (例如 [00:12.30]歌词内容)...',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saveChanges,
          child: const Text('保存修改'),
        ),
      ],
    );
  }
}
