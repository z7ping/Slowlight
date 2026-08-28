import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('Cloud auth rejects local token', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'local:123'});
    expect(await AuthService.isLoggedIn(), isFalse);
  });

  test('Cloud auth rejects expired JWT', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 60);
    SharedPreferences.setMockInitialValues({'auth_token': token});
    expect(await AuthService.isLoggedIn(), isFalse);
  });

  test('Cloud auth accepts unexpired JWT', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    SharedPreferences.setMockInitialValues({'auth_token': token});
    expect(await AuthService.isLoggedIn(), isTrue);
  });

  test('Legacy token is migrated out of SharedPreferences', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    SharedPreferences.setMockInitialValues({'auth_token': token});

    expect(await AuthService.getToken(), token);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'auth_token'), token);
  });
}

String _jwt({required int exp}) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'exp': exp})}.signature';
}
