/// 均衡器频段信息（与平台无关的描述，view 层据此渲染滑杆）。
class EqualizerBandInfo {
  final int index;

  /// 中心频率（Hz）。
  final double centerHz;
  final double minDb;
  final double maxDb;
  final double gainDb;

  const EqualizerBandInfo({
    required this.index,
    required this.centerHz,
    required this.minDb,
    required this.maxDb,
    required this.gainDb,
  });
}

/// 一次性读取的均衡器参数快照。
class EqualizerSnapshot {
  final double minDb;
  final double maxDb;
  final List<EqualizerBandInfo> bands;

  const EqualizerSnapshot({
    required this.minDb,
    required this.maxDb,
    required this.bands,
  });
}
