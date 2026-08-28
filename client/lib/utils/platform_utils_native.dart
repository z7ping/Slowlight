import 'dart:io';
import '../services/lock_screen.dart';

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> lockScreen({String message = '休息中'}) async {
  await LockScreenManager().lock(message: message);
}

Future<void> unlockScreen() async {
  LockScreenManager().unlock();
}
