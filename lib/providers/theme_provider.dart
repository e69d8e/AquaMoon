import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../services/storage_service.dart';
import 'audio_provider.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final StorageService _storageService;

  ThemeModeNotifier(this._storageService)
    : super(_storageService.getSavedThemeMode());

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _storageService.saveThemeMode(mode);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier(ref.watch(storageServiceProvider));
});

class ThemePaletteNotifier extends StateNotifier<AppPalette> {
  final StorageService _storageService;

  ThemePaletteNotifier(this._storageService)
    : super(AppPalette.byId(_storageService.getSavedThemeId()));

  void setPalette(AppPalette palette) {
    state = palette;
    _storageService.saveThemeId(palette.id);
  }
}

final themePaletteProvider =
    StateNotifierProvider<ThemePaletteNotifier, AppPalette>((ref) {
      return ThemePaletteNotifier(ref.watch(storageServiceProvider));
    });
