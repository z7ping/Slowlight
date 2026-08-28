/// Web 端：无锁屏功能，方法为空实现
bool get isDesktop => false;

Future<void> lockScreen({String message = '休息中'}) async {}

Future<void> unlockScreen() async {}
