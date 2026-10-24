import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../utils/habit_record_key.dart';
import 'habit_checkin_dialog.dart';

/// 首页、工具页和补卡共用同一字段契约与幂等重试生命周期。
/// 同一次提交失败后固定字段和 client_key，避免多次习惯重试生成额外日志。
Future<bool> recordHabit(
  BuildContext context, {
  required Habit habit,
  required Future<void> Function(Map<String, dynamic>) submit,
  bool detailed = false,
  DateTime? recordDate,
}) async {
  final clientKey = createHabitRecordKey();
  Future<void> save(Map<String, dynamic> value) => submit({
        ...value,
        'client_key': clientKey,
      });
  final needsForm = detailed ||
      recordDate != null ||
      habit.showCheckinDialog ||
      habit.recordType == 'count' ||
      habit.recordTimeLabel.isNotEmpty;
  if (!needsForm) {
    const value = <String, dynamic>{'note': ''};
    try {
      await save(value);
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      return await HabitCheckinDialog.show(
            context,
            habit: habit,
            onSubmit: save,
            pendingValue: value,
            initialError: '保存结果未确认。可重试保存；关闭后请先核对明细，避免重复记录。',
          ) !=
          null;
    }
  }
  return await HabitCheckinDialog.show(context,
          habit: habit, recordDate: recordDate, onSubmit: save) !=
      null;
}
