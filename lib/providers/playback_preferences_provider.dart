import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/song_matcher.dart';
import '../models/song.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

/// 「在线曲目优先播放本地文件」开关。
///
/// 音频引擎在播放任何非本地文件（QQ 音乐在线曲目、其它在线流）之前会读取
/// [StorageService.getPreferLocalPlayback]；本 Provider 只负责设置页的开关状态
/// 与落盘，两者共用同一个 settings 键，避免出现「开关打开了但播放没生效」。
class PreferLocalPlaybackNotifier extends StateNotifier<bool> {
  PreferLocalPlaybackNotifier(this._storageService)
      : super(_storageService.getPreferLocalPlayback());

  final StorageService _storageService;

  Future<void> setPreferLocalPlayback(bool enabled) async {
    if (state == enabled) return;
    state = enabled;
    await _storageService.savePreferLocalPlayback(enabled);
  }
}

final preferLocalPlaybackProvider =
    StateNotifierProvider<PreferLocalPlaybackNotifier, bool>((ref) {
  return PreferLocalPlaybackNotifier(ref.watch(storageServiceProvider));
});

/// 播放 [song] 时是否真的会改用本地副本。
///
/// 与音频引擎同一套判定（开关打开 + 曲库里存在可播放的同名匹配），供界面
/// 决定「先提示 VIP 受限」还是「直接安静地播本地」。
final hasLocalCopyProvider = Provider.family<bool, Song>((ref, song) {
  if (!ref.watch(preferLocalPlaybackProvider)) return false;
  if (song.hasLocalFile) return false;
  final localSongs = ref.watch(
    libraryNotifierProvider.select((state) => state.songs),
  );
  return SongMatcher.findLocalMatch(
        song,
        localSongs.where((local) => local.hasLocalFile),
      ) !=
      null;
});