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
