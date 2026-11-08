import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/notification_service.dart';

void main() {
  test('P05 notification uses absolute UTC instant, not Shanghai wall time', () {
    for (final instant in [
      DateTime.utc(2026, 3, 8, 9, 30),
      DateTime.utc(2026, 11, 1, 8, 30),
      DateTime.utc(2026, 11, 1, 9, 30),
    ]) {
      final scheduled = NotificationService.toScheduleInstant(instant);
      expect(scheduled.timeZoneOffset, Duration.zero);
      expect(scheduled.millisecondsSinceEpoch,
          instant.millisecondsSinceEpoch);
    }
  });
}
