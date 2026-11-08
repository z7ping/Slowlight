import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single platform-storage configuration for every Slowlight secret.
///
/// flutter_secure_storage 9.2.4 on Android migrates *all* keys from its
/// legacy SharedPreferences store to EncryptedSharedPreferences when
/// encryptedSharedPreferences is enabled. Mixing this with a default
/// FlutterSecureStorage() reader makes migrated credentials appear missing.
///
/// Keep the existing preference file name and key prefix: the plugin's
/// built-in migration handles legacy data without a second, custom migration.
abstract final class AppSecureStorage {
  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
}
