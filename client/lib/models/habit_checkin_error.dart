import 'habit_timezone_policy.dart';

class HabitCheckinRejected extends HabitKnownWriteBlock {
  const HabitCheckinRejected(super.message);
}

class HabitOffScheduleConfirmation extends HabitCheckinRejected {
  static const code = 'habit_off_schedule';

  final String date;
  const HabitOffScheduleConfirmation(this.date, super.message);
}

class HabitCheckinCancelled implements Exception {
  const HabitCheckinCancelled();
}
