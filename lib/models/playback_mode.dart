enum PlaybackMode {
  sequence,  // 顺序播放
  repeatAll, // 列表循环
  repeatOne, // 单曲循环
  shuffle,   // 随机播放
}

extension PlaybackModeExtension on PlaybackMode {
  String get label {
    switch (this) {
      case PlaybackMode.sequence:
        return '顺序播放';
      case PlaybackMode.repeatAll:
        return '列表循环';
      case PlaybackMode.repeatOne:
        return '单曲循环';
      case PlaybackMode.shuffle:
        return '随机播放';
    }
  }

  PlaybackMode next() {
    switch (this) {
      case PlaybackMode.sequence:
        return PlaybackMode.repeatAll;
      case PlaybackMode.repeatAll:
        return PlaybackMode.repeatOne;
      case PlaybackMode.repeatOne:
        return PlaybackMode.shuffle;
      case PlaybackMode.shuffle:
        return PlaybackMode.sequence;
    }
  }
}
