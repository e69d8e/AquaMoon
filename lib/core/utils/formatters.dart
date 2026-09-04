import 'package:intl/intl.dart';

class Formatters {
  static String formatDuration(Duration? duration) {
    if (duration == null || duration == Duration.zero) {
      return '00:00';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hStr = hours.toString().padLeft(2, '0');
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Format listening duration into human-readable Chinese string
  /// Examples: "3 小时 25 分钟", "45 分钟", "0 分钟"
  static String formatListeningDuration(Duration duration, {bool short = false}) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes <= 0) return short ? '0分' : '0 分钟';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      if (minutes > 0) {
        return short ? '$hours小时$minutes分' : '$hours 小时 $minutes 分钟';
      }
      return short ? '$hours小时' : '$hours 小时';
    }

    return short ? '$minutes分' : '$minutes 分钟';
  }

  /// Format DateTime to yyyy-MM-dd
  static String formatDateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Format friendly Chinese date
  static String formatChineseDate(DateTime date, {bool includeWeekDay = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diffDays = target.difference(today).inDays;

    final weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekDayStr = weekDays[date.weekday - 1];

    if (diffDays == 0) {
      return '今天 (${DateFormat('M月d日').format(date)} $weekDayStr)';
    } else if (diffDays == -1) {
      return '昨天 (${DateFormat('M月d日').format(date)} $weekDayStr)';
    } else if (diffDays == 1) {
      return '明天 (${DateFormat('M月d日').format(date)} $weekDayStr)';
    }

    if (date.year == now.year) {
      return includeWeekDay
          ? '${DateFormat('M月d日').format(date)} $weekDayStr'
          : DateFormat('M月d日').format(date);
    }
    return includeWeekDay
        ? '${DateFormat('yyyy年M月d日').format(date)} $weekDayStr'
        : DateFormat('yyyy年M月d日').format(date);
  }
}
