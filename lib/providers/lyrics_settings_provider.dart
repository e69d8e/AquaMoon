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

  void resetToDefaults() => update(LyricsDisplaySettings.defaults);
}

final lyricsDisplaySettingsProvider =
    StateNotifierProvider<LyricsDisplaySettingsNotifier, LyricsDisplaySettings>((
      ref,
    ) {
      return LyricsDisplaySettingsNotifier(ref.watch(storageServiceProvider));
    });
