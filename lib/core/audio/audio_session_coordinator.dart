import 'dart:async';
import 'package:audio_session/audio_session.dart';

class AudioSessionCoordinator {
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function(double) onSetVolume;
  final double Function() getCurrentVolume;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  bool _playInterrupted = false;

  AudioSessionCoordinator({
    required this.onPause,
    required this.onResume,
    required this.onSetVolume,
    required this.getCurrentVolume,
  });

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Listen for audio focus interruptions (e.g. phone call, Siri, alarm)
    _interruptionSub = session.interruptionEventStream.listen((event) async {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Lower volume to 30%
            await onSetVolume(getCurrentVolume() * 0.3);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _playInterrupted = true;
            await onPause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Restore volume
            await onSetVolume(getCurrentVolume());
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) {
              _playInterrupted = false;
              await onResume();
            }
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Listen for headphones unplugged / Bluetooth disconnected
    _noisySub = session.becomingNoisyEventStream.listen((_) async {
      await onPause();
    });
  }

  void dispose() {
    _interruptionSub?.cancel();
    _noisySub?.cancel();
  }
}
