import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
  AppInfoService._();

  static final instance = AppInfoService._();
  PackageInfo? _info;

  Future<PackageInfo> load() async =>
      _info ??= await PackageInfo.fromPlatform();
}
