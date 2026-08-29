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

  test('Windows release identity is owned by the installer shortcut', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final identity = File('windows/runner/app_identity.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    final installer =
        File('windows/installer/slowlight.iss').readAsStringSync();

    expect(main, contains('ConfigureWindowsAppIdentity();'));
    expect(main, contains('ConfigureWindowsWindowIdentity(window.GetHandle())'));
    expect(identity, contains('SetCurrentProcessExplicitAppUserModelID'));
    expect(identity, contains('kAppUserModelId[] = L"z7ping.Slowlight"'));
    expect(
      identity,
      contains('kDebugAppUserModelId[] = L"z7ping.Slowlight.Debug"'),
    );
    expect(identity, contains('#include <shobjidl.h>'));
    expect(
      identity.indexOf('#include <shobjidl.h>'),
      lessThan(identity.indexOf('#ifdef _DEBUG')),
    );
    expect(identity, contains('#ifndef _DEBUG'));
    expect(identity, contains('return true;\n#else\n  IPropertyStore* store'));
    expect(identity, contains('PKEY_AppUserModel_ID'));
    expect(identity, contains('PKEY_AppUserModel_RelaunchIconResource'));
    expect(identity, contains('kAppIconResourceSuffix[] = L",-101"'));
    expect(identity, isNot(contains('FOLDERID_Programs')));
    expect(identity, isNot(contains('SetPath(executable.c_str())')));

    expect(installer, contains('#define MyAppUserModelId "z7ping.Slowlight"'));
    expect(installer, contains('AppUserModelID: "{#MyAppUserModelId}"'));
    expect(installer, contains('Name: "{userprograms}\\所行映我"'));
    expect(installer, contains('Filename: "{app}\\{#MyExeName}"'));
    expect(
      installer,
      contains(
        'Source: "..\\runner\\resources\\app_icon.ico"; DestDir: "{app}\\resources"; DestName: "{#MyAppIconName}"',
      ),
    );
    expect(
      installer,
      contains(
        'IconFilename: "{app}\\resources\\{#MyAppIconName}"; IconIndex: 0; AppUserModelID: "{#MyAppUserModelId}"',
      ),
    );
    expect(installer,
        contains('SetupIconFile=..\\runner\\resources\\app_icon.ico'));
    expect(
      installer,
      contains('UninstallDisplayIcon={app}\\resources\\{#MyAppIconName}'),
    );

    expect(cmake, contains('"app_identity.cpp"'));
    expect(cmake, contains('"shell32.lib"'));
    expect(cmake, contains('"propsys.lib"'));
  });

  test('Windows installer wizard uses pinned Simplified Chinese messages', () {
    final installer =
        File('windows/installer/slowlight.iss').readAsStringSync();
    final prepareScript = File('windows/installer/prepare_chinese_messages.ps1')
        .readAsStringSync();

    expect(installer, contains('[Languages]'));
    expect(
      installer,
      contains(
        'Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"',
      ),
    );
    expect(
      prepareScript,
      contains('1ff90acc4ed4aee82b1cda43253243deee3daed4'),
    );
    expect(
      prepareScript,
      contains('30d997321197c7c96d8e111e9ddd6c0ca8da5f09'),
    );
    expect(prepareScript, contains('git hash-object'));
  });

  test('Windows installer can request a real app shutdown without breaking close-to-tray',
      () {
    final flutterWindow =
        File('windows/runner/flutter_window.cpp').readAsStringSync();
    final installer =
        File('windows/installer/slowlight.iss').readAsStringSync();
    final dartMain = File('lib/main.dart').readAsStringSync();

    expect(flutterWindow, contains('WM_QUERYENDSESSION'));
    expect(flutterWindow, contains('WM_ENDSESSION'));
    expect(flutterWindow, contains('ENDSESSION_CLOSEAPP'));
    expect(flutterWindow, contains('::DestroyWindow(hwnd);'));
    expect(
      flutterWindow.indexOf('WM_QUERYENDSESSION'),
      lessThan(flutterWindow.indexOf('HandleTopLevelWindowProc')),
    );
    expect(
      flutterWindow.indexOf('WM_ENDSESSION'),
      lessThan(flutterWindow.indexOf('HandleTopLevelWindowProc')),
    );

    expect(installer, contains('CloseApplications=yes'));
    expect(installer, contains('CloseApplicationsFilter={#MyExeName}'));
    expect(installer, contains('RestartApplications=no'));

    // User clicking the normal window close button should still hide to tray.
    expect(dartMain, contains('await windowManager.setPreventClose(true);'));
    expect(dartMain, contains('await windowManager.hide();'));
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
