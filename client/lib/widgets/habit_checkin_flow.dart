import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_checkin_error.dart';
import '../models/habit_timezone_policy.dart';
import '../ui/fx.dart';
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
  String? confirmedDate;

  Future<bool> confirm(String date, String message) async {
    final accepted = await FxDialog.confirm(
      context: context,
      title: '计划外打卡',
      content: message,
      confirmText: '仍然打卡',
    );
    if (accepted != true || !context.mounted) return false;
    confirmedDate = date;
    return true;
  }

  Future<void> send(Map<String, dynamic> value) => submit({
        ...value,
        'client_key': clientKey,
        if (confirmedDate != null) 'confirmed_off_schedule_date': confirmedDate,
      });

  Future<void> save(Map<String, dynamic> value) async {
    try {
      await send(value);
    } on HabitOffScheduleConfirmation catch (error) {
      if (!context.mounted || confirmedDate == error.date) rethrow;
      if (!await confirm(error.date, error.message)) {
        throw const HabitCheckinCancelled();
      }
      await send(value);
    }
  }

  if (habit.offScheduleDate case final date? when recordDate == null) {
    if (!await confirm(date, '$date 没有安排打卡，仍然记录这次完成？')) {
      return false;
    }
  }
  if (!context.mounted) return false;
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
    } on HabitCheckinCancelled {
      return false;
    } on HabitKnownWriteBlock catch (error) {
      if (context.mounted) {
        FxNotice.showContent(context, Text(error.message),
            variant: FxNoticeVariant.warning);
      }
      return false;
    } catch (_) {
      if (!context.mounted) return false;
      return await HabitCheckinDialog.show(
            context,
            habit: habit,
            confirmedOffScheduleDay: DateTime.tryParse(confirmedDate ?? ''),
            onSubmit: save,
            pendingValue: value,
            initialError: '保存结果未确认。可重试保存；关闭后请先核对明细，避免重复记录。',
          ) !=
          null;
    }
  }
  return await HabitCheckinDialog.show(context,
          habit: habit,
          recordDate: recordDate,
          confirmedOffScheduleDay: DateTime.tryParse(confirmedDate ?? ''),
          onSubmit: save) !=
      null;
}
