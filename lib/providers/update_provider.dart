import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/storage_service.dart';
import '../services/update_service.dart';
import 'audio_provider.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.dispose);
  return service;
});

/// Current app version from pubspec (e.g. `1.0.2`), without the build number.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

class AutoCheckUpdatesNotifier extends StateNotifier<bool> {
  final StorageService _storageService;

  AutoCheckUpdatesNotifier(this._storageService)
    : super(_storageService.getAutoCheckUpdates());

  void setAutoCheckUpdates(bool enabled) {
    state = enabled;
    _storageService.saveAutoCheckUpdates(enabled);
  }
}

final autoCheckUpdatesProvider =
    StateNotifierProvider<AutoCheckUpdatesNotifier, bool>((ref) {
      return AutoCheckUpdatesNotifier(ref.watch(storageServiceProvider));
    });
