// 原生平台 — 可用 dart:io 检测桌面
import 'dart:io' show Platform;

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
