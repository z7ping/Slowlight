import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'auth_service.dart';

/// Windows / Android 共用的 GitHub 浏览器授权与一次性凭据领取。
/// 不需要 deep link；即使授权在外部浏览器完成，客户端也能恢复登录状态。
class GitHubSignIn {
  static Future<void> signIn({required bool Function() shouldContinue}) async {
    ApiService.validateCloudEndpoint();
    final start = await ApiService.post('/auth/github/start', body: {});
    final authUrl = Uri.parse(start['authorization_url'] as String);
    final sessionId = start['session_id'] as String;
    final pollToken = start['poll_token'] as String;
    if (authUrl.scheme != 'https' || authUrl.host != 'github.com') {
      throw StateError('GitHub 授权地址无效');
    }
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开浏览器，请检查系统默认浏览器');
    }
    // 后端授权会话 10 分钟有效，轮询不在请求 URL 中携带任何密钥。
    for (var attempt = 0; attempt < 200; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!shouldContinue()) return;
      final result = await ApiService.post('/auth/github/poll', body: {
        'session_id': sessionId,
        'poll_token': pollToken,
      });
      if (result['status'] == 'pending') continue;
      if (result['status'] == 'complete') {
        if (!shouldContinue()) return;
        await AuthService.completeOAuthLogin(result);
        return;
      }
      throw StateError('GitHub 登录状态异常，请重试');
    }
    throw StateError('GitHub 授权已超时，请重试');
  }
}
