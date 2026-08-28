#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <cwchar>

#include "app_identity.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

bool EnvironmentVariableEquals(const wchar_t* name, const wchar_t* expected) {
  wchar_t value[32] = {};
  const DWORD length = ::GetEnvironmentVariableW(name, value, 32);
  return length > 0 && length < 32 && std::wcscmp(value, expected) == 0;
}

int ReadEngineSwitchCount() {
  wchar_t value[16] = {};
  const DWORD length =
      ::GetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", value, 16);
  if (length == 0 || length >= 16) {
    return 0;
  }

  wchar_t* end = nullptr;
  const long count = std::wcstol(value, &end, 10);
  if (end == value || *end != L'\0' || count < 0 || count >= 100) {
    return 0;
  }
  return static_cast<int>(count);
}

bool HasSoftwareRenderingSwitch(int switch_count) {
  for (int index = 1; index <= switch_count; ++index) {
    wchar_t name[64] = {};
    swprintf_s(name, _countof(name), L"FLUTTER_ENGINE_SWITCH_%d", index);
    if (EnvironmentVariableEquals(name, L"enable-software-rendering=true")) {
      return true;
    }
  }
  return false;
}

void ConfigureRenderingMode() {
  if (EnvironmentVariableEquals(L"SLOWLIGHT_HARDWARE_RENDERING", L"1")) {
    return;
  }
  const int existing_switch_count = ReadEngineSwitchCount();
  if (HasSoftwareRenderingSwitch(existing_switch_count)) {
    return;
  }

  const int software_switch_index = existing_switch_count + 1;
  wchar_t switch_count[16] = {};
  wchar_t switch_name[64] = {};
  swprintf_s(switch_count, _countof(switch_count), L"%d",
             software_switch_index);
  swprintf_s(switch_name, _countof(switch_name),
             L"FLUTTER_ENGINE_SWITCH_%d", software_switch_index);
  ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", switch_count);
  ::SetEnvironmentVariableW(switch_name,
                            L"enable-software-rendering=true");
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // WinToast/local_notifier requires a matching Start Menu shortcut. Refresh
  // it on every launch because flutter run and installed builds can live at
  // different paths; a stale shortcut makes the taskbar resolve no icon.
  ConfigureWindowsAppIdentity();

  ConfigureRenderingMode();
  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"\u6240\u884C\u6620\u6211 \u00B7 Slowlight", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
