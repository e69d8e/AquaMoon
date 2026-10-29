import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyrics_display_settings.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';

class LyricsDisplaySettingsNotifier
    extends StateNotifier<LyricsDisplaySettings> {
  final StorageService _storageService;

  LyricsDisplaySettingsNotifier(this._storageService)
    : super(_storageService.getSavedLyricsDisplaySettings());

  void update(LyricsDisplaySettings settings) {
    state = settings;
    _storageService.saveLyricsDisplaySettings(settings);
  }

  /// 滑条拖动过程中的即时预览：只更新内存状态，不落盘。
  /// 拖动每帧都调用 [update] 会对 Hive 产生几十次无谓写入；拖完由
  /// [persist] 统一持久化。
  void updateLive(LyricsDisplaySettings settings) {
    state = settings;
  }

  /// 把当前状态写入磁盘（与 [updateLive] 配对使用）。
  void persist() {
    _storageService.saveLyricsDisplaySettings(state);
  }

  void resetToDefaults() => update(LyricsDisplaySettings.defaults);
}

final lyricsDisplaySettingsProvider =
    StateNotifierProvider<LyricsDisplaySettingsNotifier, LyricsDisplaySettings>((
      ref,
    ) {
      return LyricsDisplaySettingsNotifier(ref.watch(storageServiceProvider));
    });
