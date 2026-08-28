import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner delegates first visibility to Dart startup', () {
    final flutterWindow =
        File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(flutterWindow, isNot(contains('this->Show();')));
    expect(
      flutterWindow,
      contains('RegisterPlugins(flutter_controller_->engine());'),
    );
  });

  test('Windows runner refreshes the Slowlight taskbar identity shortcut', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final identity = File('windows/runner/app_identity.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(main, contains('ConfigureWindowsAppIdentity();'));
    expect(identity, contains('SetCurrentProcessExplicitAppUserModelID'));
    expect(identity, contains('FOLDERID_Programs'));
    expect(identity, contains('kAppUserModelId[] = L"Slowlight"'));
    expect(identity, contains('kDisplayName[]'));
    expect(identity, contains('std::wstring(kDisplayName) + L".lnk"'));
    expect(identity, contains('SetPath(executable.c_str())'));
    expect(identity, contains('SetIconLocation(executable.c_str(), 0)'));
    expect(identity, contains('PKEY_AppUserModel_ID'));
    expect(cmake, contains('"app_identity.cpp"'));
    expect(cmake, contains('"propsys.lib"'));
  });

  test('Windows runner assigns large and small icons directly to each HWND',
      () {
    final header = File('windows/runner/win32_window.h').readAsStringSync();
    final implementation =
        File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(header, contains('void UpdateWindowIcons(UINT dpi);'));
    expect(implementation, contains('WM_SETICON, ICON_BIG'));
    expect(implementation, contains('WM_SETICON, ICON_SMALL'));
    expect(implementation, contains('GetSystemMetricsForDpi'));
    expect(implementation, contains('UpdateWindowIcons(LOWORD(wparam));'));
  });

  test('Windows runner retains multi-window plugin registration as fallback',
      () {
    final flutterWindow =
        File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(
      flutterWindow,
      contains('#include <desktop_multi_window/desktop_multi_window_plugin.h>'),
    );
    expect(
      flutterWindow,
      contains('DesktopMultiWindowSetWindowCreatedCallback'),
    );
    expect(flutterWindow, contains('RegisterPlugins(registry);'));
  });

  test('Windows runner defaults to software rendering with a Slowlight escape hatch',
      () {
    final main = File('windows/runner/main.cpp').readAsStringSync();

    expect(main, contains('ConfigureRenderingMode();'));
    expect(main, contains('SLOWLIGHT_HARDWARE_RENDERING'));
    expect(main, isNot(contains('FOCUSLIST_HARDWARE_RENDERING')));
    expect(main, contains('FLUTTER_ENGINE_SWITCH_'));
    expect(main, contains('enable-software-rendering=true'));
    expect(main, contains('existing_switch_count + 1'));
    expect(
      main.indexOf('ConfigureRenderingMode();'),
      lessThan(main.indexOf('flutter::DartProject project')),
    );
  });
}
