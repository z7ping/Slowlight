import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';
import 'http_util.dart';

/// Server deployment provenance. Missing fields mean the server did not
/// provide verifiable metadata; they must not be replaced by local timestamps.
class ServerVersionInfo {
  final String? version;
  final String? deployedAt;
  final String? commitTime;
  final String? commitHash;
  final String? builtAt;

  const ServerVersionInfo({
    this.version,
    this.deployedAt,
    this.commitTime,
    this.commitHash,
    this.builtAt,
  });

  factory ServerVersionInfo.fromJson(Map<String, dynamic> json) {
    String? field(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    return ServerVersionInfo(
      version: field('version'),
      deployedAt: field('deployed_at'),
      commitTime: field('commit_time'),
      commitHash: field('commit_hash'),
      builtAt: field('built_at'),
    );
  }
}

class AppInfoService {
  AppInfoService._();

  static final instance = AppInfoService._();
  PackageInfo? _info;

  Future<PackageInfo> load() async =>
      _info ??= await PackageInfo.fromPlatform();

  /// Public version endpoint; no token required, even in Local Data mode.
  /// Always fetch remotely, so opening About after an upgrade sees the new
  /// deployment without persisting stale metadata.
  Future<ServerVersionInfo> loadServerVersion() async {
    ApiService.validateCloudEndpoint();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/version'),
    ).timeout(ApiService.getTimeout);
    if (response.statusCode != 200) {
      throw StateError('服务端版本查询失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        !decoded.containsKey('version')) {
      throw const FormatException('服务端版本响应格式无效');
    }
    return ServerVersionInfo.fromJson(decoded);
  }
}
