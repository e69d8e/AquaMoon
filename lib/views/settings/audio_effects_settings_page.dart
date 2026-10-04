import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_toast.dart';
import '../../models/audio_effects.dart';
import '../../providers/audio_provider.dart';

/// 音效与均衡器设置页（仅 Android 提供）：
/// - 淡入淡出：暂停/恢复与睡眠定时器到点时对音量做短促渐变；
/// - 均衡器：基于系统 Equalizer 的多频段增益调节，带总开关。
class AudioEffectsSettingsPage extends ConsumerStatefulWidget {
  const AudioEffectsSettingsPage({super.key});

  @override
  ConsumerState<AudioEffectsSettingsPage> createState() =>
      _AudioEffectsSettingsPageState();
}

class _AudioEffectsSettingsPageState
    extends ConsumerState<AudioEffectsSettingsPage> {
  bool _fadeEnabled = false;
  bool _equalizerEnabled = false;
  EqualizerSnapshot? _snapshot;
  List<double>? _gains;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = ref.read(audioControllerProvider);
    final storage = ref.read(storageServiceProvider);
    final snapshot = controller.equalizerSupported
        ? await controller.loadEqualizerSnapshot()
        : null;

    if (!mounted) return;
    setState(() {
      _fadeEnabled = storage.getFadeEnabled();
      _equalizerEnabled = storage.getEqualizerEnabled();
      _snapshot = snapshot;
      if (snapshot != null) {
        final saved = storage.getEqualizerGains();
        _gains = List<double>.generate(
          snapshot.bands.length,
          (i) =>
              i < saved.length
                  ? saved[i].clamp(snapshot.minDb, snapshot.maxDb)
                  : snapshot.bands[i].gainDb,
        );
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(title: const Text('音效与均衡器')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (!supported) ...[
                  const SizedBox(height: 40),
                  Icon(
                    Icons.equalizer_rounded,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '音效功能目前仅在 Android 设备上提供',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 200),
                ] else ...[
                  _FadeCard(
                    enabled: _fadeEnabled,
                    onChanged: (enabled) async {
                      setState(() => _fadeEnabled = enabled);
                      await ref
                          .read(audioControllerProvider)
                          .setFadeEnabled(enabled);
                    },
                  ),
                  const SizedBox(height: 16),
                  _EqualizerCard(
                    enabled: _equalizerEnabled,
                    snapshot: _snapshot,
                    gains: _gains,
                    onEnabled: (enabled) async {
                      setState(() => _equalizerEnabled = enabled);
                      await ref
                          .read(audioControllerProvider)
                          .setEqualizerEnabled(enabled);
                    },
                    onBandChanged: (index, gain) {
                      setState(() {
                        if (_gains != null && index < _gains!.length) {
                          _gains![index] = gain;
                        }
                      });
                    },
                    onBandChangeEnd: (index, gain) async {
                      await ref
                          .read(audioControllerProvider)
                          .setEqualizerBandGain(index, gain);
                    },
                    onReset: () async {
                      final controller = ref.read(audioControllerProvider);
                      if (_snapshot == null) return;
                      final zeros = List<double>.filled(
                        _snapshot!.bands.length,
                        0.0,
                      );
                      await controller.setEqualizerGains(zeros);
                      if (!mounted) return;
                      setState(() => _gains = zeros);
                      if (!context.mounted) return;
                      AppToast.show(
                        context,
                        '均衡器已重置为平直',
                        icon: Icons.restart_alt_rounded,
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }
}

class _FadeCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _FadeCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.waves_rounded),
        title: const Text(
          '淡入淡出',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          '暂停与恢复播放时音量平滑过渡，睡眠定时到点淡出后停止',
          style: TextStyle(fontSize: 12),
        ),
        trailing: Switch(value: enabled, onChanged: onChanged),
      ),
    );
  }
}

class _EqualizerCard extends StatelessWidget {
  final bool enabled;
  final EqualizerSnapshot? snapshot;
  final List<double>? gains;
  final ValueChanged<bool> onEnabled;
  final void Function(int index, double gain) onBandChanged;
  final void Function(int index, double gain) onBandChangeEnd;
  final VoidCallback onReset;

  const _EqualizerCard({
    required this.enabled,
    required this.snapshot,
    required this.gains,
    required this.onEnabled,
    required this.onBandChanged,
    required this.onBandChangeEnd,
    required this.onReset,
  });

  static String _bandLabel(double hz) {
    if (hz >= 1000) {
      final khz = hz / 1000;
      return '${khz == khz.roundToDouble() ? khz.round() : khz.toStringAsFixed(1)}kHz';
    }
    return '${hz.round()}Hz';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.equalizer_rounded),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    '均衡器',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(value: enabled, onChanged: snapshot == null ? null : onEnabled),
              ],
            ),
            if (snapshot == null) ...[
              const SizedBox(height: 8),
              Text(
                '未检测到系统均衡器（可能播放器尚未初始化音频设备）',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: enabled ? 1.0 : 0.45,
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onReset,
                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                          label: const Text('重置', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      for (final band in snapshot!.bands)
                        _BandSlider(
                          band: band,
                          gain: gains != null && band.index < gains!.length
                              ? gains![band.index]
                              : band.gainDb,
                          onChanged: (value) => onBandChanged(band.index, value),
                          onChangeEnd: (value) =>
                              onBandChangeEnd(band.index, value),
                        ),
                      Text(
                        '调节范围 ${snapshot!.minDb.toStringAsFixed(0)} ~ ${snapshot!.maxDb.toStringAsFixed(0)} dB',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  final EqualizerBandInfo band;
  final double gain;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BandSlider({
    required this.band,
    required this.gain,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            _EqualizerCard._bandLabel(band.centerHz),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: gain.clamp(band.minDb, band.maxDb),
            min: band.minDb,
            max: band.maxDb,
            divisions: ((band.maxDb - band.minDb) * 2).round().clamp(1, 60),
            label: '${gain.toStringAsFixed(1)} dB',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: gain.abs() < 0.05
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
