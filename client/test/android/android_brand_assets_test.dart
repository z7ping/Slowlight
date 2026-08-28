import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 使用 Slowlight 技术身份与所行映我显示名', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(gradle, contains('namespace = "site.z7ping.slowlight"'));
    expect(gradle, contains('applicationId = "site.z7ping.slowlight"'));
    expect(gradle, isNot(contains('site.z7ping.focuslist')));

    expect(manifest, contains('android:label="所行映我"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher"'));
  });

  test('Android 自适应图标使用正式深色背景与单色图标', () {
    final colors =
        File('android/app/src/main/res/values/colors.xml').readAsStringSync();
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final adaptiveV33 = File(
      'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml',
    ).readAsStringSync();

    expect(
      colors,
      contains('<color name="ic_launcher_background">#0B1220</color>'),
    );
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
    expect(adaptiveV33, contains('@color/ic_launcher_background'));
    expect(adaptiveV33, contains('@mipmap/ic_launcher_foreground'));
    expect(adaptiveV33, contains('@drawable/ic_launcher_monochrome'));
  });
}
