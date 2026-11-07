import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Cloud habit dates are owned by the server account timezone; a cached
/// offline write must never silently use a different device calendar.
abstract class HabitKnownWriteBlock implements Exception {
  const HabitKnownWriteBlock(this.message);
  final String message;
  @override
  String toString() => message;
}

class HabitTimezoneMismatch extends HabitKnownWriteBlock {
  const HabitTimezoneMismatch(super.message);
}

class HabitGoalVersionRequiresOnline extends HabitKnownWriteBlock {
  const HabitGoalVersionRequiresOnline()
      : super('目标或频率变更需联网保存，以免离线修改丢失历史版本；本次未写入');
}

abstract final class HabitTimezonePolicy {
  static bool _initialized = false;

  static tz.Location _accountLocation(String? accountZone) {
    if (accountZone == null || accountZone.trim().isEmpty) {
      throw const HabitTimezoneMismatch(
        '账号时区尚未确认，请联网刷新账号资料后再离线记录',
      );
    }
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    try {
      return tz.getLocation(accountZone);
    } catch (_) {
      throw const HabitTimezoneMismatch(
        '账号时区无效，请联网刷新账号资料后再记录',
      );
    }
  }

  /// Compares actual UTC offsets across the whole current annual cycle,
  /// not just today: identical offsets now can conceal different DST rules.
  /// No IANA device API is required; DateTime.toLocal is the OS authority.
  static void requireCompatibleDeviceCalendar(String? accountZone,
      {DateTime? now, String? recordDate,
      Duration Function(DateTime)? deviceOffsetAt}) {
    final location = _accountLocation(accountZone);
    final current = (now ?? DateTime.now()).toUtc();
    final probes = <DateTime>[
      current,
      for (var month = 0; month < 12; month++)
        DateTime.utc(current.year, month + 1, 15, 12),
    ];
    if (recordDate != null) {
      final date = DateTime.tryParse(recordDate);
      if (date != null) {
        probes.add(DateTime.utc(date.year, date.month, date.day, 12));
      }
    }
    for (final instant in probes) {
      final deviceOffset =
          deviceOffsetAt?.call(instant) ?? instant.toLocal().timeZoneOffset;
      final accountOffset = tz.TZDateTime.from(instant, location).timeZoneOffset;
      if (deviceOffset != accountOffset) {
        throw const HabitTimezoneMismatch(
          '设备时区与云端账号时区不同；为避免打卡日期和计划时段错位，'
          '请先联网记录，离线记录已安全阻止',
        );
      }
    }
  }
}
