import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/caldav_screen.dart';

void main() {
  test('CalDAV 配置保存和连接测试必须调用 Slowlight API 而非目标 CalDAV 主机', () {
    final source = File('lib/services/api_service.dart').readAsStringSync();
    final save = source.split('saveCalDAVConfig({').last.split('testCalDAVConnection({').first;
    final connectionTest = source.split('testCalDAVConnection({').last.split('getCalDAVStatus()').first;
    expect(save, contains(r"Uri.parse('${ApiService.baseUrl}/caldav/config')"));
    expect(connectionTest, contains(r"Uri.parse('${ApiService.baseUrl}/caldav/test')"));
    expect(save, contains("'base_url': baseUrl"));
    expect(connectionTest, contains("'base_url': baseUrl"));
  });

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
