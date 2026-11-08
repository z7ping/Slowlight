import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single configuration for every Slowlight secret (auth, OAuth, AI, Feishu).
///
/// flutter_secure_storage 9.2.4 migrates *all* values from its default Android
/// SharedPreferences to EncryptedSharedPreferences when this flag is true.
/// Mixing true/false between modules makes credentials appear to disappear
/// without a Dart-level delete. Keep the original storage name/key prefix so
/// the plugin can migrate existing values in place. Do not enable resetOnError.
const FlutterSecureStorage slowlightSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
