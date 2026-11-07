import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/utils/local_time_boundary.dart';

void main() {
  test('dayRange is defined by local calendar day and queried as UTC instants', () {
    final localDay = DateTime(2026, 8, 21, 15, 30);
    final range = LocalTimeBoundary.dayRange(localDay);
    final localStart = DateTime(2026, 8, 21);
    final localEnd = DateTime(2026, 8, 22);

    expect(range.startUtc, localStart.toUtc().toIso8601String());
    expect(range.endUtc, localEnd.toUtc().toIso8601String());
    expect(range.contains(DateTime(2026, 8, 21, 12)), isTrue);
    expect(range.contains(localEnd), isFalse);
  });

  test('calendar offsets keep midnight and date across month and leap-day boundaries', () {
    final leapDay = DateTime(2024, 2, 29, 12, 45);
    expect(LocalTimeBoundary.addCalendarDays(leapDay, 1), DateTime(2024, 3, 1));
    expect(LocalTimeBoundary.addCalendarDays(leapDay, -1), DateTime(2024, 2, 28));
    expect(LocalTimeBoundary.addCalendarDays(DateTime(2026, 1, 1), -7),
        DateTime(2025, 12, 25));
    expect(LocalTimeBoundary.dayEnd(leapDay), DateTime(2024, 3, 1));
  });

  test('day ranges use consecutive local midnights around possible DST dates', () {
    for (final day in [
      DateTime(2026, 3, 8, 15),
      DateTime(2026, 11, 1, 15),
    ]) {
      final range = LocalTimeBoundary.dayRange(day);
      final start = DateTime(day.year, day.month, day.day);
      final next = DateTime(day.year, day.month, day.day + 1);
      expect(range.localStart, start);
      expect(range.localEnd, next);
      expect(range.startUtc, start.toUtc().toIso8601String());
      expect(range.endUtc, next.toUtc().toIso8601String());
      expect(range.contains(next), isFalse);
    }
  });

  test('weekStart is local Monday even over month/year boundaries', () {
    expect(LocalTimeBoundary.weekStart(DateTime(2026, 11, 1, 22)),
        DateTime(2026, 10, 26));
    expect(LocalTimeBoundary.weekStart(DateTime(2027, 1, 1, 10)),
        DateTime(2026, 12, 28));
  });

  test('dateKey keeps calendar date semantics', () {
    expect(
      LocalTimeBoundary.dateKey(DateTime(2026, 1, 2, 23, 59)),
      '2026-01-02',
    );
  });

  test('parseInstant converts stored instant to device-local time', () {
    final expected = DateTime.parse('2026-08-21T03:00:00Z').toLocal();
    expect(
      LocalTimeBoundary.parseInstant('2026-08-21T03:00:00Z'),
      expected,
    );
  });
}
