import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/migration_service.dart';

void main() {
  test('X11 迁移回执只能恢复到执行迁移时的云端账号', () {
    expect(() => MigrationService.requireRecoveryAccount(25, 25),
        returnsNormally);
    expect(() => MigrationService.requireRecoveryAccount(25, 26),
        throwsStateError);
    expect(() => MigrationService.requireRecoveryAccount(25, null),
        throwsStateError);
    // Legacy rows have no account binding: never guess their owner.
    expect(() => MigrationService.requireRecoveryAccount(null, 25),
        throwsStateError);
    expect(() => MigrationService.requireRecoveryAccount(0, 25),
        throwsStateError);
  });
}
