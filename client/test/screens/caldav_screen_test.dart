import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/caldav_screen.dart';

void main() {
  group('12 CalDAV 原有表单校验语义', () {
    test('服务器地址必填且只能使用 HTTP 或 HTTPS', () {
      expect(CalDavFormValidation.serverUrl(''), '请输入服务器地址');
      expect(CalDavFormValidation.serverUrl('ftp://example.com'),
          '请输入有效地址（以 http:// 或 https:// 开头）');
      expect(CalDavFormValidation.serverUrl('https://example.com'), isNull);
      expect(CalDavFormValidation.serverUrl('http://example.com'), isNull);
    });

    test('用户名、凭证、项目路径仍必填', () {
      expect(CalDavFormValidation.username(' '), '请输入用户名');
      expect(CalDavFormValidation.password(''), '请输入密码或访问令牌');
      expect(CalDavFormValidation.paths(' \n '), '请至少输入一个项目路径');
      expect(CalDavFormValidation.username('alice'), isNull);
      expect(CalDavFormValidation.password('secret'), isNull);
      expect(CalDavFormValidation.paths('/dav/projects/1'), isNull);
    });
  });
}
