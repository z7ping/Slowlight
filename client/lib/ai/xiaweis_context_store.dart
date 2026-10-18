import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 用户主动维护的个人背景，不内置任何具体用户的私有资料。
/// 首版仅保存在当前设备；不会自动同步到 Slowlight Cloud。
class XiaweisContextStore {
  static const storageKey = 'slowlight.xiaweis.personal_context.v1';
  static const maxLength = 12000;

  final FlutterSecureStorage storage;

  XiaweisContextStore({FlutterSecureStorage? storage})
      : storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<String> read() async => (await storage.read(key: storageKey)) ?? '';

  Future<void> save(String value) async {
    final normalized = value.trim();
    if (normalized.length > maxLength) {
      throw ArgumentError('个人资料最多 12000 字符');
    }
    if (normalized.isEmpty) {
      await storage.delete(key: storageKey);
    } else {
      await storage.write(key: storageKey, value: normalized);
    }
  }
}
