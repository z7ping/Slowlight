import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/task_create_sheet.dart';

void main() {
  group('TaskCreateSheet', () {
    test('快速创建默认使用无优先级并安排到今天', () {
      const sheet = TaskCreateSheet(quickMode: true);

      expect(sheet.initialPriority, 'none');
      expect(sheet.defaultDueToday, isTrue);
    });

    test('四象限入口可以预设优先级且不强制安排到今天', () {
      const sheet = TaskCreateSheet(
        quickMode: true,
        initialPriority: 'important',
        defaultDueToday: false,
      );

      expect(sheet.initialPriority, 'important');
      expect(sheet.defaultDueToday, isFalse);
    });
  });
}
